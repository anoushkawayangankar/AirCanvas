import Foundation
import XCTest
@testable import AirCanvas

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testFreshDefaultsRequireOnboarding() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = OnboardingState(defaults: defaults)

        XCTAssertTrue(state.requiresOnboarding)
    }

    func testCompletionPersistsAcrossStateRecreation() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunchState = OnboardingState(defaults: defaults)
        firstLaunchState.completeOnboarding()

        let relaunchedState = OnboardingState(defaults: defaults)

        XCTAssertFalse(firstLaunchState.requiresOnboarding)
        XCTAssertFalse(relaunchedState.requiresOnboarding)
        XCTAssertTrue(defaults.bool(forKey: OnboardingState.completionKey))
    }

    func testCompletedOnboardingDoesNotResetWithoutExplicitDataRemoval() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: OnboardingState.completionKey)

        XCTAssertFalse(OnboardingState(defaults: defaults).requiresOnboarding)
        XCTAssertFalse(OnboardingState(defaults: defaults).requiresOnboarding)
    }

    func testVersionedFlowRequestsPermissionOnlyAfterEducation() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let permissions = PermissionSpy(status: .notDetermined, requestedStatus: .authorized)
        let state = OnboardingState(defaults: defaults, permissionProvider: permissions, capabilityChecker: CapabilitySpy(.supported))

        await state.advance()
        XCTAssertEqual(state.step, .interactionBasics)
        await state.advance()
        XCTAssertEqual(state.step, .cameraEducation)
        XCTAssertEqual(permissions.requestCount, 0)
        await state.advance()
        XCTAssertEqual(permissions.requestCount, 1)
        XCTAssertTrue(state.requiresOnboarding)
        XCTAssertEqual(state.step, .spatialPreparation)
    }

    func testDeniedAndUnsupportedStatesAreTypedAndDoNotCompleteSpatialFlow() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let denied = OnboardingState(defaults: defaults, permissionProvider: PermissionSpy(status: .denied, requestedStatus: .denied), capabilityChecker: CapabilitySpy(.supported))
        await denied.advance(); await denied.advance(); await denied.advance()
        XCTAssertEqual(denied.step, .cameraDenied)
        XCTAssertTrue(denied.requiresOnboarding)

        let unsupported = OnboardingState(defaults: defaults, permissionProvider: PermissionSpy(status: .authorized, requestedStatus: .authorized), capabilityChecker: CapabilitySpy(.unsupportedWorldTracking))
        await unsupported.advance(); await unsupported.advance(); await unsupported.advance()
        XCTAssertEqual(unsupported.step, .unsupportedDevice)
    }

    func testReplayDoesNotClearPersistedCompletion() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = OnboardingState(defaults: defaults)
        state.completeOnboarding()
        state.beginReplay()
        XCTAssertTrue(state.requiresOnboarding)
        XCTAssertEqual(state.step, .welcome)
        XCTAssertEqual(defaults.integer(forKey: OnboardingState.completionVersionKey), OnboardingState.currentVersion)
    }

    func testProductionARReadinessMapsAndOnlyReadyAdvancesToHandCheck() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = OnboardingState(defaults: defaults, permissionProvider: PermissionSpy(status: .authorized, requestedStatus: .authorized), capabilityChecker: CapabilitySpy(.supported))
        state.refreshPermission()

        state.observeProductionRuntime(sessionState: .running(.limited(.initializing)), handState: .noHand, fingertipState: .unavailable)
        XCTAssertEqual(state.spatialReadiness, .limited(.initializing))
        XCTAssertEqual(state.step, .spatialPreparation)

        state.observeProductionRuntime(sessionState: .running(.normal), handState: .noHand, fingertipState: .unavailable)
        XCTAssertEqual(state.spatialReadiness, .ready)
        XCTAssertEqual(state.step, .handCheck)

        state.observeProductionRuntime(sessionState: .interrupted, handState: .noHand, fingertipState: .unavailable)
        XCTAssertEqual(state.spatialReadiness, .interrupted)
        XCTAssertEqual(state.step, .handCheck)

        state.observeProductionRuntime(sessionState: .failed(.sessionFailed), handState: .noHand, fingertipState: .unavailable)
        XCTAssertEqual(state.spatialReadiness, .failed(ARSessionFailure.sessionFailed.message))
        XCTAssertEqual(state.step, .handCheck)
    }

    func testTrackingLimitationsAndProductionHandValidityAreMappedSafely() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = OnboardingState(defaults: defaults, permissionProvider: PermissionSpy(status: .authorized, requestedStatus: .authorized), capabilityChecker: CapabilitySpy(.supported))
        state.refreshPermission()

        let limitations: [(ARTrackingLimitation, SpatialTrackingLimitation)] = [
            (.excessiveMotion, .excessiveMotion),
            (.insufficientFeatures, .insufficientFeatures),
            (.relocalizing, .relocalizing)
        ]
        for (tracking, expected) in limitations {
            state.observeProductionRuntime(sessionState: .running(.limited(tracking)), handState: .noHand, fingertipState: .unavailable)
            XCTAssertEqual(state.spatialReadiness, .limited(expected))
            XCTAssertFalse(state.isHandReady)
        }

        state.observeProductionRuntime(sessionState: .running(.normal), handState: .unreliable, fingertipState: .tracked(.zero))
        XCTAssertFalse(state.isHandReady)

        let landmark = try XCTUnwrap(HandLandmark(normalizedPosition: .init(x: 0.5, y: 0.5), confidence: 0.9))
        let hand = HandPose(indexTip: landmark, thumbTip: landmark, wrist: nil)
        state.observeProductionRuntime(sessionState: .running(.normal), handState: .detected(hand), fingertipState: .tracked(.init(0, 1, 0)))
        XCTAssertTrue(state.isHandReady)

        state.observeProductionRuntime(sessionState: .running(.normal), handState: .noHand, fingertipState: .unavailable)
        XCTAssertFalse(state.isHandReady)
    }

    func testPinchVerificationRequiresProductionSemanticBeginThenEnd() throws {
        let state = try makePinchReadyState()
        XCTAssertEqual(state.step, .pinchCheck)
        XCTAssertEqual(state.pinchVerificationState, .waitingForPinch)

        state.observeProductionPinchEvent(.ended)
        XCTAssertEqual(state.pinchVerificationState, .waitingForPinch)
        XCTAssertEqual(state.step, .pinchCheck)

        state.observeProductionPinchEvent(.began)
        XCTAssertEqual(state.pinchVerificationState, .waitingForRelease)
        state.observeProductionPinchEvent(.began)
        XCTAssertEqual(state.pinchVerificationState, .waitingForRelease)
        state.observeProductionPinchEvent(.ended)
        XCTAssertEqual(state.pinchVerificationState, .completed)
        XCTAssertEqual(state.step, .firstStroke)
    }

    func testPinchVerificationHandTrackingLossAndSkipDoNotCompleteGesture() throws {
        let state = try makePinchReadyState()
        state.observeProductionPinchEvent(.began)
        state.observeProductionRuntime(sessionState: .running(.normal), handState: .noHand, fingertipState: .unavailable)
        XCTAssertEqual(state.pinchVerificationState, .waitingForPinch)
        XCTAssertEqual(state.step, .pinchCheck)

        state.skipPinchVerification()
        XCTAssertEqual(state.pinchVerificationState, .waitingForPinch)
        XCTAssertEqual(state.step, .firstStroke)
    }

    func testPinchVerificationTrackingLossAndRetryResetWithoutCompletion() throws {
        let state = try makePinchReadyState()
        state.observeProductionPinchEvent(.began)
        state.observeProductionRuntime(sessionState: .interrupted, handState: .noHand, fingertipState: .unavailable)
        XCTAssertEqual(state.pinchVerificationState, .waitingForPinch)
        XCTAssertEqual(state.step, .pinchCheck)
        state.retryPinchVerification()
        XCTAssertEqual(state.pinchVerificationState, .waitingForPinch)
    }

    func testFirstStrokeCompletesOnlyForCommittedStrokeInRememberedCanvas() throws {
        let state = try makePinchReadyState()
        let canvasID = UUID()
        let otherCanvasID = UUID()
        state.rememberOnboardingCanvas(id: canvasID)
        state.observeProductionPinchEvent(.began)
        state.observeProductionPinchEvent(.ended)
        XCTAssertEqual(state.step, .firstStroke)

        state.observeCommittedOnboardingStroke(in: otherCanvasID)
        XCTAssertTrue(state.requiresOnboarding)
        XCTAssertEqual(state.step, .firstStroke)

        state.observeCommittedOnboardingStroke(in: canvasID)
        XCTAssertFalse(state.requiresOnboarding)
        XCTAssertEqual(state.step, .complete)
    }

    func testSkipFirstStrokeCompletesWithoutCreatingGestureSuccess() throws {
        let state = try makePinchReadyState()
        state.observeProductionPinchEvent(.began)
        state.observeProductionPinchEvent(.ended)
        state.skipFirstStroke()
        XCTAssertFalse(state.requiresOnboarding)
        XCTAssertEqual(state.step, .complete)
    }

    private func makePinchReadyState() throws -> OnboardingState {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        // The suite is unique and short-lived; retaining it is required while
        // the returned state reads its backing defaults.
        _ = suiteName
        let state = OnboardingState(defaults: defaults, permissionProvider: PermissionSpy(status: .authorized, requestedStatus: .authorized), capabilityChecker: CapabilitySpy(.supported))
        state.refreshPermission()
        let landmark = try XCTUnwrap(HandLandmark(normalizedPosition: .init(x: 0.5, y: 0.5), confidence: 0.9))
        let hand = HandPose(indexTip: landmark, thumbTip: landmark, wrist: nil)
        state.observeProductionRuntime(sessionState: .running(.normal), handState: .detected(hand), fingertipState: .tracked(.zero))
        state.continueFromHandCheck()
        return state
    }

    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AirCanvasTests.OnboardingState.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor private final class PermissionSpy: CameraPermissionProviding {
    var status: CameraAuthorization
    let requestedStatus: CameraAuthorization
    private(set) var requestCount = 0
    init(status: CameraAuthorization, requestedStatus: CameraAuthorization) { self.status = status; self.requestedStatus = requestedStatus }
    func authorizationStatus() -> CameraAuthorization { status }
    func requestAccess() async -> CameraAuthorization { requestCount += 1; status = requestedStatus; return status }
}

private struct CapabilitySpy: SpatialCanvasCapabilityChecking {
    let value: SpatialCanvasCapability
    init(_ value: SpatialCanvasCapability) { self.value = value }
    func spatialCanvasCapability() -> SpatialCanvasCapability { value }
}

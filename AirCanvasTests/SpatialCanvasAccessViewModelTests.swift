import XCTest
@testable import AirCanvas

@MainActor
final class SpatialCanvasAccessViewModelTests: XCTestCase {
    func testNotDeterminedAuthorizationRequestsAccessAndOpensCanvasWhenGranted() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .notDetermined,
            requestResult: .authorized
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .supported)

        await viewModel.prepareForCanvas()

        XCTAssertEqual(permissionService.requestCount, 1)
        XCTAssertEqual(viewModel.state, .readyForCanvas)
    }

    func testAuthorizedUserOpensCanvasWithoutASecondRequest() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .authorized,
            requestResult: .authorized
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .supported)

        await viewModel.prepareForCanvas()

        XCTAssertEqual(permissionService.requestCount, 0)
        XCTAssertEqual(viewModel.state, .readyForCanvas)
    }

    func testDeniedAuthorizationShowsPermissionRequiredState() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .denied,
            requestResult: .denied
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .supported)

        await viewModel.prepareForCanvas()

        XCTAssertEqual(viewModel.state, .cameraAccessRequired)
    }

    func testRestrictedAuthorizationShowsRestrictedState() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .restricted,
            requestResult: .restricted
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .supported)

        await viewModel.prepareForCanvas()

        XCTAssertEqual(viewModel.state, .cameraAccessRestricted)
    }

    func testUnsupportedCapabilityPreventsPermissionRequest() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .notDetermined,
            requestResult: .authorized
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .unsupportedWorldTracking)

        await viewModel.prepareForCanvas()

        XCTAssertEqual(permissionService.requestCount, 0)
        XCTAssertEqual(viewModel.state, .unsupportedDevice)
    }

    func testSettingsReturnRefreshesDeniedAuthorization() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .denied,
            requestResult: .denied
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .supported)

        await viewModel.prepareForCanvas()
        permissionService.authorization = .authorized
        viewModel.refreshAfterApplicationBecomesActive()

        XCTAssertEqual(viewModel.state, .readyForCanvas)
    }

    func testSettingsReturnDetectsRevokedAuthorizationFromAnActiveCanvas() async {
        let permissionService = CameraPermissionServiceSpy(
            authorization: .authorized,
            requestResult: .authorized
        )
        let viewModel = makeViewModel(permissionService: permissionService, capability: .supported)

        await viewModel.prepareForCanvas()
        permissionService.authorization = .denied
        viewModel.refreshAfterApplicationBecomesActive()

        XCTAssertEqual(viewModel.state, .cameraAccessRequired)
    }

    private func makeViewModel(
        permissionService: CameraPermissionServiceSpy,
        capability: SpatialCanvasCapability
    ) -> SpatialCanvasAccessViewModel {
        SpatialCanvasAccessViewModel(
            cameraPermissionService: permissionService,
            capabilityService: CapabilityServiceSpy(capability: capability)
        )
    }
}

@MainActor
private final class CameraPermissionServiceSpy: CameraPermissionProviding {
    var authorization: CameraAuthorization
    let requestResult: CameraAuthorization
    private(set) var requestCount = 0

    init(authorization: CameraAuthorization, requestResult: CameraAuthorization) {
        self.authorization = authorization
        self.requestResult = requestResult
    }

    func authorizationStatus() -> CameraAuthorization {
        authorization
    }

    func requestAccess() async -> CameraAuthorization {
        requestCount += 1
        authorization = requestResult
        return requestResult
    }
}

private struct CapabilityServiceSpy: SpatialCanvasCapabilityChecking {
    let capability: SpatialCanvasCapability

    func spatialCanvasCapability() -> SpatialCanvasCapability {
        capability
    }
}

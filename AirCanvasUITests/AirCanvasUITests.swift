import XCTest

@MainActor
final class AirCanvasUITests: XCTestCase {
    func testUnsupportedSimulatorOnboardingCanContinueToHome() {
        let app = XCUIApplication()
        app.launchEnvironment["AIRCANVAS_UI_TESTING"] = "1"
        app.launchArguments += ["-AirCanvasOnboardingCompleted", "NO"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Spatial Drawing Isn’t Supported"].waitForExistence(timeout: 2))
        app.buttons["Continue to My Canvases"].tap()
        XCTAssertTrue(app.navigationBars["AirCanvas"].waitForExistence(timeout: 2))
    }

    func testHomeNavigationReachesEachFoundationDestination() {
        let app = XCUIApplication()
        app.launchEnvironment["AIRCANVAS_UI_TESTING"] = "1"
        app.launchArguments += ["-AirCanvasOnboardingCompleted", "YES"]
        app.launch()

        app.buttons["My Canvases"].tap()
        XCTAssertTrue(app.staticTexts["No Canvases Yet"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Learn AirCanvas"].waitForExistence(timeout: 2))
    }

    func testNonARAccessibilityIdentifiersExposeLibraryAndHelpActions() {
        let app = XCUIApplication()
        app.launchEnvironment["AIRCANVAS_UI_TESTING"] = "1"
        app.launchArguments += ["-AirCanvasOnboardingCompleted", "YES"]
        app.launch()

        app.buttons["home.myCanvases"].tap()
        XCTAssertTrue(app.buttons["myCanvases.create"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["myCanvases.import"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.learnAirCanvas"].waitForExistence(timeout: 2))
    }
}

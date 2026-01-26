import XCTest

final class SagaUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
  }

  func testHomeScreenshot() throws {
    let homeButton = app.buttons[AccessibilityID.Sidebar.homeButton]
    XCTAssertTrue(homeButton.waitForExistence(timeout: 10))

    let syncButton = app.buttons[AccessibilityID.Toolbar.syncButton]
    XCTAssertTrue(syncButton.waitForExistence(timeout: 5))

    let screenshot = XCUIScreen.main.screenshot()
    addScreenshotAttachment(screenshot, name: "home")
  }

  private func addScreenshotAttachment(_ screenshot: XCUIScreenshot, name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

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

  func testSidebarKeyboardNavigation() throws {
    // Wait for the app to fully load
    let homeButton = app.buttons[AccessibilityID.Sidebar.homeButton]
    XCTAssertTrue(homeButton.waitForExistence(timeout: 10))

    // Wait for books to load - check first book row exists
    let firstBookRow = app.otherElements[AccessibilityID.Books.bookRow(0)]
    let booksExist = firstBookRow.waitForExistence(timeout: 10)

    // If no books exist, skip the test (need data to test navigation)
    guard booksExist else {
      XCTSkip("No books available to test keyboard navigation")
      return
    }

    // Take initial screenshot
    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-nav-01-initial")

    // Click on the scroll area to give it focus
    let scrollArea = app.otherElements[AccessibilityID.Books.sidebarScrollArea]
    XCTAssertTrue(scrollArea.waitForExistence(timeout: 5), "Sidebar scroll area should exist")
    scrollArea.click()

    // Small delay to ensure focus
    Thread.sleep(forTimeInterval: 0.2)

    // Press down arrow to select first book (from Home)
    app.typeKey(.downArrow, modifierFlags: [])
    Thread.sleep(forTimeInterval: 0.3)
    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-nav-02-after-down")

    // Press down arrow again to move to second book
    app.typeKey(.downArrow, modifierFlags: [])
    Thread.sleep(forTimeInterval: 0.3)
    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-nav-03-after-second-down")

    // Press up arrow to go back to first book
    app.typeKey(.upArrow, modifierFlags: [])
    Thread.sleep(forTimeInterval: 0.3)
    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-nav-04-after-up")

    // Press up arrow again to go back to Home
    app.typeKey(.upArrow, modifierFlags: [])
    Thread.sleep(forTimeInterval: 0.3)
    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-nav-05-back-to-home")
  }

  func testSidebarKeyboardRepeat() throws {
    // Wait for the app to fully load
    let homeButton = app.buttons[AccessibilityID.Sidebar.homeButton]
    XCTAssertTrue(homeButton.waitForExistence(timeout: 10))

    // Wait for at least 5 books to exist for repeat testing
    let fifthBookRow = app.otherElements[AccessibilityID.Books.bookRow(4)]
    let enoughBooks = fifthBookRow.waitForExistence(timeout: 10)

    guard enoughBooks else {
      XCTSkip("Need at least 5 books to test keyboard repeat navigation")
      return
    }

    // Click on scroll area to give it focus
    let scrollArea = app.otherElements[AccessibilityID.Books.sidebarScrollArea]
    XCTAssertTrue(scrollArea.waitForExistence(timeout: 5))
    scrollArea.click()
    Thread.sleep(forTimeInterval: 0.2)

    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-repeat-01-initial")

    // Hold down arrow for ~1 second to test key repeat
    // XCUITest doesn't have a direct "hold key" API, so we simulate rapid presses
    for i in 0..<10 {
      app.typeKey(.downArrow, modifierFlags: [])
      Thread.sleep(forTimeInterval: 0.05)  // 50ms between presses, simulating key repeat
    }

    Thread.sleep(forTimeInterval: 0.3)
    addScreenshotAttachment(
      XCUIScreen.main.screenshot(), name: "keyboard-repeat-02-after-rapid-down")

    // Now go back up with rapid key presses
    for i in 0..<10 {
      app.typeKey(.upArrow, modifierFlags: [])
      Thread.sleep(forTimeInterval: 0.05)
    }

    Thread.sleep(forTimeInterval: 0.3)
    addScreenshotAttachment(XCUIScreen.main.screenshot(), name: "keyboard-repeat-03-after-rapid-up")
  }

  private func addScreenshotAttachment(_ screenshot: XCUIScreenshot, name: String) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

import Foundation

public enum AccessibilityID {
  public enum Toolbar {
    public static let backButton = "toolbar.backButton"
    public static let forwardButton = "toolbar.forwardButton"
    public static let syncButton = "toolbar.syncButton"
    public static let settingsButton = "toolbar.settingsButton"
  }

  public enum Sidebar {
    public static let homeButton = "sidebar.home"
  }

  public enum Home {
    public static let view = "home.view"
    public static let scroll = "home.scroll"
  }

  public enum Books {
    public static let list = "books.list"
    public static let sidebar = "books.sidebar"
    public static let sidebarScrollArea = "books.sidebarScrollArea"
    public static let newBookButton = "books.newBookButton"

    public static func bookRow(_ index: Int) -> String {
      "books.row.\(index)"
    }
  }

  public enum Settings {
    public static let view = "settings.view"
    public static let sidebar = "settings.sidebar"
    public static let creditsView = "settings.creditsView"
    public static let clearCaches = "settings.clearCaches"
    public static let clearCachesAndData = "settings.clearCachesAndData"
    public static let checkForUpdates = "settings.checkForUpdates"
    public static let automaticallyCheckForUpdates = "settings.automaticallyCheckForUpdates"
    public static let automaticallyDownloadUpdates = "settings.automaticallyDownloadUpdates"

    public static func pane(_ id: String) -> String {
      "settings.pane.\(id)"
    }
  }
}

import Foundation

public enum AccessibilityID {
  public enum Toolbar {
    public static let backButton = "toolbar.backButton"
    public static let forwardButton = "toolbar.forwardButton"
    public static let syncButton = "toolbar.syncButton"
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

    public static func bookRow(_ index: Int) -> String {
      "books.row.\(index)"
    }
  }

  public enum Settings {
    public static let view = "settings.view"
    public static let clearCaches = "settings.clearCaches"
    public static let clearCachesAndData = "settings.clearCachesAndData"
  }
}

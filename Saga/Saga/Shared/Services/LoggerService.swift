//
//  LoggerService.swift
//  Saga
//
//  Created by Dylan Gattey on 1/25/26.
//

import OSLog

enum LogSurface: String {
  /// Sync orchestration and lifecycle events.
  case sync = "Sync"
  /// Core Data stack setup and sync persistence work.
  case persistence = "Persistence"
  /// Goodreads CSV parsing + import routines.
  case booksImport = "BooksImport"
  /// HTTP requests and remote service responses.
  case network = "Network"
  /// Rich text parsing and rendering.
  case richText = "RichText"
  /// Hot reload / InjectionIII diagnostics (Debug only).
  case hotReload = "HotReload"
}

enum LogLevel {
  case debug
  case notice
  case warning
  case error
}

struct LoggerService {
  private static let subsystem = "Saga"

  static func logger(for surface: LogSurface) -> Logger {
    Logger(subsystem: subsystem, category: surface.rawValue)
  }

  static func log(_ message: String, level: LogLevel = .notice, surface: LogSurface) {
    let logger = logger(for: surface)
    switch level {
    case .debug:
      logger.debug("\(message, privacy: .public)")
    case .notice:
      logger.notice("\(message, privacy: .public)")
    case .warning:
      logger.warning("\(message, privacy: .public)")
    case .error:
      logger.error("\(message, privacy: .public)")
    }
  }

  static func log(_ message: String, error: Error, surface: LogSurface) {
    let description = String(describing: error)
    log("\(message): \(description)", level: .error, surface: surface)
  }
}

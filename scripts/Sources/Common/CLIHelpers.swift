import Foundation

// MARK: - CLI Option Protocol

/// Protocol for CLI options that enables type-safe switching while supporting auto-generated usage.
/// Conform your enum to this protocol to define options with metadata.
public protocol CLIOptionType: RawRepresentable, CaseIterable where RawValue == String {
  /// Optional single-character short form (e.g. "v" for -v).
  var shortName: String? { get }
  /// Help text for this option.
  var description: String { get }
  /// If non-nil, the option takes an argument with this display name (e.g. "<branch>").
  var argumentName: String? { get }
}

extension CLIOptionType {
  // Default implementations
  public var shortName: String? { nil }
  public var argumentName: String? { nil }

  /// The long flag form (e.g. "--verbose").
  public var longFlag: String { "--\(rawValue)" }
  /// The short flag form (e.g. "-v"), if shortName is defined.
  public var shortFlag: String? { shortName.map { "-\($0)" } }

  /// Returns true if the argument matches this option's long or short flag.
  public func matches(_ arg: String) -> Bool {
    arg == longFlag || (shortFlag != nil && arg == shortFlag)
  }

  /// Finds the option matching the given argument, or nil if no match.
  public static func match(_ arg: String) -> Self? {
    allCases.first { $0.matches(arg) }
  }

  /// All completion strings for this option type.
  public static var completions: [String] {
    allCases.flatMap { option -> [String] in
      var result = [option.longFlag]
      if let short = option.shortFlag { result.append(short) }
      return result
    }
  }
}

// MARK: - CLI Subcommand Protocol

/// Protocol for CLI subcommands that enables type-safe switching.
public protocol CLISubcommandType: RawRepresentable, CaseIterable where RawValue == String {
  /// Help text for this subcommand.
  var description: String { get }
}

extension CLISubcommandType {
  /// All completion strings for this subcommand type.
  public static var completions: [String] {
    allCases.map(\.rawValue)
  }
}

// MARK: - CLI

/// CLI configuration that auto-generates usage, completions, and handles standard flags.
public struct CLI<Option: CLIOptionType> {
  public let scriptName: String
  public let description: String
  public let optionType: Option.Type
  public let subcommandDescriptions: [(name: String, description: String)]
  public let examples: [String]
  public let notes: [String]

  /// Standard options added to all CLIs.
  private static var helpOption: StandardOption { .help }
  private static var completionsOption: StandardOption { .completions }

  /// Creates a CLI with typed options, deriving script name and description from the source file.
  public init(
    filePath: String,
    options: Option.Type,
    subcommands: [(name: String, description: String)] = [],
    examples: [String] = [],
    notes: [String] = []
  ) {
    let url = URL(fileURLWithPath: filePath)
    self.scriptName = url.deletingLastPathComponent().lastPathComponent
    self.description = scriptDescription(filePath: filePath)
    self.optionType = options
    self.subcommandDescriptions = subcommands
    self.examples = examples
    self.notes = notes
  }

  // MARK: - Usage generation

  /// Generates the full usage text.
  public func usage() -> String {
    var lines: [String] = []

    if !description.isEmpty {
      lines.append(description)
      lines.append("")
    }

    lines.append("Usage:")
    lines.append("  \(usageLine)")

    let optionLines = formattedOptions()
    if !optionLines.isEmpty {
      lines.append("")
      lines.append("Options:")
      lines.append(contentsOf: optionLines.map { "  \($0)" })
    }

    if !subcommandDescriptions.isEmpty {
      lines.append("")
      lines.append("Subcommands:")
      lines.append(contentsOf: formattedSubcommands().map { "  \($0)" })
    }

    if !examples.isEmpty {
      lines.append("")
      lines.append("Examples:")
      lines.append(contentsOf: examples.map { "  \($0)" })
    }

    if !notes.isEmpty {
      lines.append("")
      lines.append("Notes:")
      lines.append(contentsOf: notes.map { "  - \($0)" })
    }

    return lines.joined(separator: "\n")
  }

  private var usageLine: String {
    var parts = ["run", scriptName]
    if !subcommandDescriptions.isEmpty {
      parts.append("<command>")
    }
    if Option.allCases.count > 0 {
      parts.append("[options]")
    }
    return parts.joined(separator: " ")
  }

  private func formattedOptions() -> [String] {
    let userOptions: [(flags: String, desc: String)] = Option.allCases.map { option in
      (optionFlags(option), option.description)
    }
    let standardOptions: [(flags: String, desc: String)] = StandardOption.allCases.map { option in
      (optionFlags(option), option.description)
    }
    let allOptions = userOptions + standardOptions
    let maxWidth = allOptions.map(\.flags.count).max() ?? 0
    return allOptions.map { formatOption($0.flags, $0.desc, width: maxWidth) }
  }

  private func optionFlags<O: CLIOptionType>(_ option: O) -> String {
    var flags = option.longFlag
    if let short = option.shortFlag {
      flags = "\(flags), \(short)"
    }
    if let arg = option.argumentName {
      flags = "\(flags) \(arg)"
    }
    return flags
  }

  private func formatOption(_ flags: String, _ desc: String, width: Int) -> String {
    let padding = String(repeating: " ", count: max(0, width - flags.count + 2))
    return "\(flags)\(padding)\(desc)"
  }

  private func formattedSubcommands() -> [String] {
    let maxWidth = subcommandDescriptions.map(\.name.count).max() ?? 0
    return subcommandDescriptions.map { cmd in
      let padding = String(repeating: " ", count: max(0, maxWidth - cmd.name.count + 2))
      return "\(cmd.name)\(padding)\(cmd.description)"
    }
  }

  // MARK: - Completions

  /// Generates all completions for shell completion scripts.
  public func completions() -> [String] {
    var result = Option.completions
    result.append(contentsOf: subcommandDescriptions.map(\.name))
    result.append(contentsOf: StandardOption.completions)
    return result
  }

  // MARK: - Preflight

  /// Handles --help and --completions, exiting if matched.
  public func preflight(_ args: [String]) {
    if args.contains(where: { Self.completionsOption.matches($0) }) {
      print(completions().joined(separator: "\n"))
      exit(0)
    }
    if args.contains(where: { Self.helpOption.matches($0) }) {
      print(usage())
      exit(0)
    }
  }
}

// MARK: - CLI without options

/// CLI configuration for scripts with no custom options.
public struct SimpleCLI {
  public let scriptName: String
  public let description: String
  public let subcommandDescriptions: [(name: String, description: String)]
  public let examples: [String]
  public let notes: [String]

  /// Creates a CLI with no custom options.
  public init(
    filePath: String,
    subcommands: [(name: String, description: String)] = [],
    examples: [String] = [],
    notes: [String] = []
  ) {
    let url = URL(fileURLWithPath: filePath)
    self.scriptName = url.deletingLastPathComponent().lastPathComponent
    self.description = scriptDescription(filePath: filePath)
    self.subcommandDescriptions = subcommands
    self.examples = examples
    self.notes = notes
  }

  /// Generates the full usage text.
  public func usage() -> String {
    var lines: [String] = []

    if !description.isEmpty {
      lines.append(description)
      lines.append("")
    }

    lines.append("Usage:")
    var usageParts = ["run", scriptName]
    if !subcommandDescriptions.isEmpty { usageParts.append("<command>") }
    lines.append("  \(usageParts.joined(separator: " "))")

    lines.append("")
    lines.append("Options:")
    let maxWidth = StandardOption.allCases.map { optionFlags($0).count }.max() ?? 0
    for option in StandardOption.allCases {
      let flags = optionFlags(option)
      let padding = String(repeating: " ", count: max(0, maxWidth - flags.count + 2))
      lines.append("  \(flags)\(padding)\(option.description)")
    }

    if !subcommandDescriptions.isEmpty {
      lines.append("")
      lines.append("Subcommands:")
      let cmdWidth = subcommandDescriptions.map(\.name.count).max() ?? 0
      for cmd in subcommandDescriptions {
        let padding = String(repeating: " ", count: max(0, cmdWidth - cmd.name.count + 2))
        lines.append("  \(cmd.name)\(padding)\(cmd.description)")
      }
    }

    if !examples.isEmpty {
      lines.append("")
      lines.append("Examples:")
      lines.append(contentsOf: examples.map { "  \($0)" })
    }

    if !notes.isEmpty {
      lines.append("")
      lines.append("Notes:")
      lines.append(contentsOf: notes.map { "  - \($0)" })
    }

    return lines.joined(separator: "\n")
  }

  private func optionFlags(_ option: StandardOption) -> String {
    var flags = option.longFlag
    if let short = option.shortFlag { flags = "\(flags), \(short)" }
    return flags
  }

  /// Generates all completions for shell completion scripts.
  public func completions() -> [String] {
    var result = subcommandDescriptions.map(\.name)
    result.append(contentsOf: StandardOption.completions)
    return result
  }

  /// Handles --help and --completions, exiting if matched.
  public func preflight(_ args: [String]) {
    if args.contains(where: { StandardOption.completions.matches($0) }) {
      print(completions().joined(separator: "\n"))
      exit(0)
    }
    if args.contains(where: { StandardOption.help.matches($0) }) {
      print(usage())
      exit(0)
    }
  }
}

// MARK: - Standard Options

/// Standard options included in all CLIs.
enum StandardOption: String, CLIOptionType, CaseIterable {
  case help
  case completions

  var shortName: String? {
    switch self {
    case .help: "h"
    case .completions: nil
    }
  }

  var description: String {
    switch self {
    case .help: "Show this help message"
    case .completions: "Print shell completions"
    }
  }
}

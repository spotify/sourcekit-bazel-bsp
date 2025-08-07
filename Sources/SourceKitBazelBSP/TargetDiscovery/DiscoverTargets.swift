import Foundation

// MARK: - Logger

private let logger = makeFileLevelBSPLogger()

// MARK: - Public API

public enum TopLevelTarget: String {
    case iosApplication = "ios_application"
    case iosUnitTest = "ios_unit_test"
}

public enum DiscoverTargetsError: LocalizedError, Equatable {
    case noTargetsDiscovered

    public var errorDescription: String? {
        switch self {
        case .noTargetsDiscovered: return "No targets discovered!"
        }
    }
}

/// Discovers Bazel targets matching the specified rule types by running a Bazel query.
///
/// - Parameters:
///   - rules: The rule types to search for (e.g. ios_application, ios_unit_test)
///   - bazelWrapper: The Bazel executable to use (defaults to "bazel")
/// - Returns: An array of discovered target labels
/// - Throws: DiscoverTargetsError.noTargetsDiscovered if no matching targets are found
public func discoverTargets(
    for rules: TopLevelTarget...,
    bazelWrapper: String = "bazel"
) throws -> [String] {
    try discoverTargetsInternal(
        for: rules,
        bazelWrapper: bazelWrapper,
        commandRunner: ShellCommandRunner()
    )
}

// MARK: - Internal API

func discoverTargetsInternal(
    for rules: [TopLevelTarget],
    bazelWrapper: String = "bazel",
    commandRunner: CommandRunner
) throws -> [String] {
    logger.info("Discovering targets for rules: \(rules.map { $0.rawValue }.joined(separator: ", "))")

    let query = rules.map {
        "kind(\($0.rawValue), ...)"
    }
    .joined(separator: " + ")

    let cmd = "\(bazelWrapper) query '\(query)' --output label"

    let output = try commandRunner.run(cmd)

    let discoveredTargets =
        output
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if discoveredTargets.isEmpty {
        logger.error("No targets discovered!")
        throw DiscoverTargetsError.noTargetsDiscovered
    }

    return discoveredTargets
}

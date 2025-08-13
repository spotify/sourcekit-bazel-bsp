import Foundation

// MARK: - Logger

private let logger = makeFileLevelBSPLogger()

public enum BazelTargetDiscovererError: LocalizedError, Equatable {
    case noTargetsDiscovered

    public var errorDescription: String? {
        switch self {
        case .noTargetsDiscovered: return "No targets discovered!"
        }
    }
}

public enum BazelTargetDiscoverer {
    /// Discovers Bazel targets in a workspace matching the specified rule
    /// types by running a Bazel query. To be used when the BSP is initialized
    /// with no targets specified.
    ///
    /// - Parameters:
    ///   - bazelWrapper: The Bazel executable to use (defaults to "bazel")
    /// - Returns: An array of discovered target labels
    /// - Throws: DiscoverTargetsError.noTargetsDiscovered if no matching targets are found
    public static func discoverTargets(
        for rules: [TopLevelRuleType] = TopLevelRuleType.allCases,
        bazelWrapper: String = "bazel",
        commandRunner: CommandRunner? = nil
    ) throws -> [String] {
        let commandRunner = commandRunner ?? ShellCommandRunner()

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
            throw BazelTargetDiscovererError.noTargetsDiscovered
        }

        return discoveredTargets
    }
}

import Foundation

public enum BazelTargetDiscovererError: LocalizedError, Equatable {
    case noRulesProvided
    case noTargetsDiscovered
    case noLocationsProvided

    public var errorDescription: String? {
        switch self {
        case .noRulesProvided: return "No rules provided!"
        case .noTargetsDiscovered: return "No targets discovered!"
        case .noLocationsProvided: return "No locations provided!"
        }
    }
}

public enum BazelTargetDiscoverer {
    /// Discovers Bazel targets in a workspace matching the specified rule
    /// types by running a Bazel query. To be used when the BSP is initialized
    /// with no targets specified.
    ///
    /// - Parameters:
    ///   - rules: The rule types to search for (e.g. ios_application, ios_unit_test)
    ///   - bazelWrapper: The Bazel executable to use (defaults to "bazel")
    /// - Returns: An array of discovered target labels
    /// - Throws: DiscoverTargetsError.noTargetsDiscovered if no matching targets are found
    public static func discoverTargets(
        for rules: [TopLevelRuleType] = TopLevelRuleType.allCases,
        bazelWrapper: String = "bazel",
        locations: [String] = [],
        commandRunner: CommandRunner? = nil
    ) throws -> [String] {
        guard !rules.isEmpty else {
            throw BazelTargetDiscovererError.noRulesProvided
        }

        guard !locations.isEmpty else {
            throw BazelTargetDiscovererError.noLocationsProvided
        }

        let commandRunner = commandRunner ?? ShellCommandRunner()

        let kindsQuery = "\"" + rules.map { $0.rawValue }.joined(separator: "|") + "\""
        let locationsQuery = locations.joined(separator: " union ")
        let query = "kind(\(kindsQuery), \(locationsQuery))"

        let cmd = "\(bazelWrapper) query '\(query)' --output label"

        let output: String = try commandRunner.run(cmd)

        let discoveredTargets =
            output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if discoveredTargets.isEmpty {
            throw BazelTargetDiscovererError.noTargetsDiscovered
        }

        return discoveredTargets
    }
}

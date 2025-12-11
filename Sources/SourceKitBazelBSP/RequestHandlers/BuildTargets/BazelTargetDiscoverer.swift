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
    ///   - additionalFlags: Additional flags to pass to the Bazel command
    /// - Returns: An array of discovered target labels
    /// - Throws: DiscoverTargetsError.noTargetsDiscovered if no matching targets are found
    public static func discoverTargets(
        for rules: [TopLevelRuleType] = TopLevelRuleType.allCases,
        bazelWrapper: String = "bazel",
        locations: [String] = [],
        additionalFlags: [String] = [],
        commandRunner: CommandRunner? = nil
    ) throws -> [String] {
        guard !rules.isEmpty else {
            throw BazelTargetDiscovererError.noRulesProvided
        }

        guard !locations.isEmpty else {
            throw BazelTargetDiscovererError.noLocationsProvided
        }

        let commandRunner = commandRunner ?? ShellCommandRunner()

        // FIXME: This has a lot of overlap with the Bazel utilities in CommandRunner, but we cannot
        // use them because this logic runs before the actual initialize code that builds all necessary info.
        // So we're duplicating a bunch of this logic here as a result.
        let kindsQuery = "\"" + rules.map { $0.rawValue }.joined(separator: "|") + "\""
        let locationsQuery = locations.joined(separator: " union ")
        let query = "kind(\(kindsQuery), \(locationsQuery))"
        let additionalFlagsString: String = {
            if additionalFlags.isEmpty {
                return ""
            }
            return " " + additionalFlags.joined(separator: " ")
        }()
        let cmd = "\(bazelWrapper) cquery '\(query)'\(additionalFlagsString) --output label"

        let output: String = try commandRunner.run(cmd)

        let discoveredTargets =
            output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: " (")[0] }

        if discoveredTargets.isEmpty {
            throw BazelTargetDiscovererError.noTargetsDiscovered
        }

        return discoveredTargets
    }
}

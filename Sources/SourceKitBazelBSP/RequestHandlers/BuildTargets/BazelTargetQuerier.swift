// Copyright (c) 2025 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import BazelProtobufBindings
import Foundation

private let logger = makeFileLevelBSPLogger()

enum BazelTargetQuerierError: Error, LocalizedError {
    case noKinds
    case noTargets
    case invalidQueryOutput

    var errorDescription: String? {
        switch self {
        case .noKinds: return "A list of kinds is necessary to query targets"
        case .noTargets: return "A list of targets is necessary to query targets"
        case .invalidQueryOutput: return "Query output is not valid XML"
        }
    }
}

/// Small abstraction to handle and cache the results of bazel queries.
///
/// FIXME: Currently uses XML, should use proto instead so that we can organize and test this properly
final class BazelTargetQuerier {

    private let commandRunner: CommandRunner
    private var queryCache = [String: XMLElement]()

    static func queryDepsString(forTargets targets: [String]) -> String {
        var query = ""
        for target in targets {
            if query == "" {
                query = "deps(\(target))"
            } else {
                query += " union deps(\(target))"
            }
        }
        return query
    }

    init(commandRunner: CommandRunner = ShellCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func queryTargets(forConfig config: BaseServerConfig, rootUri: String, kinds: Set<String>) throws -> XMLElement {
        guard !kinds.isEmpty else {
            throw BazelTargetQuerierError.noKinds
        }

        guard !config.targets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        let kindsFilter = kinds.sorted().joined(separator: "|")
        let depsQuery = Self.queryDepsString(forTargets: config.targets)
        let cacheKey = "\(kindsFilter)+\(depsQuery)"

        logger.info("Processing query request for \(cacheKey)")

        if let cached = queryCache[cacheKey] {
            logger.debug("Returning cached results")
            return cached
        }

        // We run this one on the main output base since it's not related to the actual indexing bits
        let cmd = "query \"kind('\(kindsFilter)', \(depsQuery))\" --output xml"
        let output = try commandRunner.bazel(baseConfig: config, rootUri: rootUri, cmd: cmd)

        logger.debug("Finished querying, building result XML")

        guard let xml = try XMLDocument(xmlString: output).rootElement() else {
            throw BazelTargetQuerierError.invalidQueryOutput
        }

        queryCache[cacheKey] = xml

        return xml
    }

    func clearCache() {
        queryCache = [:]
    }
}

// MARK: Protobuf

extension BazelTargetQuerier {
    /// Based on the server config, it constructs query and calls `bazel query deps` with output proto
    func queryTargetsWithProto(
        forConfig config: BaseServerConfig,
        rootUri: String,
        kinds: Set<String>
    ) throws -> [BlazeQuery_Target] {
        guard !kinds.isEmpty else {
            throw BazelTargetQuerierError.noKinds
        }

        guard !config.targets.isEmpty else {
            throw BazelTargetQuerierError.noTargets
        }

        let kindsFilter = kinds.sorted().joined(separator: "|")
        let depsQuery = Self.queryDepsString(forTargets: config.targets)
        let cacheKey = "\(kindsFilter)+\(depsQuery)"

        logger.info("Processing query request for \(cacheKey) --output streamed_proto")

        // We run this one on the main output base since it's not related to the actual indexing bits
        let cmd = "query \"kind('source file|\(kindsFilter)', \(depsQuery))\" --output streamed_proto"

        let output = try commandRunner.getStdout(with: config.bazelWrapper + " " + cmd, cwd: rootUri)

        logger.debug("Finished querying, building result protobuf \(output.count, privacy: .public)")

        let targets = try BazelProtobufBindings.parseQueryTargets(data: output)

        logger.debug("Parsing BlazeQuery_Target: \(targets.count, privacy: .public)")

        return targets
    }
}

extension CommandRunner {
    func getStdout(with cmd: String, cwd: String?) throws -> Data {
          let task = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        task.standardOutput = stdout
        task.standardError = stderr
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        if let cwd {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        task.arguments = ["-c", cmd]
        task.standardInput = nil

        logger.info("Running shell: \(cmd)")
        try task.run()

        // Drain stdout/err first to avoid deadlocking when the output is buffered.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let stderrString: String = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            throw ShellCommandRunnerError.failed(cmd, stderrString)
        }

        return data
    }
}

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

import Foundation
import Logging
import OSLog

public typealias SwiftLogger = Logging.Logger
public typealias OSLogger = os.Logger

public struct BSPLogging {
    public static func setup(logToFile: Bool) {
        LoggingSystem.bootstrap { label in
            let osLogger = os.Logger(
                subsystem: "sourcekit-bazel-bsp",
                category: #fileID
            )
            if logToFile, let handler = try? FileLogHandler(label: label) {
                osLogger.debug("FileLogHandler initialized")
                return handler
            } else {
                let handler = OSLogHandler(subsystem: label)
                osLogger.debug("OSLogHandler initialized")
                return handler
            }
        }
    }
}

public struct FileLogHandler: LogHandler, Sendable {
    
    public var logLevel: SwiftLogger.Level
    public var metadata: SwiftLogger.Metadata

    private let label: String
    private let fileName: String
    private let fileURL: URL
    private let fileHandle: FileHandle
    private let dateFormatter: DateFormatter
    
    public subscript(metadataKey metadataKey: String) -> SwiftLogger.Metadata.Value? {
        get {
            self.metadata[metadataKey]
        }
        set(newValue) {
            self.metadata[metadataKey] = newValue
        }
    }
    
    public init(
        logLevel: SwiftLogger.Level = .info,
        metadata: SwiftLogger.Metadata = .init(),
        label: String = "sourcekit-bazel-bsp",
        fileName: String = "bazel-bsp.log",
        fileDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) throws {
        self.logLevel = logLevel
        self.metadata = metadata
        
        self.label = label
        self.fileName = fileName
        self.fileURL = fileDirectory.appending(component: fileName)
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        if !FileManager.default.fileExists(atPath: fileURL.path()) {
            FileManager.default.createFile(atPath: fileURL.path(), contents: nil, attributes: nil)
        }
        
        self.fileHandle = try FileHandle(forWritingTo: fileURL)
    }

    public func log(
        level: SwiftLogger.Level,
        message: SwiftLogger.Message,
        metadata: SwiftLogger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let timestamp = self.dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] [\(label)] [\(level.rawValue)] \(message)"
        self.writeToFile(logEntry)
    }
    
    private func writeToFile(_ logEntry: String) {
        if let data = logEntry.data(using: .utf8) {
            try? self.fileHandle.write(contentsOf: data)
        }
    }
}

public struct OSLogHandler: LogHandler, Sendable {

    public var metadata: Logging.Logger.Metadata = .init()
    public subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get {
            self.metadata[metadataKey]
        }
        set(newValue) {
            self.metadata[metadataKey] = newValue
        }
    }
    
    public var logLevel: SwiftLogger.Level = .info
    
    public let logger: OSLogger
    
    public init(
        subsystem: String = "sourcekit-bazel-bsp",
        category: String = #fileID
    ) {
        self.logger = OSLogger(subsystem: subsystem, category: category)
    }
    
    public func log(
        level: SwiftLogger.Level,
        message: SwiftLogger.Message,
        metadata: SwiftLogger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        switch level {
        case .info:
            self.logger.info("\(message, privacy: .public)")
        case .debug:
            self.logger.debug("\(message, privacy: .public)")
        case .error:
            self.logger.error("\(message, privacy: .public)")
        case .critical:
            self.logger.critical("\(message, privacy: .public)")
        case .notice:
            self.logger.notice("\(message, privacy: .public)")
        case .warning:
            self.logger.warning("\(message, privacy: .public)")
        case .trace:
            self.logger.trace("\(message, privacy: .public)")
        }
    }
}


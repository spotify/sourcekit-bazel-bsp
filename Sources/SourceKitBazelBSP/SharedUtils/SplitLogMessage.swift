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

// Based on the same file in sourcekit-lsp, which we can't use directly due to it currently being `package` scoped.
// os_log has a maximum message length, so longer messages need to be split into multiple logs.

import OSLog

/// Splits `message` such that each chunk is at most `maxChunkSize` bytes long.
///
/// The intended use case for this is to split compiler arguments and a file's contents into multiple chunks so
/// that each chunk doesn't exceed the maximum message length of `os_log` and thus won't get truncated.
///
/// When `splitByCharacterCount` is true, the message is split purely by character count, ignoring any
/// separator logic. Otherwise, splits along newline boundaries (a single line longer than `maxChunkSize`
/// won't be split in that mode).
package func splitLongMultilineMessage(
    message: String,
    splitByCharacterCount: Bool = false
) -> [String] {
    let maxChunkSize = 800
    var chunks: [String] = []

    if splitByCharacterCount {
        var remaining = message
        while !remaining.isEmpty {
            if remaining.utf8.count > maxChunkSize {
                let endIndex = remaining.utf8.index(remaining.utf8.startIndex, offsetBy: maxChunkSize)
                chunks.append(String(remaining[..<endIndex]))
                remaining = String(remaining[endIndex...])
            } else {
                chunks.append(remaining)
                remaining = ""
            }
        }
        return chunks
    }

    for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
        if let lastChunk = chunks.last, lastChunk.utf8.count + line.utf8.count < maxChunkSize {
            chunks[chunks.count - 1] += "\n" + line
        } else {
            if !chunks.isEmpty {
                // Append an end marker to the last chunk so that os_log doesn't truncate trailing whitespace,
                // which would modify the source contents.
                // Empty newlines are important so the offset of the request is correct.
                chunks[chunks.count - 1] += "\n--- End Chunk"
            }
            chunks.append(String(line))
        }
    }
    return chunks
}

extension Logger {
    package func logFullObjectInMultipleLogMessages(
        level: OSLogType = .default,
        header: StaticString,
        _ subject: String,
        splitByCharacterCount: Bool = false
    ) {
        let chunks = splitLongMultilineMessage(
            message: subject,
            splitByCharacterCount: splitByCharacterCount
        )
        let maxChunkCount = chunks.count
        for i in 0..<maxChunkCount {
            let loggableChunk = i < chunks.count ? chunks[i] : ""
            self.log(
                level: level,
                """
                \(header, privacy: .public) (\(i + 1, privacy: .public)/\(maxChunkCount, privacy: .public))
                \(loggableChunk, privacy: .public)
                """
            )
        }
    }
}

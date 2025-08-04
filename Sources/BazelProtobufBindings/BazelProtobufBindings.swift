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

package enum BazelProtobufBindings {
    package static func parseQueryTargets(data: Data) throws -> [BlazeQuery_Target] {
        var targets: [BlazeQuery_Target] = []
        let messages = try parseMultipleDelimitedMessages(from: data)
        for message in messages {
            let target = try BlazeQuery_Target(serializedBytes: message)
            targets.append(target)
        }

        return targets
    }

    package static func parseActionGraph(data: Data) throws -> Analysis_ActionGraphContainer {
        try Analysis_ActionGraphContainer(serializedBytes: data)
    }
}

extension BazelProtobufBindings {
    /// Bazel query outputs a series of messages and each one is prefixed with length to indicate
    /// the number of bytes in the payload. Returns a tuple of (value, bytesConsumed).
    /// Protobuf [documentation](https://protobuf.dev/programming-guides/encoding/) provides more
    /// details on how `varint` works.
    private static func parseVarint(
        from data: Data,
        startIndex: Int
    ) throws -> (UInt64, Int) {
        guard startIndex < data.count else {
            throw VarintError.truncated
        }

        var result: UInt64 = 0
        var shift = 0
        var bytesRead = 0
        var index = startIndex

        while index < data.count {
            let byte = data[index]
            bytesRead += 1
            index += 1

            // Check for overflow (varints can be at most 10 bytes for 64-bit values)
            if bytesRead > 10 {
                throw VarintError.overflow
            }

            // Extract the 7 data bits
            let dataBits = UInt64(byte & 0x7F)

            // Check for shift overflow
            if shift >= 64 {
                throw VarintError.overflow
            }

            // little-endian -> big-endian
            result |= dataBits << shift

            // If the continuation bit (MSB) is not set, we're done
            if (byte & 0x80) == 0 {
                return (result, bytesRead)
            }

            shift += 7
        }

        // If we get here, the varint was truncated
        throw VarintError.truncated
    }

    /// Parse the length prefix and return the message data
    private static func parseDelimitedMessage(
        from data: Data,
        startIndex: Int = 0
    ) throws -> (Data, Int) {
        let (messageLength, lengthBytes) = try parseVarint(
            from: data,
            startIndex: startIndex
        )

        let messageStart = startIndex + lengthBytes
        let messageEnd = messageStart + Int(messageLength)

        guard messageEnd <= data.count else {
            throw VarintError.truncated
        }

        let messageData = data.subdata(in: messageStart..<messageEnd)
        let totalBytesConsumed = lengthBytes + Int(messageLength)

        return (messageData, totalBytesConsumed)
    }

    /// Parse multiple delimited messages from a data stream
    private static func parseMultipleDelimitedMessages(from data: Data) throws -> [Data] {
        var messages: [Data] = []
        var currentIndex = 0

        while currentIndex < data.count {
            let (messageData, bytesConsumed) = try parseDelimitedMessage(
                from: data,
                startIndex: currentIndex
            )
            messages.append(messageData)
            currentIndex += bytesConsumed
        }

        return messages
    }
}

package enum VarintError: Error {
    case truncated
    case overflow
    case invalidData
}

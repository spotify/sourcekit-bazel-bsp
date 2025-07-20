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

import BuildServerProtocol
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import Testing

@testable import SourceKitBazelBSP

@Suite
struct BSPMessageHandlerTests {
    @Test
    func unknownRequestHandler() throws {
        let handler = BSPMessageHandler()
        struct FakeRequest: RequestType {
            static let method = "fake/request"
            typealias Response = VoidResponse
        }
        let request = FakeRequest()
        var receivedResponse: LSPResult<VoidResponse>?
        handler.handle(request, id: RequestID.number(1)) { result in receivedResponse = result }
        let result = try #require(receivedResponse)
        switch result {
        case .success: Issue.record("Expected failure but got success!")
        case .failure(let error):
            #expect(error.code == .methodNotFound)
            #expect(error.message == "method not found: fake/request")
        }
    }

    @Test
    func successfulRequest() throws {
        let mockResponse = BuildTargetSourcesResponse(items: [])

        let handler = BSPMessageHandler()
        handler.register(requestHandler: { (_: BuildTargetSourcesRequest, _) in mockResponse })

        let request = BuildTargetSourcesRequest(targets: [BuildTargetIdentifier(uri: try URI(string: "file:///test"))],
        )

        var receivedResponse: LSPResult<BuildTargetSourcesResponse>?
        handler.handle(request, id: RequestID.number(1)) { result in receivedResponse = result }

        let result = try #require(receivedResponse)
        switch result {
        case .success(let response): #expect(response == mockResponse)
        case .failure(let error): Issue.record("Expected success but got error: \(error)")
        }
    }

    @Test
    func failedRequest() throws {
        let mockError = ResponseError.internalError("Test error")
        let handler = BSPMessageHandler()
        handler.register(requestHandler: { (_: BuildTargetSourcesRequest, _) in throw mockError })

        let request = BuildTargetSourcesRequest(targets: [BuildTargetIdentifier(uri: try URI(string: "file:///test"))],
        )

        var receivedResponse: LSPResult<BuildTargetSourcesResponse>?
        handler.handle(request, id: RequestID.number(1)) { result in receivedResponse = result }

        let result = try #require(receivedResponse)
        switch result {
        case .success: Issue.record("Expected failure but got success!")
        case .failure(let error): #expect(error == mockError)
        }
    }

    @Test
    func unknownNotification() throws {
        var initialized = false
        let handler = BSPMessageHandler()

        handler.register(notificationHandler: { (_: OnBuildInitializedNotification) in initialized = true })

        // Some other notification type that is not the one we registered for
        let notification = CancelRequestNotification(id: RequestID.number(1))
        handler.handle(notification)

        // Since notifications don't currently throw errors on failure, we're just checking the tool didn't crash
        #expect(initialized == false)
    }

    @Test
    func successfulNotification() throws {
        var initialized = false
        let handler = BSPMessageHandler()

        handler.register(notificationHandler: { (_: OnBuildInitializedNotification) in initialized = true })

        let notification = OnBuildInitializedNotification()
        handler.handle(notification)

        #expect(initialized)
    }
}

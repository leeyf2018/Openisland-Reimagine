import Foundation
import Testing
@testable import OpenIslandCore

struct CodexAppServerRateLimitsTests {
    @Test
    func readRateLimitsMapsFreshServerWindow() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 1

        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting
        let capturedAt = Date(timeIntervalSince1970: 1_786_417_200)

        let snapshotTask = Task {
            try await client.readRateLimits(capturedAt: capturedAt)
        }

        let requestData = pipe.fileHandleForReading.availableData
        let request = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        let requestID = try #require(request["id"] as? Int)
        #expect(request["method"] as? String == "account/rateLimits/read")
        #expect(request["params"] is NSNull)

        let response = """
        {"id":\(requestID),"result":{"rateLimits":{"limitId":"codex","planType":"plus","primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1787020203},"secondary":null}}}
        """
        client.handleIncomingData(Data((response + "\n").utf8))

        let snapshot = try await snapshotTask.value
        #expect(snapshot?.sourceFilePath == "codex-app-server://account/rateLimits/read")
        #expect(snapshot?.capturedAt == capturedAt)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.planType == "plus")
        #expect(snapshot?.windows.map(\.label) == ["7d"])
        #expect(snapshot?.windows.first?.roundedUsedPercentage == 2)
        #expect(snapshot?.windows.first?.leftPercentage == 98)
        #expect(snapshot?.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_787_020_203))
    }

    @Test
    func readRateLimitsReturnsNilWhenServerHasNoWindow() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 1

        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting
        let snapshotTask = Task { try await client.readRateLimits() }

        let requestData = pipe.fileHandleForReading.availableData
        let request = try #require(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        let requestID = try #require(request["id"] as? Int)
        client.handleIncomingData(Data("{\"id\":\(requestID),\"result\":{\"rateLimits\":null}}\n".utf8))

        #expect(try await snapshotTask.value == nil)
    }
}

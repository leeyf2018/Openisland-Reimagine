import Foundation
import Testing
@testable import OpenIslandCore

struct CodexAppServerRateLimitsTests {
    @Test
    func readRateLimitsMapsFreshServerWindow() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 1
        client.stdin = .nullDevice
        let capturedAt = Date(timeIntervalSince1970: 1_786_417_200)
        var observedMethod: String?
        var observedNullParams = false
        client.onRequestSentForTests = { requestData in
            guard let request = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                  let requestID = request["id"] as? Int else { return }
            observedMethod = request["method"] as? String
            observedNullParams = request["params"] is NSNull
            let response = """
            {"id":\(requestID),"result":{"rateLimits":{"limitId":"codex","planType":"plus","primary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1787020203},"secondary":null}}}
            """
            client.handleIncomingData(Data((response + "\n").utf8))
        }

        let snapshot = try await client.readRateLimits(capturedAt: capturedAt)
        #expect(observedMethod == "account/rateLimits/read")
        #expect(observedNullParams)
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
        client.stdin = .nullDevice
        client.onRequestSentForTests = { requestData in
            guard let request = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
                  let requestID = request["id"] as? Int else { return }
            client.handleIncomingData(Data("{\"id\":\(requestID),\"result\":{\"rateLimits\":null}}\n".utf8))
        }

        #expect(try await client.readRateLimits() == nil)
    }
}

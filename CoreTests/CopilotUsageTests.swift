import Core
import Foundation
import Testing

// Shape of a real copilot_internal/user response, trimmed to the fields Core reads.
let sampleResponse = Data("""
  {
    "quota_reset_date": "2026-11-01",
    "quota_reset_date_utc": "2026-11-01T00:00:00.000Z",
    "quota_snapshots": {
      "premium_interactions": {
        "credits_used": 8857,
        "entitlement": 12000,
        "quota_remaining": 3142.7,
        "percent_remaining": 26.1,
        "unlimited": false
      }
    }
  }
  """.utf8)

func utcDate(_ isoString: String) -> Date {
  try! Date(isoString, strategy: .iso8601)
}

@Test func decodesPremiumInteractions() throws {
  let usage = try CopilotUsageClient.usage(from: sampleResponse, statusCode: 200)
  #expect(usage.creditsUsed == 8857)
  #expect(usage.entitlement == 12000)
  #expect(usage.creditsRemaining == 3142.7)
  #expect(usage.percentRemaining == 26.1)
  #expect(usage.isUnlimited == false)
  #expect(usage.resetDate == utcDate("2026-11-01T00:00:00Z"))
}

@Test func unauthorizedStatusMeansNotLoggedIn() {
  #expect(throws: CopilotUsageError.notLoggedIn) {
    try CopilotUsageClient.usage(from: Data(), statusCode: 401)
  }
}

@Test func otherFailureStatusIsReported() {
  #expect(throws: CopilotUsageError.httpStatus(500)) {
    try CopilotUsageClient.usage(from: Data(), statusCode: 500)
  }
}

@Test func missingFieldsAreInvalidResponse() {
  #expect(throws: CopilotUsageError.invalidResponse) {
    try CopilotUsageClient.usage(from: Data("{}".utf8), statusCode: 200)
  }
}

@Test func requestSendsTokenOnlyInAuthorizationHeader() {
  let request = CopilotUsageClient.makeRequest(token: "test-token")
  #expect(request.url?.absoluteString == "https://api.github.com/copilot_internal/user")
  #expect(request.value(forHTTPHeaderField: "Authorization") == "token test-token")
  #expect(request.value(forHTTPHeaderField: "Editor-Version") == "vscode/1.99.0")
}

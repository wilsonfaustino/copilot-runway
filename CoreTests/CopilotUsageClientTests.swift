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
  #expect(usage.creditsUsed == 12000 - 3142.7)
  #expect(usage.entitlement == 12000)
  #expect(usage.creditsRemaining == 3142.7)
  #expect(usage.percentRemaining == 26.1)
  #expect(usage.isUnlimited == false)
  #expect(usage.resetDate == utcDate("2026-11-01T00:00:00Z"))
}

func premiumResponse(entitlement: Int, creditsUsed: Int, quotaRemaining: Double, percentRemaining: Double, unlimited: Bool) -> Data {
  Data("""
    {
      "quota_reset_date_utc": "2026-12-01T00:00:00.000Z",
      "quota_snapshots": {
        "premium_interactions": {
          "credits_used": \(creditsUsed),
          "entitlement": \(entitlement),
          "quota_remaining": \(quotaRemaining),
          "percent_remaining": \(percentRemaining),
          "unlimited": \(unlimited)
        }
      }
    }
    """.utf8)
}

@Test func usageUsesOneSourceForUsedAndRemaining() throws {
  let data = premiumResponse(entitlement: 20000, creditsUsed: 1235, quotaRemaining: 18131, percentRemaining: 90.6, unlimited: false)
  let usage = try CopilotUsageClient.usage(from: data, statusCode: 200)
  #expect(usage.creditsUsed == 1869)
  #expect(usage.creditsRemaining == 18131)
  #expect(usage.entitlement - usage.creditsUsed == usage.creditsRemaining)
  #expect(Runway.wholePercentRemaining(usage: usage) == 91)
}

@Test func unlimitedPlanKeepsCreditsUsedFromApi() throws {
  let data = premiumResponse(entitlement: 0, creditsUsed: 50, quotaRemaining: 0, percentRemaining: 100, unlimited: true)
  let usage = try CopilotUsageClient.usage(from: data, statusCode: 200)
  #expect(usage.creditsUsed == 50)
}

@Test func zeroEntitlementKeepsCreditsUsedFromApi() throws {
  let data = premiumResponse(entitlement: 0, creditsUsed: 50, quotaRemaining: 0, percentRemaining: 100, unlimited: false)
  let usage = try CopilotUsageClient.usage(from: data, statusCode: 200)
  #expect(usage.creditsUsed == 50)
}

@Test func overageKeepsNegativeRemainingAndUsedAboveEntitlement() throws {
  let data = premiumResponse(entitlement: 1500, creditsUsed: 1500, quotaRemaining: -40, percentRemaining: 0, unlimited: false)
  let usage = try CopilotUsageClient.usage(from: data, statusCode: 200)
  #expect(usage.creditsUsed == 1540)
  #expect(usage.creditsRemaining == -40)
  #expect(Runway.wholePercentRemaining(usage: usage) == 0)
  #expect(Runway.wholeDaysLeft(usage: usage, now: utcDate("2026-11-10T00:00:00Z")) == 0)
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

@Test func redirectStatusIsInvalidResponse() {
  #expect(throws: CopilotUsageError.invalidResponse) {
    try CopilotUsageClient.usage(from: Data(), statusCode: 302)
  }
}

@Test func errorMessagesTellTheUserWhatToDo() {
  #expect(CopilotUsageError.ghNotFound.message == "GitHub CLI not found. Install it with: brew install gh")
  #expect(CopilotUsageError.notLoggedIn.message == "Not logged in to GitHub. Run: gh auth login")
  #expect(CopilotUsageError.network.message == "Cannot reach api.github.com. Check your connection.")
  #expect(CopilotUsageError.httpStatus(503).message == "GitHub returned HTTP 503.")
  #expect(CopilotUsageError.invalidResponse.message == "GitHub returned an unexpected response.")
}

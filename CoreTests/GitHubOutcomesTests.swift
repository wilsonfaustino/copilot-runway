import Core
import Foundation
import Testing

let outcomesCycleStart = utcDate("2026-10-01T00:00:00Z")

// Shape of `gh search prs --json number` and `gh search commits --json sha` output.
let samplePullRequestResults = Data("""
  [{"number": 12}, {"number": 12}, {"number": 845}]
  """.utf8)
let sampleCommitResults = Data("""
  [{"sha": "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567"}, {"sha": "1b2c3d4e5f60718293a4b5c6d7e8f9012345678a"}]
  """.utf8)

@Test func openedQueryFiltersByAuthorAndCreationDate() {
  let arguments = GitHubOutcomesClient.arguments(for: .prsOpened, organization: "example-org", since: outcomesCycleStart)
  #expect(arguments == [
    "search", "prs", "--owner=example-org", "--author=@me", "--created=>=2026-10-01T00:00:00Z",
    "--json=number", "--limit=1000",
  ])
}

@Test func reviewedQueryExcludesOwnPullRequests() {
  let arguments = GitHubOutcomesClient.arguments(for: .prsReviewed, organization: "example-org", since: outcomesCycleStart)
  #expect(arguments == [
    "search", "prs", "--owner=example-org", "--reviewed-by=@me", "--updated=>=2026-10-01T00:00:00Z",
    "--json=number", "--limit=1000", "--", "-author:@me",
  ])
}

@Test func commitQueryFiltersByAuthorDate() {
  let arguments = GitHubOutcomesClient.arguments(for: .commits, organization: "example-org", since: outcomesCycleStart)
  #expect(arguments == [
    "search", "commits", "--owner=example-org", "--author=@me", "--author-date=>=2026-10-01T00:00:00Z",
    "--json=sha", "--limit=1000",
  ])
}

@Test func organizationThatLooksLikeAFlagStaysAValue() {
  let arguments = GitHubOutcomesClient.arguments(for: .prsOpened, organization: "--web", since: outcomesCycleStart)
  #expect(arguments.contains("--owner=--web"))
  #expect(!arguments.contains("--web"))
}

@Test func dateQualifierIsCycleStartInUTC() {
  #expect(GitHubOutcomesClient.dateQualifier(utcDate("2026-09-15T00:00:00Z")) == ">=2026-09-15T00:00:00Z")
}

@Test func organizationIsTrimmedAndEmptyMeansNotSet() {
  #expect(GitHubOutcomesClient.normalizedOrganization("  example-org\n") == "example-org")
  #expect(GitHubOutcomesClient.normalizedOrganization("   ") == nil)
  #expect(GitHubOutcomesClient.normalizedOrganization("") == nil)
}

@Test func countsSearchResults() throws {
  // PR numbers repeat across repos, so every result counts.
  #expect(try GitHubOutcomesClient.count(from: samplePullRequestResults) == 3)
  #expect(try GitHubOutcomesClient.count(from: sampleCommitResults) == 2)
  #expect(try GitHubOutcomesClient.count(from: Data("[]".utf8)) == 0)
}

@Test func outputThatIsNotAListFails() {
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.count(from: Data("{\"message\": \"error\"}".utf8))
  }
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.count(from: Data())
  }
}

// stderr samples are what gh 2.102 printed in October 2026, with the organization replaced.
@Test func classifiesGhErrors() {
  let noLogin = "To get started with GitHub CLI, please run:  gh auth login"
  #expect(GitHubOutcomesClient.error(exitStatus: 4, standardError: noLogin) == .notLoggedIn)

  let badToken = #"non-200 OK status code: 401 Unauthorized body: "{\"message\": \"Bad credentials\"}""#
  #expect(GitHubOutcomesClient.error(exitStatus: 1, standardError: badToken) == .notLoggedIn)

  let unknownOrganization = """
    Invalid search query "author:@me type:pr user:example-org".
    The listed users and repositories cannot be searched either because the resources do not exist or you do not have permission to view them.
    """
  #expect(GitHubOutcomesClient.error(exitStatus: 1, standardError: unknownOrganization) == .organizationNotFound)

  let rateLimited = "HTTP 403: You have exceeded a secondary rate limit. Please wait a few minutes before you try again."
  #expect(GitHubOutcomesClient.error(exitStatus: 1, standardError: rateLimited) == .rateLimited)

  #expect(GitHubOutcomesClient.error(exitStatus: 1, standardError: "error connecting to api.github.com") == .searchFailed)
}

@Test func errorMessagesDoNotRepeatGhOutput() {
  let errors: [GitHubOutcomesError] = [.ghNotFound, .notLoggedIn, .organizationNotFound, .rateLimited, .searchFailed]
  for error in errors {
    #expect(!error.message.contains("example-org"))
    #expect(!error.message.isEmpty)
  }
}

@Test func creditsPerOutcomeCountsOnlyPullRequests() {
  let outcomes = GitHubOutcomes(prsOpened: 6, prsReviewed: 14, commits: 40)
  #expect(outcomes.outcomeCount == 20)
  #expect(outcomes.creditsPerOutcome(creditsUsed: 3000) == 150)
}

@Test func creditsPerOutcomeIsNilWithoutPullRequests() {
  let outcomes = GitHubOutcomes(prsOpened: 0, prsReviewed: 0, commits: 5)
  #expect(outcomes.creditsPerOutcome(creditsUsed: 3000) == nil)
}

@Test func countAtTheSearchLimitShowsAPlus() {
  #expect(GitHubOutcomes.countText(999) == "999")
  #expect(GitHubOutcomes.countText(1000) == "1,000+")
}

@Test func outcomesFetchIsDueOnLaunchOrganizationChangeAndAfterThirtyMinutes() {
  let startDate = utcDate("2026-10-10T12:00:00Z")
  let lastFetch = OutcomesFetch(organization: "example-org", cycleStart: outcomesCycleStart, startDate: startDate)
  #expect(OutcomesFetch.isDue(lastFetch: nil, organization: "example-org", cycleStart: outcomesCycleStart, now: startDate))
  #expect(OutcomesFetch.isDue(lastFetch: lastFetch, organization: "other-org", cycleStart: outcomesCycleStart, now: startDate))
  // A credits tick 5 minutes later does not search again.
  let fiveMinutesLater = startDate.addingTimeInterval(5 * 60)
  #expect(!OutcomesFetch.isDue(lastFetch: lastFetch, organization: "example-org", cycleStart: outcomesCycleStart, now: fiveMinutesLater))
  let almostThirtyMinutesLater = startDate.addingTimeInterval(30 * 60 - 1)
  #expect(!OutcomesFetch.isDue(lastFetch: lastFetch, organization: "example-org", cycleStart: outcomesCycleStart, now: almostThirtyMinutesLater))
  let thirtyMinutesLater = startDate.addingTimeInterval(30 * 60)
  #expect(OutcomesFetch.isDue(lastFetch: lastFetch, organization: "example-org", cycleStart: outcomesCycleStart, now: thirtyMinutesLater))
}

@Test func outcomesFetchIsDueWhenANewCycleStarts() {
  let startDate = utcDate("2026-10-31T23:50:00Z")
  let lastFetch = OutcomesFetch(organization: "example-org", cycleStart: outcomesCycleStart, startDate: startDate)
  let nextCycleStart = utcDate("2026-11-01T00:00:00Z")
  #expect(OutcomesFetch.isDue(lastFetch: lastFetch, organization: "example-org", cycleStart: nextCycleStart, now: nextCycleStart))
}

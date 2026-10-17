@testable import Core
import Foundation
import Testing

let outcomesCycleStart = utcDate("2026-10-01T00:00:00Z")

@Test func commitsUseRestSearchAndReadOnlyTheTotal() {
  let arguments = GitHubOutcomesClient.commitsArguments(organization: "example-org", since: outcomesCycleStart)
  #expect(arguments == [
    "api", "--method=GET", "search/commits",
    "-f", "q=author:@me author-date:>=2026-10-01T00:00:00Z user:example-org", "-f", "per_page=1",
  ])
}

@Test func pullRequestSearchesFilterByStateAndCreationDate() {
  let openQuery = GitHubOutcomesClient.pullRequestSearchQuery(organization: "example-org", state: "open", since: outcomesCycleStart)
  #expect(openQuery == "org:example-org is:pr author:@me is:open created:>=2026-10-01T00:00:00Z")
  let mergedQuery = GitHubOutcomesClient.pullRequestSearchQuery(organization: "example-org", state: "merged", since: outcomesCycleStart)
  #expect(mergedQuery == "org:example-org is:pr author:@me is:merged created:>=2026-10-01T00:00:00Z")
}

@Test func outcomesArgumentsWithOrganizationSendEverySearchAsVariables() throws {
  let arguments = GitHubOutcomesClient.outcomesArguments(organization: "example-org", login: "example-user", since: outcomesCycleStart)
  #expect(Array(arguments.prefix(3)) == ["api", "graphql", "-f"])
  let document = try #require(arguments.first { $0.hasPrefix("query=") })
  #expect(!document.contains("example-org"))
  #expect(!document.contains("example-user"))
  for alias in ["openPullRequests:", "mergedPullRequests:", "reviewed:", "copilotReviews:"] {
    #expect(document.contains(alias))
  }
  #expect(arguments.dropFirst(4) == [
    "-f", "openQuery=org:example-org is:pr author:@me is:open created:>=2026-10-01T00:00:00Z",
    "-f", "mergedQuery=org:example-org is:pr author:@me is:merged created:>=2026-10-01T00:00:00Z",
    "-f", "reviewedQuery=org:example-org is:pr reviewed-by:@me -author:@me updated:>=2026-10-01T00:00:00Z",
    "-f", "login=example-user",
    "-f", "copilotQuery=author:@me is:pr updated:>=2026-10-01T00:00:00Z",
  ])
}

@Test func outcomesArgumentsWithoutOrganizationSendOnlyTheCopilotSearch() throws {
  let arguments = GitHubOutcomesClient.outcomesArguments(organization: nil, login: nil, since: outcomesCycleStart)
  #expect(arguments.count == 6)
  #expect(arguments.suffix(2) == ["-f", "copilotQuery=author:@me is:pr updated:>=2026-10-01T00:00:00Z"])
  // GraphQL rejects a declared variable that the document does not use.
  let document = try #require(arguments.first { $0.hasPrefix("query=") })
  #expect(!document.contains("$login"))
  #expect(!document.contains("openPullRequests"))
  #expect(!document.contains("reviewed:"))
}

@Test func reviewedSearchExcludesOwnPullRequests() {
  let query = GitHubOutcomesClient.reviewedSearchQuery(organization: "example-org", since: outcomesCycleStart)
  #expect(query == "org:example-org is:pr reviewed-by:@me -author:@me updated:>=2026-10-01T00:00:00Z")
}

@Test func reviewedArgumentsSendOrganizationAndLoginAsVariables() throws {
  let arguments = GitHubOutcomesClient.reviewedArguments(
    organization: "example-org", login: "example-user", since: outcomesCycleStart, after: nil
  )
  #expect(Array(arguments.prefix(3)) == ["api", "graphql", "-f"])
  let document = try #require(arguments.first { $0.hasPrefix("query=") })
  #expect(!document.contains("example-org"))
  #expect(!document.contains("example-user"))
  #expect(arguments.suffix(4) == [
    "-f", "q=org:example-org is:pr reviewed-by:@me -author:@me updated:>=2026-10-01T00:00:00Z",
    "-f", "login=example-user",
  ])
  #expect(!arguments.contains { $0.hasPrefix("after=") })
}

@Test func reviewedArgumentsSendCursorForLaterPages() {
  let arguments = GitHubOutcomesClient.reviewedArguments(
    organization: "example-org", login: "example-user", since: outcomesCycleStart, after: "Y3Vyc29yOjEwMA=="
  )
  #expect(arguments.suffix(2) == ["-f", "after=Y3Vyc29yOjEwMA=="])
}

@Test func organizationMustBeAGitHubLogin() {
  #expect(GitHubOutcomesClient.isValidOrganization("example-org"))
  #expect(GitHubOutcomesClient.isValidOrganization("Example-Org-2"))
  #expect(!GitHubOutcomesClient.isValidOrganization("foo is:open"))
  #expect(!GitHubOutcomesClient.isValidOrganization("-x"))
  #expect(!GitHubOutcomesClient.isValidOrganization("foo:bar"))
  #expect(!GitHubOutcomesClient.isValidOrganization(""))
}

@Test func organizationThatLooksLikeAFlagStaysAValue() {
  let arguments = GitHubOutcomesClient.commitsArguments(organization: "--web", since: outcomesCycleStart)
  #expect(arguments.contains("q=author:@me author-date:>=2026-10-01T00:00:00Z user:--web"))
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

// Shape of `gh api --method=GET search/commits -f per_page=1` output.
@Test func readsTheCommitTotalCount() throws {
  let response = Data("""
    {"total_count": 1234, "incomplete_results": false, "items": [{"sha": "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567"}]}
    """.utf8)
  #expect(try GitHubOutcomesClient.totalCount(from: response) == 1234)
  #expect(try GitHubOutcomesClient.totalCount(from: Data(#"{"total_count": 0, "incomplete_results": false, "items": []}"#.utf8)) == 0)
}

// Shape of the reviewed search response. Each node is one PR with your last submitted review, if any.
func reviewedResponse(_ nodes: String, hasNextPage: Bool = false) -> Data {
  Data("""
    {"data": {"search": {"pageInfo": {"hasNextPage": \(hasNextPage), "endCursor": "Y3Vyc29yOjEwMA=="}, "nodes": [\(nodes)]}}}
    """.utf8)
}

func reviewNode(_ submittedAt: String) -> String {
  #"{"reviews": {"nodes": [{"submittedAt": "\#(submittedAt)"}]}}"#
}

@Test func reviewedCountsOnlyLastReviewsInTheCycle() throws {
  let lastReviewBeforeCycle = reviewNode("2026-09-30T23:59:59Z")
  let lastReviewInCycle = reviewNode("2026-10-07T10:00:00Z")
  let page = try GitHubOutcomesClient.reviewedPage(
    from: reviewedResponse([lastReviewBeforeCycle, lastReviewInCycle].joined(separator: ",")), since: outcomesCycleStart
  )
  #expect(page.reviewedCount == 1)
  #expect(page.resultCount == 2)
  #expect(page.nextCursor == nil)
}

@Test func reviewedCountsReviewAtCycleStart() throws {
  let page = try GitHubOutcomesClient.reviewedPage(
    from: reviewedResponse(reviewNode("2026-10-01T00:00:00Z")), since: outcomesCycleStart
  )
  #expect(page.reviewedCount == 1)
}

@Test func reviewedSkipsPullRequestsWithOnlyPendingReviews() throws {
  // The states filter leaves out pending reviews, so the list is empty.
  let page = try GitHubOutcomesClient.reviewedPage(
    from: reviewedResponse(#"{"reviews": {"nodes": []}}, {}"#), since: outcomesCycleStart
  )
  #expect(page.reviewedCount == 0)
  #expect(page.resultCount == 2)
}

@Test func reviewedPageGivesCursorOnlyWhenMorePagesExist() throws {
  let page = try GitHubOutcomesClient.reviewedPage(
    from: reviewedResponse(reviewNode("2026-10-07T10:00:00Z"), hasNextPage: true), since: outcomesCycleStart
  )
  #expect(page.nextCursor == "Y3Vyc29yOjEwMA==")
}

@Test func graphQLErrorsThrowInsteadOfCountingZero() {
  let errorsWithData = Data("""
    {"data": {"search": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": []}},
     "errors": [{"message": "Something went wrong while executing your query."}]}
    """.utf8)
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.reviewedPage(from: errorsWithData, since: outcomesCycleStart)
  }
  let rateLimited = Data(#"{"data": null, "errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded for user ID 1."}]}"#.utf8)
  #expect(throws: GitHubOutcomesError.rateLimited) {
    try GitHubOutcomesClient.reviewedPage(from: rateLimited, since: outcomesCycleStart)
  }
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.reviewedPage(from: Data("[]".utf8), since: outcomesCycleStart)
  }
}

@Test func readsViewerLogin() throws {
  #expect(try GitHubOutcomesClient.login(from: Data(#"{"data": {"viewer": {"login": "example-user"}}}"#.utf8)) == "example-user")
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.login(from: Data(#"{"data": {"viewer": null}}"#.utf8))
  }
}

@Test func commitOutputWithoutATotalFails() {
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.totalCount(from: Data("{\"message\": \"error\"}".utf8))
  }
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.totalCount(from: Data())
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
  let outcomes = GitHubOutcomes(prsMerged: 4, prsOpen: 2, prsReviewed: 14, commits: 40)
  #expect(outcomes.outcomeCount == 20)
  #expect(outcomes.creditsPerOutcome(creditsUsed: 3000) == 150)
}

@Test func creditsPerOutcomeIsNilWithoutPullRequests() {
  let outcomes = GitHubOutcomes(prsMerged: 0, prsOpen: 0, prsReviewed: 0, commits: 5)
  #expect(outcomes.creditsPerOutcome(creditsUsed: 3000) == nil)
}

@Test func countTextIsExactAboveTheSearchLimit() {
  #expect(GitHubOutcomes.countText(999) == "999")
  #expect(GitHubOutcomes.countText(1000) == "1,000")
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

@Test func outcomesFetchWithoutOrganizationIsDueWhenOneIsSet() {
  let startDate = utcDate("2026-10-10T12:00:00Z")
  let lastFetch = OutcomesFetch(organization: nil, cycleStart: outcomesCycleStart, startDate: startDate)
  let fiveMinutesLater = startDate.addingTimeInterval(5 * 60)
  #expect(!OutcomesFetch.isDue(lastFetch: lastFetch, organization: nil, cycleStart: outcomesCycleStart, now: fiveMinutesLater))
  #expect(OutcomesFetch.isDue(lastFetch: lastFetch, organization: "example-org", cycleStart: outcomesCycleStart, now: fiveMinutesLater))
}

func searchJSON(_ nodes: String, hasNextPage: Bool) -> String {
  #"{"pageInfo": {"hasNextPage": \#(hasNextPage), "endCursor": "Y3Vyc29yOjEwMA=="}, "nodes": [\#(nodes)]}"#
}

// Shape of the combined outcomes response. pullRequests nil gives the response without an organization.
func combinedResponse(
  pullRequests: (open: Int, merged: Int)? = nil,
  reviewedNodes: String = "",
  reviewedHasNextPage: Bool = false,
  copilotNodes: String,
  copilotHasNextPage: Bool = false
) -> Data {
  var searches = [#""copilotReviews": \#(searchJSON(copilotNodes, hasNextPage: copilotHasNextPage))"#]
  if let pullRequests {
    searches += [
      #""openPullRequests": {"issueCount": \#(pullRequests.open)}"#,
      #""mergedPullRequests": {"issueCount": \#(pullRequests.merged)}"#,
      #""reviewed": \#(searchJSON(reviewedNodes, hasNextPage: reviewedHasNextPage))"#,
    ]
  }
  return Data(#"{"data": {\#(searches.joined(separator: ", "))}}"#.utf8)
}

let copilotReviewInCycle = pullRequestNode(reviewJSON(login: copilotLogin, submittedAt: "2026-10-07T10:00:00Z"))

@Test func combinedResponseAddsOpenAndMergedPullRequests() throws {
  let reviewedNodes = [reviewNode("2026-09-30T23:59:59Z"), reviewNode("2026-10-07T10:00:00Z")].joined(separator: ",")
  let humanReview = reviewJSON(login: "example-reviewer", submittedAt: "2026-10-07T11:00:00Z")
  let copilotReview = reviewJSON(login: copilotLogin, submittedAt: "2026-10-07T10:00:00Z")
  let data = combinedResponse(
    pullRequests: (open: 2, merged: 17), reviewedNodes: reviewedNodes, copilotNodes: pullRequestNode(copilotReview, humanReview)
  )
  let response = try GitHubOutcomesClient.outcomesResponse(from: data, includesOrganization: true, since: outcomesCycleStart)
  #expect(response.pullRequestCounts?.merged == 17)
  #expect(response.pullRequestCounts?.open == 2)
  let reviewedPage = try #require(response.reviewedPage)
  #expect(reviewedPage.reviewedCount == 1)
  #expect(reviewedPage.resultCount == 2)
  #expect(reviewedPage.nextCursor == nil)
  #expect(response.copilotReviewPage.reviewCount == 1)
  #expect(response.copilotReviewPage.nextCursor == nil)
}

@Test func combinedResponseWithoutOrganizationHasOnlyTheCopilotPage() throws {
  let data = combinedResponse(copilotNodes: copilotReviewInCycle, copilotHasNextPage: true)
  let response = try GitHubOutcomesClient.outcomesResponse(from: data, includesOrganization: false, since: outcomesCycleStart)
  #expect(response.pullRequestCounts == nil)
  #expect(response.reviewedPage == nil)
  #expect(response.copilotReviewPage.reviewCount == 1)
  #expect(response.copilotReviewPage.nextCursor == "Y3Vyc29yOjEwMA==")
}

@Test func combinedResponseFailsWhenAnOrganizationSearchIsMissing() {
  let data = combinedResponse(copilotNodes: copilotReviewInCycle)
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.outcomesResponse(from: data, includesOrganization: true, since: outcomesCycleStart)
  }
}

@Test func combinedResponseThrowsOnGraphQLErrors() {
  let rateLimited = Data(#"{"data": null, "errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded for user ID 1."}]}"#.utf8)
  #expect(throws: GitHubOutcomesError.rateLimited) {
    try GitHubOutcomesClient.outcomesResponse(from: rateLimited, includesOrganization: true, since: outcomesCycleStart)
  }
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.outcomesResponse(from: Data("[]".utf8), includesOrganization: false, since: outcomesCycleStart)
  }
}

let commitsCall = GitHubOutcomesClient.commitsArguments(organization: "example-org", since: outcomesCycleStart)
let combinedCall = GitHubOutcomesClient.outcomesArguments(organization: "example-org", login: "example-user", since: outcomesCycleStart)
let copilotOnlyCall = GitHubOutcomesClient.outcomesArguments(organization: nil, login: nil, since: outcomesCycleStart)
let commitsResponse = Data(#"{"total_count": 19, "incomplete_results": false, "items": []}"#.utf8)
let organizationResponse = combinedResponse(
  pullRequests: (open: 2, merged: 17), reviewedNodes: reviewNode("2026-10-07T10:00:00Z"), copilotNodes: copilotReviewInCycle
)

// Runs a fetch with gh replaced by fixed responses, and records each gh call. A call with no response fails.
func fetchActivity(
  organization: String?,
  login: String?,
  responses: [[String]: Result<Data, GitHubOutcomesError>]
) async throws(GitHubOutcomesError) -> (activity: GitHubActivity, calls: [[String]]) {
  var calls: [[String]] = []
  let activity = try await GitHubOutcomesClient.fetchActivity(organization: organization, login: login, since: outcomesCycleStart) {
    arguments throws(GitHubOutcomesError) in
    calls.append(arguments)
    guard let response = responses[arguments] else { throw GitHubOutcomesError.searchFailed }
    return try response.get()
  }
  return (activity, calls)
}

@Test func fetchWithoutOrganizationRunsOnlyTheCopilotSearch() async throws {
  let result = try await fetchActivity(
    organization: nil, login: nil, responses: [copilotOnlyCall: .success(combinedResponse(copilotNodes: copilotReviewInCycle))]
  )
  #expect(result.calls == [copilotOnlyCall])
  #expect(result.activity == GitHubActivity(outcomes: nil, copilotReviewCount: 1, login: nil))
}

@Test func fetchWithOrganizationAndKnownLoginRunsTwoRequests() async throws {
  let result = try await fetchActivity(
    organization: "example-org", login: "example-user",
    responses: [commitsCall: .success(commitsResponse), combinedCall: .success(organizationResponse)]
  )
  #expect(result.calls == [commitsCall, combinedCall])
  let outcomes = GitHubOutcomes(prsMerged: 17, prsOpen: 2, prsReviewed: 1, commits: 19)
  #expect(result.activity == GitHubActivity(outcomes: .success(outcomes), copilotReviewCount: 1, login: "example-user"))
}

@Test func fetchGetsTheLoginWhenItIsNotKnownYet() async throws {
  let result = try await fetchActivity(
    organization: "example-org", login: nil,
    responses: [
      commitsCall: .success(commitsResponse),
      GitHubOutcomesClient.loginArguments: .success(Data(#"{"data": {"viewer": {"login": "example-user"}}}"#.utf8)),
      combinedCall: .success(organizationResponse),
    ]
  )
  #expect(result.calls == [commitsCall, GitHubOutcomesClient.loginArguments, combinedCall])
  #expect(result.activity.login == "example-user")
}

@Test func fetchRunsALaterReviewedPageOnlyWhenThereIsOne() async throws {
  let firstResponse = combinedResponse(
    pullRequests: (open: 2, merged: 17), reviewedNodes: reviewNode("2026-10-07T10:00:00Z"), reviewedHasNextPage: true,
    copilotNodes: copilotReviewInCycle
  )
  let nextPageCall = GitHubOutcomesClient.reviewedArguments(
    organization: "example-org", login: "example-user", since: outcomesCycleStart, after: "Y3Vyc29yOjEwMA=="
  )
  let result = try await fetchActivity(
    organization: "example-org", login: "example-user",
    responses: [
      commitsCall: .success(commitsResponse),
      combinedCall: .success(firstResponse),
      nextPageCall: .success(reviewedResponse(reviewNode("2026-10-08T10:00:00Z"))),
    ]
  )
  #expect(result.calls == [commitsCall, combinedCall, nextPageCall])
  #expect(try result.activity.outcomes?.get().prsReviewed == 2)
  #expect(result.activity.copilotReviewCount == 1)
}

@Test func fetchRunsALaterCopilotPageOnlyWhenThereIsOne() async throws {
  let nextPageCall = GitHubOutcomesClient.copilotReviewArguments(since: outcomesCycleStart, after: "Y3Vyc29yOjEwMA==")
  let result = try await fetchActivity(
    organization: nil, login: nil,
    responses: [
      copilotOnlyCall: .success(combinedResponse(copilotNodes: copilotReviewInCycle, copilotHasNextPage: true)),
      nextPageCall: .success(copilotReviewResponse(copilotReviewInCycle)),
    ]
  )
  #expect(result.calls == [copilotOnlyCall, nextPageCall])
  #expect(result.activity.copilotReviewCount == 2)
}

@Test func invalidOrganizationFailsTheOutcomesBeforeAnyOrganizationSearch() async throws {
  let result = try await fetchActivity(
    organization: "foo is:open", login: "example-user",
    responses: [copilotOnlyCall: .success(combinedResponse(copilotNodes: copilotReviewInCycle))]
  )
  #expect(result.calls == [copilotOnlyCall])
  #expect(result.activity == GitHubActivity(outcomes: .failure(.organizationNotFound), copilotReviewCount: 1, login: "example-user"))
}

@Test func unknownOrganizationFailsTheOutcomesButKeepsTheCopilotCount() async throws {
  let result = try await fetchActivity(
    organization: "example-org", login: nil,
    responses: [
      commitsCall: .failure(.organizationNotFound),
      copilotOnlyCall: .success(combinedResponse(copilotNodes: copilotReviewInCycle)),
    ]
  )
  #expect(result.calls == [commitsCall, copilotOnlyCall])
  #expect(result.activity == GitHubActivity(outcomes: .failure(.organizationNotFound), copilotReviewCount: 1, login: nil))
}

@Test func failedCombinedRequestFailsTheFetch() async {
  await #expect(throws: GitHubOutcomesError.rateLimited) {
    try await fetchActivity(
      organization: "example-org", login: "example-user",
      responses: [commitsCall: .success(commitsResponse), combinedCall: .failure(.rateLimited)]
    )
  }
}

@Test func restErrorIsClassifiedFromTheResponseBody() async {
  // gh api prints a REST error body to stdout and only "HTTP 422" to stderr. Sample from gh 2.102 in October 2026.
  let body = #"{"message":"Validation Failed","errors":[{"message":"The listed users and repositories cannot be searched either because the resources do not exist or you do not have permission to view them.","resource":"Search","field":"q","code":"invalid"}],"status":"422"}"#
  let script = "printf '%s' '\(body)'; echo 'gh: Validation Failed (HTTP 422)' >&2; exit 1"
  await #expect(throws: GitHubOutcomesError.organizationNotFound) {
    try await GitHubOutcomesClient.runGh(ghPath: "/bin/sh", arguments: ["-c", script])
  }
}

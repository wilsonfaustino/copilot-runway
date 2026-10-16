import Core
import Foundation
import Testing

// Shape of the review search response. Each node is one PR of yours with its reviews.
func copilotReviewResponse(_ nodes: String, hasNextPage: Bool = false) -> Data {
  Data("""
    {"data": {"search": {"pageInfo": {"hasNextPage": \(hasNextPage), "endCursor": "Y3Vyc29yOjEwMA=="}, "nodes": [\(nodes)]}}}
    """.utf8)
}

func reviewJSON(login: String?, submittedAt: String?) -> String {
  let author = login.map { #"{"login": "\#($0)"}"# } ?? "null"
  let submitted = submittedAt.map { #""\#($0)""# } ?? "null"
  return #"{"author": \#(author), "submittedAt": \#(submitted)}"#
}

func pullRequestNode(_ reviews: String...) -> String {
  #"{"reviews": {"nodes": [\#(reviews.joined(separator: ","))]}}"#
}

let copilotLogin = "copilot-pull-request-reviewer"

@Test func copilotReviewQueryUsesOwnPullRequestsWithoutOrganization() {
  let query = GitHubOutcomesClient.copilotReviewSearchQuery(since: outcomesCycleStart)
  #expect(query == "author:@me is:pr updated:>=2026-10-01T00:00:00Z")
  #expect(!query.contains("org:"))
}

@Test func copilotReviewArgumentsSendQueryAsVariable() throws {
  let arguments = GitHubOutcomesClient.copilotReviewArguments(since: outcomesCycleStart, after: nil)
  #expect(Array(arguments.prefix(3)) == ["api", "graphql", "-f"])
  let document = try #require(arguments.first { $0.hasPrefix("query=") })
  #expect(!document.contains("author:@me"))
  #expect(arguments.suffix(2) == ["-f", "q=author:@me is:pr updated:>=2026-10-01T00:00:00Z"])
  #expect(!arguments.contains { $0.hasPrefix("after=") })
}

@Test func copilotReviewArgumentsSendCursorForLaterPages() {
  let arguments = GitHubOutcomesClient.copilotReviewArguments(since: outcomesCycleStart, after: "Y3Vyc29yOjEwMA==")
  #expect(arguments.suffix(2) == ["-f", "after=Y3Vyc29yOjEwMA=="])
}

@Test func copilotReviewCountSkipsHumanReviews() throws {
  let copilotReview = reviewJSON(login: copilotLogin, submittedAt: "2026-10-07T10:00:00Z")
  let humanReview = reviewJSON(login: "example-reviewer", submittedAt: "2026-10-07T11:00:00Z")
  let page = try GitHubOutcomesClient.copilotReviewPage(
    from: copilotReviewResponse(pullRequestNode(copilotReview, humanReview)), since: outcomesCycleStart
  )
  #expect(page.reviewCount == 1)
  #expect(page.resultCount == 1)
  #expect(page.nextCursor == nil)
}

@Test func copilotReviewCountSkipsReviewsBeforeTheCycle() throws {
  let beforeCycle = reviewJSON(login: copilotLogin, submittedAt: "2026-09-30T23:59:59Z")
  let atCycleStart = reviewJSON(login: copilotLogin, submittedAt: "2026-10-01T00:00:00Z")
  let afterCycleStart = reviewJSON(login: copilotLogin, submittedAt: "2026-10-12T08:30:00Z")
  let page = try GitHubOutcomesClient.copilotReviewPage(
    from: copilotReviewResponse(pullRequestNode(beforeCycle, atCycleStart, afterCycleStart)), since: outcomesCycleStart
  )
  #expect(page.reviewCount == 2)
}

@Test func copilotReviewCountAddsReviewsAcrossPullRequests() throws {
  let first = reviewJSON(login: copilotLogin, submittedAt: "2026-10-03T09:00:00Z")
  let second = reviewJSON(login: copilotLogin, submittedAt: "2026-10-04T09:00:00Z")
  let nodes = [pullRequestNode(first, second), pullRequestNode(first), pullRequestNode()].joined(separator: ",")
  let page = try GitHubOutcomesClient.copilotReviewPage(from: copilotReviewResponse(nodes), since: outcomesCycleStart)
  #expect(page.reviewCount == 3)
  #expect(page.resultCount == 3)
}

@Test func copilotReviewCountSkipsPendingReviewsAndDeletedAuthors() throws {
  let pending = reviewJSON(login: copilotLogin, submittedAt: nil)
  let deletedAuthor = reviewJSON(login: nil, submittedAt: "2026-10-07T10:00:00Z")
  let page = try GitHubOutcomesClient.copilotReviewPage(
    from: copilotReviewResponse(pullRequestNode(pending, deletedAuthor)), since: outcomesCycleStart
  )
  #expect(page.reviewCount == 0)
}

@Test func copilotReviewCountIsZeroForAnEmptyResult() throws {
  let page = try GitHubOutcomesClient.copilotReviewPage(from: copilotReviewResponse(""), since: outcomesCycleStart)
  #expect(page.reviewCount == 0)
  #expect(page.resultCount == 0)
  #expect(page.nextCursor == nil)
}

@Test func copilotReviewPageGivesCursorOnlyWhenMorePagesExist() throws {
  let review = reviewJSON(login: copilotLogin, submittedAt: "2026-10-07T10:00:00Z")
  let firstPage = try GitHubOutcomesClient.copilotReviewPage(
    from: copilotReviewResponse(pullRequestNode(review), hasNextPage: true), since: outcomesCycleStart
  )
  #expect(firstPage.nextCursor == "Y3Vyc29yOjEwMA==")
  let lastPage = try GitHubOutcomesClient.copilotReviewPage(
    from: copilotReviewResponse(pullRequestNode(review), hasNextPage: false), since: outcomesCycleStart
  )
  #expect(lastPage.nextCursor == nil)
}

@Test func copilotReviewPageThrowsOnGraphQLErrors() {
  let rateLimited = Data(#"{"data": null, "errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded for user ID 1."}]}"#.utf8)
  #expect(throws: GitHubOutcomesError.rateLimited) {
    try GitHubOutcomesClient.copilotReviewPage(from: rateLimited, since: outcomesCycleStart)
  }
  #expect(throws: GitHubOutcomesError.searchFailed) {
    try GitHubOutcomesClient.copilotReviewPage(from: Data("[]".utf8), since: outcomesCycleStart)
  }
}

@Test func copilotReviewCountFetchIsDueOnLaunchAfterThirtyMinutesAndInANewCycle() {
  let startDate = utcDate("2026-10-10T12:00:00Z")
  let lastFetch = CopilotReviewCountFetch(cycleStart: outcomesCycleStart, startDate: startDate)
  #expect(CopilotReviewCountFetch.isDue(lastFetch: nil, cycleStart: outcomesCycleStart, now: startDate))
  #expect(!CopilotReviewCountFetch.isDue(lastFetch: lastFetch, cycleStart: outcomesCycleStart, now: startDate.addingTimeInterval(5 * 60)))
  #expect(CopilotReviewCountFetch.isDue(lastFetch: lastFetch, cycleStart: outcomesCycleStart, now: startDate.addingTimeInterval(30 * 60)))
  let nextCycleStart = utcDate("2026-11-01T00:00:00Z")
  #expect(CopilotReviewCountFetch.isDue(lastFetch: lastFetch, cycleStart: nextCycleStart, now: startDate))
}

@Test func copilotReviewSentenceIsNilWithoutReviews() {
  #expect(RunwayInsight.copilotReviewSentence(count: 0) == nil)
}

@Test func copilotReviewSentenceUsesSingularForOneReview() {
  #expect(
    RunwayInsight.copilotReviewSentence(count: 1)
      == "1 Copilot code review ran on your PRs this cycle. It uses credits that local sessions do not show."
  )
}

@Test func copilotReviewSentenceUsesPluralForManyReviews() {
  #expect(
    RunwayInsight.copilotReviewSentence(count: 14)
      == "14 Copilot code reviews ran on your PRs this cycle. They use credits that local sessions do not show."
  )
}

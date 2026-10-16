@testable import Core
import Foundation
import Testing

// A stand-in for gh that never ends. exec keeps one process, so terminate closes the pipes.
private func makeHangingGh() throws -> URL {
  let scriptURL = FileManager.default.temporaryDirectory.appending(path: "hanging-gh-\(UUID().uuidString)")
  try Data("#!/bin/sh\nexec /bin/sleep 60\n".utf8).write(to: scriptURL)
  try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
  return scriptURL
}

@Test func runnerReturnsOutputAndExitStatus() async throws {
  let output = try await GhRunner.run(path: "/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"], readsStandardError: true)
  #expect(output.exitStatus == 3)
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "out\n")
  #expect(String(decoding: output.standardError, as: UTF8.self) == "err\n")
}

@Test func runnerDrainsOutputLargerThanThePipeBuffer() async throws {
  // 200 KB on each pipe is more than the 64 KB pipe buffer.
  let script = "head -c 204800 /dev/zero; head -c 204800 /dev/zero >&2"
  let output = try await GhRunner.run(path: "/bin/sh", arguments: ["-c", script], readsStandardError: true, timeout: .seconds(10))
  #expect(output.standardOutput.count == 204_800)
  #expect(output.standardError.count == 204_800)
}

@Test func runnerStopsAProcessAtTheTimeLimit() async {
  let clock = ContinuousClock()
  let start = clock.now
  await #expect(throws: GhRunner.Failure.timedOut) {
    try await GhRunner.run(path: "/bin/sleep", arguments: ["60"], readsStandardError: true, timeout: .seconds(1))
  }
  #expect(clock.now - start < .seconds(5))
}

@Test func runnerReportsALaunchFailure() async {
  await #expect(throws: GhRunner.Failure.launchFailed) {
    try await GhRunner.run(path: "/nonexistent/gh", arguments: [], readsStandardError: false)
  }
}

@Test func tokenTimeoutIsANetworkError() async throws {
  let hangingGh = try makeHangingGh()
  defer { try? FileManager.default.removeItem(at: hangingGh) }
  let clock = ContinuousClock()
  let start = clock.now
  await #expect(throws: CopilotUsageError.network) {
    try await CopilotUsageClient.readGitHubToken(ghPath: hangingGh.path, timeout: .seconds(1))
  }
  #expect(clock.now - start < .seconds(5))
}

@Test func outcomesTimeoutIsASearchFailure() async {
  let clock = ContinuousClock()
  let start = clock.now
  await #expect(throws: GitHubOutcomesError.searchFailed) {
    try await GitHubOutcomesClient.runGh(ghPath: "/bin/sleep", arguments: ["60"], timeout: .seconds(1))
  }
  #expect(clock.now - start < .seconds(5))
}

@Test func redirectIsRefused() async {
  let url = URL(string: "https://api.github.com/copilot_internal/user")!
  let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://example.com/"])!
  let task = URLSession.shared.dataTask(with: url)
  let newRequest = await RedirectRefusal().urlSession(
    URLSession.shared,
    task: task,
    willPerformHTTPRedirection: redirect,
    newRequest: URLRequest(url: URL(string: "https://example.com/")!)
  )
  #expect(newRequest == nil)
}

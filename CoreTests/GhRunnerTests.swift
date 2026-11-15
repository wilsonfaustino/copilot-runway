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

@Test func runnerAddsExtraEnvironmentToTheInheritedOne() async throws {
  let inheritedHome = try #require(ProcessInfo.processInfo.environment["HOME"])
  let output = try await GhRunner.run(
    path: "/bin/sh", arguments: ["-c", "echo \"$RUNWAY_TEST_VALUE:$HOME\""],
    readsStandardError: false, extraEnvironment: ["RUNWAY_TEST_VALUE": "set"]
  )
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "set:\(inheritedHome)\n")
}

@Test func runnerExtraEnvironmentOverridesAnInheritedKey() async throws {
  let output = try await GhRunner.run(
    path: "/bin/sh", arguments: ["-c", "echo \"$HOME\""],
    readsStandardError: false, extraEnvironment: ["HOME": "/runway-test-home"]
  )
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "/runway-test-home\n")
}

@Test func runnerGivesTheProcessAnEmptyStdin() async throws {
  // read fails on EOF at once; with an open stdin it would wait until the time limit.
  let output = try await GhRunner.run(
    path: "/bin/sh", arguments: ["-c", "read answer; echo \"exit $?\""],
    readsStandardError: false, timeout: .seconds(5)
  )
  #expect(String(decoding: output.standardOutput, as: UTF8.self) == "exit 1\n")
}

@Test func runnerSendsInterruptAtTheTimeLimitWhenAsked() async throws {
  let markerURL = FileManager.default.temporaryDirectory.appending(path: "interrupt-marker-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: markerURL) }
  // Like brew update: clean up on SIGINT, then exit. The sleep runs in the background so the trap fires at once.
  let script = "trap 'touch \"$0\"; exit 130' INT; /bin/sleep 60 & wait"
  await #expect(throws: GhRunner.Failure.timedOut) {
    try await GhRunner.run(
      path: "/bin/sh", arguments: ["-c", script, markerURL.path],
      readsStandardError: false, timeout: .seconds(1), interruptsAtTimeLimit: true
    )
  }
  let clock = ContinuousClock()
  let deadline = clock.now + .seconds(2)
  while !FileManager.default.fileExists(atPath: markerURL.path), clock.now < deadline {
    try await Task.sleep(for: .milliseconds(50))
  }
  #expect(FileManager.default.fileExists(atPath: markerURL.path))
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

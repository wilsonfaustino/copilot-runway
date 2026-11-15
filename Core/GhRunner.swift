import Foundation
import os

// Runs a command line tool (gh, brew) without blocking a thread while it runs, and stops it after a time limit.
// Both pipes drain while the tool runs, so a full pipe cannot stop it.
enum GhRunner {
  // A tool can wait for ever, for example gh on a keychain prompt that nobody answers.
  static let defaultTimeout: Duration = .seconds(30)
  // After SIGINT, brew needs time to clean up and release its lock. A retry that starts too early hits that lock.
  static let interruptGracePeriod: Duration = .seconds(10)

  struct Output: Sendable {
    let exitStatus: Int32
    let standardOutput: Data
    let standardError: Data
  }

  enum Failure: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
  }

  // stderr goes to /dev/null unless readsStandardError is true. stdin is always empty, so a prompt fails at once.
  // interruptsAtTimeLimit sends SIGINT instead of SIGTERM: brew update cleans up its fetch children on SIGINT only.
  // It also waits for the process to exit (up to interruptGracePeriod) before it reports the time limit.
  static func run(
    path: String,
    arguments: [String],
    readsStandardError: Bool,
    timeout: Duration = defaultTimeout,
    extraEnvironment: [String: String] = [:],
    interruptsAtTimeLimit: Bool = false
  ) async throws(Failure) -> Output {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    if !extraEnvironment.isEmpty {
      process.environment = ProcessInfo.processInfo.environment.merging(extraEnvironment) { _, extraValue in extraValue }
    }
    process.standardInput = FileHandle.nullDevice
    let outputPipe = Pipe()
    let errorPipe = readsStandardError ? Pipe() : nil
    process.standardOutput = outputPipe
    process.standardError = errorPipe ?? FileHandle.nullDevice
    var timeoutTask: Task<Void, Never>?
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Output, Failure>, Never>) in
      let run = RunState(continuation: continuation, openPipeCount: errorPipe == nil ? 1 : 2)
      process.terminationHandler = { run.exited(status: $0.terminationStatus) }
      do {
        try process.run()
      } catch {
        run.end(with: .launchFailed)
        return
      }
      outputPipe.fileHandleForReading.readabilityHandler = { run.read(from: $0, isStandardError: false) }
      errorPipe?.fileHandleForReading.readabilityHandler = { run.read(from: $0, isStandardError: true) }
      timeoutTask = Task {
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        guard let continuation = run.claim() else { return }
        if interruptsAtTimeLimit {
          process.interrupt()
          let graceEnd = ContinuousClock.now + interruptGracePeriod
          while process.isRunning, ContinuousClock.now < graceEnd {
            try? await Task.sleep(for: .milliseconds(50))
          }
          if process.isRunning { process.terminate() }
        } else {
          process.terminate()
        }
        continuation.resume(returning: .failure(.timedOut))
      }
    }
    timeoutTask?.cancel()
    return try result.get()
  }
}

// Hands the continuation to exactly one owner: the exit and pipe path, a launch failure, or the time limit.
private final class RunState: Sendable {
  private struct Fields: Sendable {
    var continuation: CheckedContinuation<Result<GhRunner.Output, GhRunner.Failure>, Never>?
    var openPipeCount: Int
    var exitStatus: Int32?
    var standardOutput = Data()
    var standardError = Data()
  }

  private let fields: OSAllocatedUnfairLock<Fields>

  init(continuation: CheckedContinuation<Result<GhRunner.Output, GhRunner.Failure>, Never>, openPipeCount: Int) {
    fields = OSAllocatedUnfairLock(initialState: Fields(continuation: continuation, openPipeCount: openPipeCount))
  }

  func read(from handle: FileHandle, isStandardError: Bool) {
    let chunk = handle.availableData
    // An empty chunk is the end of the pipe. Without this, the handler keeps firing.
    if chunk.isEmpty { handle.readabilityHandler = nil }
    finishIfDone { fields in
      if chunk.isEmpty {
        fields.openPipeCount -= 1
      } else if isStandardError {
        fields.standardError.append(chunk)
      } else {
        fields.standardOutput.append(chunk)
      }
    }
  }

  func exited(status: Int32) {
    finishIfDone { $0.exitStatus = status }
  }

  // Returns the continuation only to the first caller. That caller must resume it, and the exit path then never does.
  func claim() -> CheckedContinuation<Result<GhRunner.Output, GhRunner.Failure>, Never>? {
    fields.withLock { fields in
      defer { fields.continuation = nil }
      return fields.continuation
    }
  }

  func end(with failure: GhRunner.Failure) {
    claim()?.resume(returning: .failure(failure))
  }

  private func finishIfDone(_ change: @Sendable (inout Fields) -> Void) {
    let finished = fields.withLock { fields -> (CheckedContinuation<Result<GhRunner.Output, GhRunner.Failure>, Never>, GhRunner.Output)? in
      change(&fields)
      guard fields.openPipeCount == 0, let exitStatus = fields.exitStatus, let continuation = fields.continuation else {
        return nil
      }
      fields.continuation = nil
      let output = GhRunner.Output(
        exitStatus: exitStatus,
        standardOutput: fields.standardOutput,
        standardError: fields.standardError
      )
      return (continuation, output)
    }
    if let (continuation, output) = finished { continuation.resume(returning: .success(output)) }
  }
}

import Foundation
import os

// Runs gh without blocking a thread while it runs, and stops it after a time limit.
// Both pipes drain while gh runs, so a full pipe cannot stop gh.
enum GhRunner {
  // gh can wait for ever, for example on a keychain prompt that nobody answers.
  static let defaultTimeout: Duration = .seconds(30)

  struct Output: Sendable {
    let exitStatus: Int32
    let standardOutput: Data
    let standardError: Data
  }

  enum Failure: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
  }

  // stderr goes to /dev/null unless readsStandardError is true.
  static func run(
    path: String,
    arguments: [String],
    readsStandardError: Bool,
    timeout: Duration = defaultTimeout
  ) async throws(Failure) -> Output {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
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
        if run.end(with: .timedOut) { process.terminate() }
      }
    }
    timeoutTask?.cancel()
    return try result.get()
  }
}

// Resumes the continuation exactly once: after gh exits and every pipe reaches its end, or at the time limit.
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

  // Returns true when this call ended the run, so only that caller stops the process.
  @discardableResult
  func end(with failure: GhRunner.Failure) -> Bool {
    let continuation = fields.withLock { fields in
      defer { fields.continuation = nil }
      return fields.continuation
    }
    continuation?.resume(returning: .failure(failure))
    return continuation != nil
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

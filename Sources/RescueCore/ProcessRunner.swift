import Foundation
import Darwin

public struct LocalProcessRunner: CommandRunning {
    public init() {}

    private func executable(for tool: ToolKind) throws -> URL {
        if tool == .systemLog { return URL(fileURLWithPath: "/usr/bin/log") }
        // Never search arbitrary PATH entries or invoke a shell / package manager.
        for directory in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let installer = directory + "/ideviceinstaller"
            let devices = directory + "/idevice_id"
            if FileManager.default.isExecutableFile(atPath: installer), FileManager.default.isExecutableFile(atPath: devices) {
                let path = tool == .liveLog ? directory + "/idevicesyslog" : (tool == .installer ? installer : devices)
                guard FileManager.default.isExecutableFile(atPath: path) else { throw RescueError.missingTools }
                return URL(fileURLWithPath: path)
            }
        }
        throw RescueError.missingTools
    }

    public func run(_ command: ToolCommand) async throws -> CommandResult {
        let executableURL = try executable(for: command.tool)
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try Self.execute(command, executableURL: executableURL, cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func execute(_ command: ToolCommand, executableURL: URL, cancellation: ProcessCancellation) throws -> CommandResult {
        if cancellation.isCancelled && !command.expectedStop { throw RescueError.timedOut }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = command.arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        let capture = ProcessCapture(limit: command.maximumOutputBytes)
        do { try process.run() } catch { throw RescueError.launchFailed }
        cancellation.attach(process)

        let readers = DispatchGroup()
        for (handle, isError) in [(output.fileHandleForReading, false), (errorOutput.fileHandleForReading, true)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while let chunk = try? handle.read(upToCount: 16_384), !chunk.isEmpty {
                    capture.append(chunk, isError: isError)
                }
            }
        }
        let termination = DispatchWorkItem {
            if process.isRunning {
                capture.markTimedOut()
                process.terminate()
            }
        }
        let hardStop = DispatchWorkItem {
            if process.isRunning {
                capture.markTimedOut()
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + command.timeout, execute: termination)
        DispatchQueue.global().asyncAfter(deadline: .now() + command.timeout + 2, execute: hardStop)
        process.waitUntilExit()
        termination.cancel()
        hardStop.cancel()
        let drained = readers.wait(timeout: .now() + 2) == .success
        try? output.fileHandleForReading.close()
        try? errorOutput.fileHandleForReading.close()
        let snapshot = capture.snapshot()
        let stopped = snapshot.timedOut || cancellation.isCancelled
        if stopped && !command.expectedStop { throw RescueError.timedOut }
        if snapshot.overflow || !drained { throw RescueError.outputTooLarge }
        return CommandResult(exitCode: process.terminationStatus,
                             stdout: String(decoding: snapshot.stdout, as: UTF8.self),
                             stderr: String(decoding: snapshot.stderr, as: UTF8.self),
                             stoppedAsRequested: command.expectedStop && stopped)
    }
}

private final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func attach(_ process: Process) {
        lock.lock(); self.process = process; let stop = cancelled; lock.unlock()
        if stop { terminate(process) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let child = process; lock.unlock()
        if let child = child { terminate(child) }
    }
    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }
}

private final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var output = Data(), errorOutput = Data()
    private var overflow = false, timedOut = false
    init(limit: Int) { self.limit = limit }
    func append(_ data: Data, isError: Bool) {
        lock.lock(); defer { lock.unlock() }
        let remaining = max(0, limit - output.count - errorOutput.count)
        if data.count > remaining { overflow = true }
        if isError { errorOutput.append(data.prefix(remaining)) }
        else { output.append(data.prefix(remaining)) }
        // Continue draining after the limit; never let a full pipe deadlock a child.
    }
    func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }
    func snapshot() -> (stdout: Data, stderr: Data, overflow: Bool, timedOut: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (output, errorOutput, overflow, timedOut)
    }
}

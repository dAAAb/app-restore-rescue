import Foundation
import Darwin

public struct LocalProcessRunner: CommandRunning {
    public init() {}

    /// Called only when the app is actually quitting. Stopping a client cannot roll back an uninstall already sent.
    public static func shutdownOwnedProcesses() async {
        await OwnedProcessRegistry.shared.shutdown()
    }

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
        let capture = ProcessCapture(limit: command.maximumOutputBytes, readinessMarker: command.readinessMarker, onReady: command.readinessHandler)
        do { try OwnedProcessRegistry.shared.launch(process, cancellation: cancellation) } catch { throw RescueError.launchFailed }
        defer { OwnedProcessRegistry.shared.finished(cancellation) }

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
                             stoppedAsRequested: command.expectedStop && stopped,
                             monitoringStarted: snapshot.ready)
    }
}

final class ProcessCancellation: @unchecked Sendable {
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
    func waitUntilExit() {
        lock.lock(); let child = process; lock.unlock()
        child?.waitUntilExit()
    }
    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        }
    }
}

final class OwnedProcessRegistry: @unchecked Sendable {
    static let shared = OwnedProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: ProcessCancellation] = [:]
    private var shuttingDown = false

    func launch(_ process: Process, cancellation: ProcessCancellation) throws {
        lock.lock(); defer { lock.unlock() }
        guard !shuttingDown, !cancellation.isCancelled else { throw RescueError.launchFailed }
        // Hold the lock across launch so shutdown cannot miss a newly started child.
        try process.run()
        cancellation.attach(process)
        processes[ObjectIdentifier(cancellation)] = cancellation
    }

    func finished(_ cancellation: ProcessCancellation) {
        lock.lock(); processes.removeValue(forKey: ObjectIdentifier(cancellation)); lock.unlock()
    }

    func shutdown() async {
        let children = beginShutdown()
        children.forEach { $0.cancel() }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                children.forEach { $0.waitUntilExit() }
                continuation.resume()
            }
        }
    }

    private func beginShutdown() -> [ProcessCancellation] {
        lock.lock(); defer { lock.unlock() }
        shuttingDown = true
        return Array(processes.values)
    }
}

struct MonitorReadinessDetector {
    private let expected: String
    private var line = Data()
    private var oversizedLine = false
    private(set) var ready = false
    init(marker: String) { expected = marker }
    mutating func append(_ bytes: Data) -> Bool {
        guard !ready else { return false }
        for byte in bytes {
            if byte == 10 {
                if !oversizedLine, String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == expected {
                    ready = true
                    return true
                }
                line.removeAll(keepingCapacity: true)
                oversizedLine = false
            } else if line.count < 4096 { line.append(byte) }
            else { oversizedLine = true }
        }
        return false
    }
}

private final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var output = Data(), errorOutput = Data()
    private var overflow = false, timedOut = false
    private var readiness: MonitorReadinessDetector?
    private let onReady: (@Sendable () -> Void)?
    init(limit: Int, readinessMarker: String?, onReady: (@Sendable () -> Void)?) {
        self.limit = limit
        readiness = readinessMarker.map { MonitorReadinessDetector(marker: $0) }
        self.onReady = onReady
    }
    func append(_ data: Data, isError: Bool) {
        lock.lock()
        let remaining = max(0, limit - output.count - errorOutput.count)
        if data.count > remaining { overflow = true }
        if isError { errorOutput.append(data.prefix(remaining)) }
        else { output.append(data.prefix(remaining)) }
        let becameReady = !isError && (readiness?.append(data) ?? false)
        lock.unlock()
        if becameReady { onReady?() }
        // Continue draining after the limit; never let a full pipe deadlock a child.
    }
    func markTimedOut() { lock.lock(); timedOut = true; lock.unlock() }
    func snapshot() -> (stdout: Data, stderr: Data, overflow: Bool, timedOut: Bool, ready: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (output, errorOutput, overflow, timedOut, readiness?.ready ?? false)
    }
}

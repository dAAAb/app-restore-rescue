import Foundation

public actor RescueService {
    private let runner: any CommandRunning
    private var version: ToolVersion?
    private var inspection: Inspection?
    private var uninstallInProgress = false

    public init(runner: any CommandRunning = LocalProcessRunner()) { self.runner = runner }

    public func checkTools() async throws -> ToolVersion {
        let result = try await runner.run(.version)
        guard result.exitCode == 0 else { throw RescueError.unsupportedVersion }
        let parsed = try ToolVersion(output: result.stdout)
        guard parsed.supported else { throw RescueError.unsupportedVersion }
        version = parsed
        return parsed
    }

    public func devices() async throws -> [DeviceIdentifier] {
        if version == nil { _ = try await checkTools() }
        let result = try await runner.run(.devices)
        guard result.exitCode == 0 else { throw RescueError.serviceUnavailable }
        let lines = result.stdout.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        let identifiers = try lines.map { try DeviceIdentifier($0) }
        return Array(Set(identifiers)).sorted { $0.rawValue < $1.rawValue }
    }

    public func inspect(_ target: RescueTarget) async throws -> Inspection {
        guard !uninstallInProgress else { throw RescueError.inspectionRequired }
        inspection = nil
        guard try await devices().contains(target.device) else { throw RescueError.deviceDisconnected }
        let result = try await runner.run(.inspect(target))
        guard result.exitCode == 0 else { throw RescueError.inspectionFailed }
        let data = Data(result.stdout.utf8)
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              object is [Any] || object is [String: Any] else { throw RescueError.invalidResponse }
        let found = Self.containsBundle(object, expected: target.bundle.rawValue)
        let value = Inspection(target: target, appRecordFound: found)
        inspection = value
        return value
    }

    private static func containsBundle(_ object: Any, expected: String) -> Bool {
        if let dictionary = object as? [String: Any] {
            if dictionary["CFBundleIdentifier"] as? String == expected || dictionary[expected] != nil { return true }
            return dictionary.values.contains { containsBundle($0, expected: expected) }
        }
        if let array = object as? [Any] { return array.contains { containsBundle($0, expected: expected) } }
        return false
    }

    public func uninstall(_ authorization: UninstallAuthorization) async throws {
        guard !uninstallInProgress, inspection?.target == authorization.target else { throw RescueError.inspectionRequired }
        uninstallInProgress = true
        inspection = nil // Consume the inspection: no double submission or automatic retry.
        defer { uninstallInProgress = false }
        guard try await devices().contains(authorization.target.device) else { throw RescueError.deviceDisconnected }
        do {
            let result = try await runner.run(.uninstall(authorization))
            guard result.uninstallCompleted else {
                if result.exitCode == 0 { throw RescueError.uninstallUncertain }
                throw RescueError.uninstallFailed
            }
        } catch let error as RescueError {
            switch error {
            case .timedOut, .outputTooLarge: throw RescueError.uninstallUncertain
            default: throw error
            }
        }
    }

    public func scanLog(at url: URL) async throws -> LogScanResult {
        if url.pathExtension.lowercased() == "logarchive" {
            let command = try ToolCommand.readArchive(url)
            let output = try await runner.run(command)
            guard output.exitCode == 0 else { throw RescueError.archiveReadFailed }
            return RestoreLogScanner.scan(output.stdout)
        }
        guard ["txt", "log", "jsonl", "ndjson", "json"].contains(url.pathExtension.lowercased()) else { throw RescueError.unsupportedLog }
        guard let stream = InputStream(url: url) else { throw RescueError.unreadableLog }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw RescueError.unreadableLog }
            if count == 0 { break }
            guard data.count + count <= 8_388_608 else { throw RescueError.logTooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard let contents = String(data: data, encoding: .utf8) else { throw RescueError.unreadableLog }
        return RestoreLogScanner.scan(contents)
    }

    public func monitor(_ device: DeviceIdentifier, onReady: (@Sendable () -> Void)? = nil) async throws -> LogScanResult {
        guard try await devices().contains(device) else { throw RescueError.deviceDisconnected }
        let output = try await runner.run(.monitor(device, onReady: onReady))
        guard output.monitoringStarted, output.exitCode == 0 || output.stoppedAsRequested else { throw RescueError.serviceUnavailable }
        return RestoreLogScanner.scan(output.stdout)
    }
}

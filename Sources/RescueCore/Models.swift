import Foundation

public enum RescueError: Error, Equatable, Sendable {
    case missingTools, unsupportedVersion, invalidDevice, invalidBundle, systemApp
    case confirmationMismatch, inspectionRequired, deviceDisconnected
    case serviceUnavailable, launchFailed, timedOut, outputTooLarge, invalidResponse
    case inspectionFailed, uninstallFailed, uninstallUncertain
    case unreadableLog, unsupportedLog, logTooLarge, archiveReadFailed
}

public struct DeviceIdentifier: Hashable, Identifiable, Sendable {
    public let rawValue: String
    public var id: String { rawValue }
    public var masked: String { "iPhone · …" + rawValue.suffix(6) }

    public init(_ value: String) throws {
        guard value.range(of: "^(?:[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16}|[A-Fa-f0-9]{40})$", options: .regularExpression) != nil else {
            throw RescueError.invalidDevice
        }
        rawValue = value
    }
}

public struct BundleIdentifier: Hashable, Sendable {
    public let rawValue: String

    public init(_ value: String) throws {
        guard value.utf8.count <= 255,
              value.range(of: "^[A-Za-z][A-Za-z0-9_-]*(?:\\.[A-Za-z0-9][A-Za-z0-9_-]*)+$", options: .regularExpression) != nil else {
            throw RescueError.invalidBundle
        }
        guard value.lowercased() != "com.apple", !value.lowercased().hasPrefix("com.apple.") else {
            throw RescueError.systemApp
        }
        rawValue = value
    }
}

public struct RescueTarget: Hashable, Identifiable, Sendable {
    public let device: DeviceIdentifier
    public let bundle: BundleIdentifier
    public var id: String { device.rawValue + ":" + bundle.rawValue }
    public init(device: DeviceIdentifier, bundle: BundleIdentifier) {
        self.device = device
        self.bundle = bundle
    }
}

public struct UninstallAuthorization: Sendable {
    public let target: RescueTarget
    public init(target: RescueTarget, typedBundleIdentifier: String) throws {
        guard typedBundleIdentifier == target.bundle.rawValue else { throw RescueError.confirmationMismatch }
        self.target = target
    }
}

public struct Inspection: Equatable, Sendable {
    public let target: RescueTarget
    public let appRecordFound: Bool
    public init(target: RescueTarget, appRecordFound: Bool) {
        self.target = target
        self.appRecordFound = appRecordFound
    }
}

public struct ToolVersion: Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public var display: String { "\(major).\(minor).\(patch)" }
    public var supported: Bool { major > 1 || (major == 1 && minor >= 2) }

    public init(output: String) throws {
        let expression = try NSRegularExpression(pattern: #"^ideviceinstaller\s+(\d+)\.(\d+)(?:\.(\d+))?\b"#)
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        guard let match = expression.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)),
              let major = Int(text.substring(with: match.range(at: 1))),
              let minor = Int(text.substring(with: match.range(at: 2))) else { throw RescueError.unsupportedVersion }
        self.major = major
        self.minor = minor
        self.patch = match.range(at: 3).location == NSNotFound ? 0 : (Int(text.substring(with: match.range(at: 3))) ?? 0)
    }
}

public enum ToolKind: Equatable, Sendable { case installer, deviceList, systemLog, liveLog }

public struct ToolCommand: Sendable {
    public let tool: ToolKind
    public let arguments: [String]
    public let timeout: TimeInterval
    public let maximumOutputBytes: Int
    public let expectedStop: Bool
    private init(_ tool: ToolKind, _ arguments: [String], timeout: TimeInterval = 30, maximumOutputBytes: Int = 262_144, expectedStop: Bool = false) {
        self.tool = tool
        self.arguments = arguments
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
        self.expectedStop = expectedStop
    }
    public static var version: ToolCommand { ToolCommand(.installer, ["--version"], timeout: 10) }
    public static var devices: ToolCommand { ToolCommand(.deviceList, ["-l"], timeout: 15) }
    public static func inspect(_ target: RescueTarget) -> ToolCommand {
        ToolCommand(.installer, ["-u", target.device.rawValue, "list", "-b", target.bundle.rawValue, "--xml"])
    }
    public static func uninstall(_ authorization: UninstallAuthorization) -> ToolCommand {
        ToolCommand(.installer, ["-u", authorization.target.device.rawValue, "uninstall", authorization.target.bundle.rawValue], timeout: 90)
    }
    public static func readArchive(_ url: URL) throws -> ToolCommand {
        guard url.isFileURL, url.pathExtension.lowercased() == "logarchive" else { throw RescueError.unsupportedLog }
        return ToolCommand(.systemLog, ["show", "--archive", url.path, "--style", "ndjson", "--info", "--debug", "--predicate", "process == 'appstored' AND (eventMessage CONTAINS 'PurchaseService' OR eventMessage CONTAINS 'Duplicate restoring request')"], timeout: 60, maximumOutputBytes: 8_388_608)
    }
    public static func monitor(_ device: DeviceIdentifier) -> ToolCommand {
        ToolCommand(.liveLog, ["-u", device.rawValue, "-x", "--no-colors", "-p", "appstored"], timeout: 60, maximumOutputBytes: 16_777_216, expectedStop: true)
    }
}

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let stoppedAsRequested: Bool
    public init(exitCode: Int32, stdout: String, stderr: String = "", stoppedAsRequested: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.stoppedAsRequested = stoppedAsRequested
    }
    public var uninstallCompleted: Bool {
        exitCode == 0 && stdout.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespaces) == "Uninstall: Complete"
        }
    }
}

public protocol CommandRunning: Sendable {
    func run(_ command: ToolCommand) async throws -> CommandResult
}

/// Public reports are deliberately assembled from known categories; raw process output is never rendered.
public enum SafeReport {
    public static func summary(version: ToolVersion?, candidateCount: Int, completed: Bool) -> String {
        "App Restore Rescue\nTool version: \(version?.display ?? "unavailable")\nMatched candidates: \(max(0, candidateCount))\nUninstall completed: \(completed ? "yes" : "no")\nNo device identifiers, account information, paths, or raw logs included."
    }
}

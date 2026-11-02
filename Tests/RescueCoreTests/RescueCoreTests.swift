import Foundation
import XCTest
@testable import RescueCore

final class RescueCoreTests: XCTestCase {
    private let deviceA = try! DeviceIdentifier("00000000-0000000000000000")
    private let deviceB = try! DeviceIdentifier("11111111-1111111111111111")
    private let bundle = try! BundleIdentifier("com.example.reader")
    private var target: RescueTarget { RescueTarget(device: deviceA, bundle: bundle) }
    private let emptyPlist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>"

    func testBundleValidationRejectsSystemAppsOptionsWildcardsAndInjection() throws {
        XCTAssertEqual(try BundleIdentifier("com.atebits.Tweetie2").rawValue, "com.atebits.Tweetie2")
        for value in ["*", "com.example.*", "--all", "com.example;whoami", "com.example\nreader", "com..reader", "com.apple", "com.apple.AppStore", "COM.APPLE.mobilemail", "com.example reader"] {
            XCTAssertThrowsError(try BundleIdentifier(value), value)
        }
    }

    func testDeviceValidationRejectsOptionsAndNetworkIdentifiers() throws {
        XCTAssertEqual(deviceA.masked, "iPhone · …000000")
        XCTAssertNoThrow(try DeviceIdentifier(String(repeating: "a", count: 40)))
        for value in ["", "--network", "00000000-0000000000000000 --all", "00000000-0000000000000000\n", "host.local"] {
            XCTAssertThrowsError(try DeviceIdentifier(value))
        }
    }

    func testCommandsTargetExactlyOneUSBDeviceAndBundle() throws {
        let authorization = try UninstallAuthorization(target: target, typedBundleIdentifier: bundle.rawValue)
        XCTAssertEqual(ToolCommand.uninstall(authorization).arguments, ["-u", deviceA.rawValue, "uninstall", bundle.rawValue])
        XCTAssertEqual(ToolCommand.inspect(target).arguments, ["-u", deviceA.rawValue, "list", "-b", bundle.rawValue, "--xml"])
        XCTAssertEqual(ToolCommand.monitor(deviceA).arguments, ["-u", deviceA.rawValue, "-x", "--no-colors", "-p", "appstored"])
        XCTAssertTrue(ToolCommand.monitor(deviceA).expectedStop)
        XCTAssertFalse(ToolCommand.uninstall(authorization).expectedStop)
        XCTAssertFalse(ToolCommand.uninstall(authorization).arguments.contains("-n"))
    }

    func testConfirmationMustBeExact() throws {
        for value in ["", "yes", "com.example.writer", "com.example.reader ", "COM.EXAMPLE.READER"] {
            XCTAssertThrowsError(try UninstallAuthorization(target: target, typedBundleIdentifier: value))
        }
    }

    func testVersionAndSuccessMarkerAreStrict() throws {
        XCTAssertFalse(try ToolVersion(output: "ideviceinstaller 1.1.1").supported)
        XCTAssertTrue(try ToolVersion(output: "ideviceinstaller 1.2.0\n").supported)
        XCTAssertThrowsError(try ToolVersion(output: "unexpected output 1.2.0"))
        XCTAssertTrue(CommandResult(exitCode: 0, stdout: "\rUninstall: RemovingApplication (50%)\n\rUninstall: Complete\n").uninstallCompleted)
        XCTAssertFalse(CommandResult(exitCode: 1, stdout: "Uninstall: Complete").uninstallCompleted)
        XCTAssertFalse(CommandResult(exitCode: 0, stdout: "Not Uninstall: Complete").uninstallCompleted)
        XCTAssertFalse(CommandResult(exitCode: 0, stdout: "Uninstall: Complete (maybe)").uninstallCompleted)
    }

    func testMissingAppRecordCanStillReceiveExplicitTargetedRequest() async throws {
        let runner = MockRunner([
            .result(CommandResult(exitCode: 0, stdout: "ideviceinstaller 1.2.0")),
            .result(CommandResult(exitCode: 0, stdout: deviceA.rawValue + "\n")),
            .result(CommandResult(exitCode: 0, stdout: emptyPlist)),
            .result(CommandResult(exitCode: 0, stdout: deviceA.rawValue + "\n")),
            .result(CommandResult(exitCode: 0, stdout: "Uninstall: Complete\n"))
        ])
        let service = RescueService(runner: runner)
        let inspected = try await service.inspect(target)
        XCTAssertFalse(inspected.appRecordFound)
        try await service.uninstall(UninstallAuthorization(target: target, typedBundleIdentifier: bundle.rawValue))
        let commands = await runner.commands
        XCTAssertEqual(commands.count, 5)
        XCTAssertEqual(commands.last?.arguments, ["-u", deviceA.rawValue, "uninstall", bundle.rawValue])
        XCTAssertEqual(commands.filter { $0.arguments.contains("uninstall") }.count, 1)
    }

    func testDeviceDisconnectNeverFallsBackToAnotherPhone() async throws {
        let runner = MockRunner([
            .result(CommandResult(exitCode: 0, stdout: "ideviceinstaller 1.2.0")),
            .result(CommandResult(exitCode: 0, stdout: deviceA.rawValue)),
            .result(CommandResult(exitCode: 0, stdout: emptyPlist)),
            .result(CommandResult(exitCode: 0, stdout: deviceB.rawValue))
        ])
        let service = RescueService(runner: runner)
        _ = try await service.inspect(target)
        do {
            try await service.uninstall(UninstallAuthorization(target: target, typedBundleIdentifier: bundle.rawValue))
            XCTFail("A disconnected device must not be substituted.")
        } catch { XCTAssertEqual(error as? RescueError, .deviceDisconnected) }
        let commands = await runner.commands
        XCTAssertFalse(commands.contains { $0.arguments.contains("uninstall") })
    }

    func testConfirmationForDifferentTargetCannotUseOldInspection() async throws {
        let runner = MockRunner([
            .result(CommandResult(exitCode: 0, stdout: "ideviceinstaller 1.2.0")),
            .result(CommandResult(exitCode: 0, stdout: deviceA.rawValue)),
            .result(CommandResult(exitCode: 0, stdout: emptyPlist))
        ])
        let service = RescueService(runner: runner)
        _ = try await service.inspect(target)
        let other = RescueTarget(device: deviceB, bundle: bundle)
        do {
            try await service.uninstall(UninstallAuthorization(target: other, typedBundleIdentifier: bundle.rawValue))
            XCTFail("Authorization must match the inspection.")
        } catch { XCTAssertEqual(error as? RescueError, .inspectionRequired) }
        let commands = await runner.commands
        XCTAssertEqual(commands.count, 3)
    }

    func testUninstallTimeoutIsUnknownAndNeverRetried() async throws {
        let runner = MockRunner([
            .result(CommandResult(exitCode: 0, stdout: "ideviceinstaller 1.2.0")),
            .result(CommandResult(exitCode: 0, stdout: deviceA.rawValue)),
            .result(CommandResult(exitCode: 0, stdout: emptyPlist)),
            .result(CommandResult(exitCode: 0, stdout: deviceA.rawValue)),
            .failure(.timedOut)
        ])
        let service = RescueService(runner: runner)
        _ = try await service.inspect(target)
        let authorization = try UninstallAuthorization(target: target, typedBundleIdentifier: bundle.rawValue)
        do { try await service.uninstall(authorization); XCTFail() }
        catch { XCTAssertEqual(error as? RescueError, .uninstallUncertain) }
        do { try await service.uninstall(authorization); XCTFail() }
        catch { XCTAssertEqual(error as? RescueError, .inspectionRequired) }
        let commands = await runner.commands
        XCTAssertEqual(commands.filter { $0.arguments.contains("uninstall") }.count, 1)
    }

    func testUninstallRequiresInspection() async throws {
        let runner = MockRunner([])
        let service = RescueService(runner: runner)
        do {
            try await service.uninstall(UninstallAuthorization(target: target, typedBundleIdentifier: bundle.rawValue))
            XCTFail()
        } catch { XCTAssertEqual(error as? RescueError, .inspectionRequired) }
        let commands = await runner.commands
        XCTAssertTrue(commands.isEmpty)
    }

    func testArchiveReaderDoesNotCollectOrWriteLogs() throws {
        let command = try ToolCommand.readArchive(URL(fileURLWithPath: "/tmp/example.logarchive"))
        XCTAssertEqual(command.tool, .systemLog)
        XCTAssertEqual(command.arguments.first, "show")
        XCTAssertFalse(command.arguments.contains("collect"))
        XCTAssertFalse(command.arguments.contains("--output"))
        XCTAssertFalse(command.arguments.contains("sudo"))
        XCTAssertThrowsError(try ToolCommand.readArchive(URL(string: "https://example.com/example.logarchive")!))
    }

    func testPublicSummaryHasNoInputForRawIdentifiersOrLogs() throws {
        let summary = SafeReport.summary(version: try ToolVersion(output: "ideviceinstaller 1.2.0"), candidateCount: 2, completed: false)
        XCTAssertFalse(summary.contains(deviceA.rawValue))
        XCTAssertFalse(summary.contains(bundle.rawValue))
        XCTAssertFalse(summary.contains("/Users/"))
        XCTAssertTrue(summary.contains("Matched candidates: 2"))
    }
}

private actor MockRunner: CommandRunning {
    enum Step: Sendable { case result(CommandResult), failure(RescueError) }
    private var steps: [Step]
    private(set) var commands: [ToolCommand] = []
    init(_ steps: [Step]) { self.steps = steps }
    func run(_ command: ToolCommand) async throws -> CommandResult {
        commands.append(command)
        guard !steps.isEmpty else { throw RescueError.invalidResponse }
        switch steps.removeFirst() {
        case .result(let result): return result
        case .failure(let error): throw error
        }
    }
}

import AppKit
import SwiftUI
import RescueCore

@main
struct AppRestoreRescueApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    var body: some Scene {
        Window("App Restore Rescue", id: "main") { RescueView() }
            .defaultSize(width: 820, height: 880)
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    static var allowTermination: (() -> Bool)?
    private var terminationPending = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        guard Self.allowTermination?() ?? true else { return .terminateCancel }
        terminationPending = true
        Task {
            await LocalProcessRunner.shutdownOwnedProcesses()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
final class RescueModel: ObservableObject {
    let isDemo: Bool
    let language: AppLanguage
    @Published var devices: [DeviceIdentifier] = []
    @Published var selectedDevice: DeviceIdentifier?
    @Published var bundleText = "com.atebits.Tweetie2"
    @Published var version: ToolVersion?
    @Published var inspection: Inspection?
    @Published var confirmation: RescueTarget?
    @Published var scan: LogScanResult?
    @Published var busy = false
    @Published var monitoring = false
    @Published var completed = false
    @Published var status: Status = .idle
    private let service = RescueService()
    private var monitoringTask: Task<Void, Never>?
    private var monitorGeneration = 0

    init(isDemo: Bool = CommandLine.arguments.contains("--demo")) {
        self.isDemo = isDemo
        language = AppLanguage.forApplication(preferredLocalizations: Bundle.main.preferredLocalizations,
                                              arguments: isDemo ? CommandLine.arguments : [])
        ApplicationDelegate.allowTermination = { [weak self] in self?.confirmTermination() ?? true }
        if isDemo {
            let device = try! DeviceIdentifier("00000000-0000000000000000")
            devices = [device]
            selectedDevice = device
            version = try? ToolVersion(output: "ideviceinstaller 1.2.0")
            scan = RestoreLogScanner.scan("2026-01-01 12:00:00.000000+0000 appstored[100:aa] [BUYA1B2C3D4/com.example.reader:123456789] Error Domain=ASDErrorDomain Code=506 \"Duplicate restoring request\"")
            status = .ready
        }
    }

    enum Status {
        case idle, ready, checking, inspecting, inspected(Bool), connectingMonitor, monitoring, scanning, scanned, uninstalling, completed
        case failed(RescueError)
    }

    func text(_ message: AppMessage) -> String { language.text(message) }
    var target: RescueTarget? {
        guard let device = selectedDevice, let bundle = try? BundleIdentifier(bundleText) else { return nil }
        return RescueTarget(device: device, bundle: bundle)
    }
    var canUninstall: Bool { !isDemo && !busy && inspection != nil && inspection?.target == target }
    var uninstallInProgress: Bool { if case .uninstalling = status { return true }; return false }

    private func confirmTermination() -> Bool {
        guard uninstallInProgress else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text(.uninstallStillRunning)
        alert.informativeText = text(.quitDuringUninstall)
        alert.addButton(withTitle: text(.waitForCompletion))
        alert.addButton(withTitle: text(.quitAnyway))
        return alert.runModal() == .alertSecondButtonReturn
    }

    func invalidateInspection() { inspection = nil; completed = false }

    func refresh() {
        guard !isDemo else { status = .ready; return }
        busy = true; status = .checking; invalidateInspection(); selectedDevice = nil; devices = []
        Task {
            defer { busy = false }
            do {
                version = try await service.checkTools()
                devices = try await service.devices()
                status = .ready
            } catch { fail(error) }
        }
    }

    func inspectTarget() {
        guard let target = target, !busy else { return }
        guard !isDemo else { inspection = Inspection(target: target, appRecordFound: false); status = .inspected(false); return }
        busy = true; status = .inspecting; invalidateInspection()
        Task {
            defer { busy = false }
            do {
                let value = try await service.inspect(target)
                inspection = value
                status = .inspected(value.appRecordFound)
            } catch { fail(error) }
        }
    }

    func startMonitoring() {
        guard !isDemo else { status = .scanned; return }
        guard let device = selectedDevice, !busy else { return }
        busy = true; monitoring = true; status = .connectingMonitor; scan = nil
        monitorGeneration += 1
        let generation = monitorGeneration
        monitoringTask = Task {
            defer { busy = false; monitoring = false; monitoringTask = nil }
            do {
                scan = try await service.monitor(device, onReady: { [weak self] in
                    Task { @MainActor in
                        guard let self = self, self.monitoring, self.monitorGeneration == generation else { return }
                        self.status = .monitoring
                    }
                })
                status = .scanned
            }
            catch { fail(error) }
        }
    }

    func stopMonitoring() { monitoringTask?.cancel() }

    func importLog() {
        guard !isDemo else { status = .scanned; return }
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = text(.chooseLocalLog)
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["logarchive", "txt", "log", "jsonl", "ndjson", "json"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = .scanning; scan = nil
        Task {
            defer { busy = false }
            do { scan = try await service.scanLog(at: url); status = .scanned }
            catch { fail(error) }
        }
    }

    func requestUninstall() {
        guard canUninstall, let target = inspection?.target else { return }
        confirmation = target
    }

    func confirmUninstall(target: RescueTarget, typedText: String) {
        guard !isDemo, !busy, canUninstall, target == inspection?.target else { return }
        do {
            let authorization = try UninstallAuthorization(target: target, typedBundleIdentifier: typedText)
            confirmation = nil
            busy = true; status = .uninstalling; inspection = nil; completed = false
            Task {
                defer { busy = false }
                do { try await service.uninstall(authorization); completed = true; status = .completed }
                catch { fail(error) }
            }
        } catch { fail(error) }
    }

    func useCandidate(_ candidate: RestoreCandidate) {
        guard !busy else { return }
        bundleText = candidate.bundle.rawValue
        invalidateInspection()
    }

    private func fail(_ error: Error) { status = .failed((error as? RescueError) ?? .invalidResponse) }

    var statusText: String {
        switch status {
        case .idle: return text(.idle)
        case .checking: return text(.checkingTools)
        case .ready: return devices.isEmpty ? text(.noDevice) : text(.chooseDevice)
        case .inspecting: return text(.inspecting)
        case .inspected(let found): return found ? text(.appRecordFound) : text(.appRecordMissing)
        case .connectingMonitor: return text(.connectingMonitor)
        case .monitoring: return text(.listening)
        case .scanning: return text(.scanning)
        case .scanned: return text(.scanned)
        case .uninstalling: return text(.uninstalling)
        case .completed: return text(.uninstallCompleted)
        case .failed(let error): return errorText(error)
        }
    }

    var monitoringStatusText: String? {
        switch status {
        case .connectingMonitor, .monitoring: return statusText
        default: return nil
        }
    }

    private func errorText(_ error: RescueError) -> String {
        switch error {
        case .missingTools: return text(.missingTools)
        case .unsupportedVersion: return text(.unsupportedVersion)
        case .invalidDevice: return text(.invalidDevice)
        case .invalidBundle, .systemApp: return text(.invalidBundle)
        case .confirmationMismatch: return text(.confirmationMismatch)
        case .inspectionRequired: return text(.inspectionRequired)
        case .deviceDisconnected: return text(.deviceDisconnected)
        case .serviceUnavailable: return text(.serviceUnavailable)
        case .launchFailed: return text(.launchFailed)
        case .timedOut: return text(.readTimedOut)
        case .outputTooLarge, .logTooLarge: return text(.outputTooLarge)
        case .invalidResponse, .inspectionFailed: return text(.inspectionFailed)
        case .uninstallFailed: return text(.uninstallFailed)
        case .uninstallUncertain: return text(.uninstallUncertain)
        case .unreadableLog: return text(.unreadableLog)
        case .unsupportedLog: return text(.unsupportedLog)
        case .archiveReadFailed: return text(.archiveReadFailed)
        }
    }
}

struct RescueView: View {
    @StateObject private var model = RescueModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "arrow.down.app.fill").font(.system(size: 42)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("App Restore Rescue").font(.largeTitle.bold())
                        Text(model.text(.subtitle))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(model.language.displayName, systemImage: "globe")
                        .font(.caption).foregroundStyle(.secondary)
                        .help(model.text(.systemLanguageHelp))
                }
                Label(model.text(.localPrivacy), systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
                if model.isDemo {
                    Label(model.text(.demoNotice), systemImage: "testtube.2")
                        .font(.callout.bold()).foregroundStyle(.orange)
                }

                card {
                    sectionTitle("1", model.text(.connectTitle))
                    Text(model.text(.connectHelp))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(model.text(.checkTools), action: model.refresh).disabled(model.busy)
                        if let version = model.version { Text("ideviceinstaller \(version.display)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    Picker(model.text(.phoneLabel), selection: $model.selectedDevice) {
                        Text(model.text(.selectDevice)).tag(Optional<DeviceIdentifier>.none)
                        ForEach(model.devices) { device in Text(device.masked).tag(Optional(device)) }
                    }.disabled(model.busy || model.devices.isEmpty)
                    Text("brew install ideviceinstaller").font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.text(.manualSetupHelp))
                        .font(.caption).foregroundStyle(.secondary)
                }

                card {
                    sectionTitle("2", model.text(.findErrorsTitle))
                    Text(model.text(.monitorHelp))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        if model.monitoring {
                            Button(model.text(.stopMonitoring), action: model.stopMonitoring)
                        } else {
                            Button(model.text(.monitorFor60Seconds), action: model.startMonitoring).disabled(model.busy || model.selectedDevice == nil)
                        }
                        Button(model.text(.importLocalLog), action: model.importLog).disabled(model.busy)
                    }
                    if let message = model.monitoringStatusText {
                        HStack(alignment: .top, spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(message).font(.callout).textSelection(.enabled)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let scan = model.scan {
                        Text(model.language.scanSummary(matched: scan.matchingFailureCount, unattributed: scan.ambiguousFailureCount))
                            .font(.caption).foregroundStyle(.secondary)
                        if scan.candidates.isEmpty {
                            Text(model.text(.noCandidate))
                                .font(.callout)
                        }
                        ForEach(scan.candidates) { candidate in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.bundle.rawValue).font(.callout.monospaced()).textSelection(.enabled)
                                    Text(model.language.matchingRequests(candidate.failureCount)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(model.text(.useCandidate)) { model.useCandidate(candidate) }.disabled(model.busy)
                            }.padding(.vertical, 4)
                        }
                    }
                    Text(model.text(.scanScope))
                        .font(.caption).foregroundStyle(.secondary)
                }

                card {
                    sectionTitle("3", model.text(.inspectTitle))
                    TextField(model.text(.bundleLabel), text: $model.bundleText)
                        .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder).disabled(model.busy)
                    Text(model.text(.bundleHelp))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.text(.checkSelectedApp), action: model.inspectTarget)
                            .disabled(model.busy || model.target == nil)
                        Spacer()
                        Button(role: .destructive, action: model.requestUninstall) {
                            Text(model.text(.uninstallSelectedApp))
                        }.disabled(!model.canUninstall)
                    }
                    Label(model.text(.dataLossWarning), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }

                HStack(alignment: .top, spacing: 12) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.completed ? "checkmark.circle.fill" : "info.circle").foregroundStyle(model.completed ? .green : .secondary) }
                    Text(model.statusText).font(.callout).textSelection(.enabled)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Text(model.text(.privacyFooter))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
        .frame(minWidth: 720, minHeight: 680)
        .onChange(of: model.selectedDevice) { _ in model.invalidateInspection() }
        .onChange(of: model.bundleText) { _ in model.invalidateInspection() }
        .background(WindowCloseGuard(blocked: model.uninstallInProgress))
        .onDisappear { if model.monitoring { model.stopMonitoring() } }
        .sheet(item: $model.confirmation) { target in
            UninstallSheet(model: model, target: target)
        }
    }

    private func sectionTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.caption.bold()).frame(width: 24, height: 24)
                .background(Color.teal.opacity(0.14), in: Circle()).foregroundStyle(.teal)
            Text(title).font(.headline)
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.12)))
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    let blocked: Bool
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ view: GuardView, context: Context) { view.blocked = blocked; view.updateButton() }
    final class GuardView: NSView {
        var blocked = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateButton() }
        func updateButton() { window?.standardWindowButton(.closeButton)?.isEnabled = !blocked }
    }
}

struct UninstallSheet: View {
    @ObservedObject var model: RescueModel
    let target: RescueTarget
    @State private var typedText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.text(.confirmUninstallTitle), systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text(target.device.masked).font(.headline)
            Text(target.bundle.rawValue).font(.body.monospaced()).textSelection(.enabled)
            Text(model.text(.confirmUninstallHelp))
            Text(model.text(.typeBundlePrompt)).font(.callout)
            TextField(target.bundle.rawValue, text: $typedText).textFieldStyle(.roundedBorder).font(.body.monospaced())
            HStack {
                Button(model.text(.cancel)) { model.confirmation = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) { model.confirmUninstall(target: target, typedText: typedText) } label: {
                    Text(model.text(.uninstallThisApp))
                }.disabled(typedText != target.bundle.rawValue)
            }
        }.padding(28).frame(width: 560)
    }
}

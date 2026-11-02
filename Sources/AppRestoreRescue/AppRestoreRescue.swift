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

enum Language: String, CaseIterable, Identifiable {
    case english, traditionalChinese
    var id: String { rawValue }
    var label: String { self == .english ? "English" : "繁體中文" }
}

@MainActor
final class RescueModel: ObservableObject {
    let isDemo: Bool
    @Published var language: Language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .traditionalChinese : .english
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
        ApplicationDelegate.allowTermination = { [weak self] in self?.confirmTermination() ?? true }
        if isDemo {
            let device = try! DeviceIdentifier("00000000-0000000000000000")
            devices = [device]
            selectedDevice = device
            version = try? ToolVersion(output: "ideviceinstaller 1.2.0")
            scan = RestoreLogScanner.scan("2026-01-01 12:00:00.000000+0000 appstored[100:aa] [BUYA1B2C3D4/com.example.reader:123456789] Error Domain=ASDErrorDomain Code=506 \"Duplicate restoring request\"")
            status = .ready
            if CommandLine.arguments.contains("--english") { language = .english }
        }
    }

    enum Status {
        case idle, ready, checking, inspecting, inspected(Bool), connectingMonitor, monitoring, scanning, scanned, uninstalling, completed
        case failed(RescueError)
    }

    func text(_ english: String, _ chinese: String) -> String { language == .english ? english : chinese }
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
        alert.messageText = text("An uninstall request is still running", "卸載請求仍在執行")
        alert.informativeText = text("Quitting stops this tool's child process, but cannot undo a request already sent to the phone. The outcome may be unknown. Wait for completion unless you intend to stop observing it.", "離開會停止本工具的子程序，但無法撤回已送達手機的請求，結果可能不確定。建議等待完成後再離開。")
        alert.addButton(withTitle: text("Wait for completion", "等待完成"))
        alert.addButton(withTitle: text("Quit anyway", "仍要離開"))
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
        panel.title = text("Choose a local diagnostic log", "選擇本機診斷日誌")
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
        case .idle: return text("Nothing has been changed. Start by checking the existing tools and USB connection.", "尚未變更任何內容。先檢查既有工具與 USB 連線。")
        case .checking: return text("Checking existing tools and USB devices…", "正在檢查既有工具與 USB 裝置…")
        case .ready: return devices.isEmpty ? text("No USB iPhone found. Unlock your phone, check the cable, then refresh. A restricted execution environment can also block the USB service.", "未找到 USB iPhone。請解鎖手機、確認傳輸線後重新檢查。受限制的執行環境也可能阻擋 USB 服務。") : text("Choose the intended iPhone. No device is selected automatically.", "請選擇要處理的 iPhone。工具不會自動選擇裝置。")
        case .inspecting: return text("Checking only the selected app…", "只檢查選定的 App…")
        case .inspected(let found): return found ? text("An app record exists. That alone does not prove a stuck restore. Uninstalling can delete its local data.", "找到 App 紀錄，但這本身不能證明回復卡住。卸載可能刪除其本機資料。") : text("No app record was returned. A targeted uninstall request can still be submitted, but may be rejected or fail to clear the restore.", "沒有查到 App 紀錄。仍可提出指定卸載請求，但系統可能拒絕，或無法解除回復狀態。")
        case .connectingMonitor: return text("Connecting to the selected phone’s log service. WAIT for the “Listening” message before pressing the cloud button.", "正在連接選定手機的日誌服務。請等待顯示「已開始監看」，再按雲朵下載按鈕。")
        case .monitoring: return text("Listening — the phone’s log service is connected. Tap the affected app’s cloud button ONCE in App Store. Wait for the cloud to return, then stop. This manual retry may install the app if it succeeds. Monitoring stops automatically within 60 seconds of launch.", "已開始監看 — 手機日誌服務已連線。請在 App Store 按一次該 App 的雲朵，等雲朵再次出現後停止監看。手動重試若成功，可能開始安裝 App。監看會在啟動後 60 秒內自動停止。")
        case .scanning: return text("Reading the selected log locally. Nothing is uploaded…", "正在本機讀取選定日誌，不會上傳…")
        case .scanned: return text("Scan finished. Results are candidates, not proof that a current restore is stuck. No matches does not mean the phone is healthy or the problem is gone.", "掃描完成。結果是候選項目，不能證明目前仍卡住；沒有匹配也不代表手機正常或問題已解除。")
        case .uninstalling: return text("Submitting one uninstall request for the confirmed device and app. Do not disconnect the phone…", "正在對確認的裝置與 App 提出一筆卸載請求。請勿拔除手機…")
        case .completed: return text("The uninstall request completed. Now manually download the app in App Store to check whether the problem is resolved. No app was installed by this tool.", "卸載請求已完成。請自行回到 App Store 下載，確認問題是否解除。此工具沒有安裝任何 App。")
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
        case .missingTools: return text("Required tools were not found. Install ideviceinstaller yourself with Homebrew; the app never installs dependencies. Live monitoring also needs idevicesyslog from libimobiledevice.", "找不到必要工具。請自行用 Homebrew 安裝 ideviceinstaller；本工具不會安裝相依元件。即時監看另需 libimobiledevice 提供的 idevicesyslog。")
        case .unsupportedVersion: return text("ideviceinstaller 1.2.0 or later is required. No software was installed or updated.", "需要 ideviceinstaller 1.2.0 以上版本。尚未安裝或更新任何軟體。")
        case .invalidDevice: return text("Unexpected device identifier. The operation was stopped.", "裝置識別碼格式不符，已停止操作。")
        case .invalidBundle, .systemApp: return text("Enter one valid third-party bundle identifier. Wildcards, Apple system apps, and shell options are not accepted.", "請輸入單一有效的第三方 App 識別碼。不接受萬用字元、Apple 系統 App 或命令選項。")
        case .confirmationMismatch: return text("The confirmation must exactly match the bundle identifier.", "確認文字必須與 App 識別碼完全相同。")
        case .inspectionRequired: return text("Check this exact device and app again before requesting uninstall.", "提出卸載前，請重新檢查這個裝置與 App。")
        case .deviceDisconnected: return text("The selected USB device is no longer available. No other device will be substituted.", "選定的 USB 裝置已無法使用。工具不會改選其他裝置。")
        case .serviceUnavailable: return text("The USB device service could not be reached, or the log connection ended with an error. Check the cable, unlock/trust status, and execution restrictions. No repair was attempted.", "無法存取 USB 裝置服務，或日誌連線出錯。請檢查傳輸線、解鎖／信任狀態與執行限制。尚未嘗試修復。")
        case .launchFailed: return text("An existing command-line tool could not start. No installer will be launched.", "既有命令列工具無法啟動。不會啟動任何安裝程式。")
        case .timedOut: return text("The read operation timed out. Try a smaller log or check the connection.", "讀取逾時。請縮小日誌範圍或檢查連線。")
        case .outputTooLarge, .logTooLarge: return text("The diagnostic output exceeded the memory limit. Export a shorter time range and try again. No partial result is treated as a clean scan.", "診斷資料超過記憶體上限。請匯出較短時段後重試；不會把不完整結果視為正常。")
        case .invalidResponse, .inspectionFailed: return text("The selected app could not be checked reliably. Uninstall remains unavailable until a new check succeeds.", "無法可靠檢查選定 App。必須重新檢查成功後，才可提出卸載。")
        case .uninstallFailed: return text("The phone reported that uninstall failed. The result was not retried, and no other app was targeted.", "手機回報卸載失敗。工具沒有重試，也沒有指定其他 App。")
        case .uninstallUncertain: return text("The uninstall outcome is UNKNOWN. The request may already have reached the phone. Check the phone and App Store before doing anything else; do not blindly retry.", "卸載結果不確定。請求可能已送達手機。請先查看手機與 App Store 狀態，不要直接重試。")
        case .unreadableLog: return text("The selected log could not be read as UTF-8 text.", "無法以 UTF-8 文字讀取選定日誌。")
        case .unsupportedLog: return text("Choose a .logarchive, .log, .txt, .jsonl, .ndjson, or .json log file.", "請選擇 .logarchive、.log、.txt、.jsonl、.ndjson 或 .json 日誌。")
        case .archiveReadFailed: return text("macOS could not read this archive. The app will not request sudo or collect another archive automatically.", "macOS 無法讀取這份日誌封存。工具不會要求 sudo，也不會自動收集另一份日誌。")
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
                        Text(model.text("A careful way out of a stuck iPhone app restore.", "協助處理卡住的 iPhone App 回復。"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Language", selection: $model.language) {
                        ForEach(Language.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 126)
                }
                Label(model.text("Local only · No telemetry · No automatic installs", "本機處理 · 無遙測 · 不自動安裝"), systemImage: "lock.shield")
                    .font(.callout).foregroundStyle(.secondary)
                if model.isDemo {
                    Label(model.text("DEMO — Synthetic data. All device actions are disabled.", "示範模式 — 全部為合成資料，停用所有裝置操作。"), systemImage: "testtube.2")
                        .font(.callout.bold()).foregroundStyle(.orange)
                }

                card {
                    sectionTitle("1", model.text("Connect and choose your iPhone", "連接並選擇 iPhone"))
                    Text(model.text("Use USB, unlock the phone, and trust this Mac yourself if prompted. Device IDs are shown only in masked form and are not saved.", "透過 USB 連接並解鎖手機；若出現提示，請自行確認信任這台 Mac。裝置識別碼僅顯示遮罩，不會儲存。"))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(model.text("Check tools & USB", "檢查工具與 USB"), action: model.refresh).disabled(model.busy)
                        if let version = model.version { Text("ideviceinstaller \(version.display)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    Picker(model.text("iPhone", "iPhone"), selection: $model.selectedDevice) {
                        Text(model.text("Select a device…", "請選擇裝置…")).tag(Optional<DeviceIdentifier>.none)
                        ForEach(model.devices) { device in Text(device.masked).tag(Optional(device)) }
                    }.disabled(model.busy || model.devices.isEmpty)
                    Text("brew install ideviceinstaller").font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.text("If tools are missing, this is a manual setup command for you to review. This app never runs Homebrew, sudo, Xcode setup, or a software installer.", "若缺少工具，以上是供你自行檢視的安裝指令。本工具不會執行 Homebrew、sudo、Xcode 設定或軟體安裝程式。"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                card {
                    sectionTitle("2", model.text("Find matching restore errors", "找出符合條件的回復錯誤"))
                    Text(model.text("Start monitoring, wait for “Listening,” then try the affected app’s cloud button once. Logs stay in memory; only matching app IDs and counts are shown. You can also import an existing local log.", "先開始監看，等顯示「已開始監看」，再按一次問題 App 的雲朵。日誌只留在記憶體，畫面僅顯示匹配的 App 識別碼與次數。也可以匯入既有的本機日誌。"))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        if model.monitoring {
                            Button(model.text("Stop monitoring", "停止監看"), action: model.stopMonitoring)
                        } else {
                            Button(model.text("Monitor for 60 seconds", "監看 60 秒"), action: model.startMonitoring).disabled(model.busy || model.selectedDevice == nil)
                        }
                        Button(model.text("Import local log…", "匯入本機日誌…"), action: model.importLog).disabled(model.busy)
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
                        Text(model.text("Matched failures: \(scan.matchingFailureCount) · Unattributed: \(scan.ambiguousFailureCount)", "匹配錯誤：\(scan.matchingFailureCount) · 無法歸屬：\(scan.ambiguousFailureCount)"))
                            .font(.caption).foregroundStyle(.secondary)
                        if scan.candidates.isEmpty {
                            Text(model.text("No confidently attributed candidate. Missing logs are not an all-clear result.", "沒有能明確歸屬的候選 App。日誌不足不代表問題已解除。"))
                                .font(.callout)
                        }
                        ForEach(scan.candidates) { candidate in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.bundle.rawValue).font(.callout.monospaced()).textSelection(.enabled)
                                    Text(model.text("\(candidate.failureCount) matching request(s)", "\(candidate.failureCount) 筆符合的請求")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(model.text("Use this app", "選擇此 App")) { model.useCandidate(candidate) }.disabled(model.busy)
                            }.padding(.vertical, 4)
                        }
                    }
                    Text(model.text("Only ASDErrorDomain 506 with “Duplicate restoring request” is matched. Imported logs may be from another phone: verify your selected device. No batch removal.", "僅匹配 ASDErrorDomain 506 與「Duplicate restoring request」。匯入日誌可能來自其他手機，請核對選定裝置。不提供批次移除。"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                card {
                    sectionTitle("3", model.text("Check one app, then decide", "檢查單一 App，再決定是否移除"))
                    TextField(model.text("Bundle identifier", "App 識別碼"), text: $model.bundleText)
                        .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder).disabled(model.busy)
                    Text(model.text("X uses com.atebits.Tweetie2. For another app, verify its bundle ID from a trusted source. A missing icon alone is not a diagnosis.", "X 的識別碼為 com.atebits.Tweetie2。其他 App 請從可信來源確認識別碼；找不到圖示本身不能診斷問題。"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.text("Check selected app", "檢查選定 App"), action: model.inspectTarget)
                            .disabled(model.busy || model.target == nil)
                        Spacer()
                        Button(role: .destructive, action: model.requestUninstall) {
                            Text(model.text("Uninstall selected app…", "卸載選定 App…"))
                        }.disabled(!model.canUninstall)
                    }
                    Label(model.text("Uninstalling can permanently delete this app’s local data, including unsynced drafts. It is not a guaranteed repair.", "卸載可能永久刪除這個 App 的本機資料，包括未同步草稿，且不保證能修復問題。"), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }

                HStack(alignment: .top, spacing: 12) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.completed ? "checkmark.circle.fill" : "info.circle").foregroundStyle(model.completed ? .green : .secondary) }
                    Text(model.statusText).font(.callout).textSelection(.enabled)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                Text(model.text("Independent open-source utility. Not affiliated with Apple or any app developer. The app does not upload diagnostics or save raw captures or full device identifiers.", "獨立開源工具，與 Apple 或 App 開發者無隸屬關係。不會上傳診斷資料，也不會另存原始監看內容或完整裝置識別碼。"))
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
            Label(model.text("Confirm one uninstall request", "確認單一卸載請求"), systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundStyle(.orange)
            Text(target.device.masked).font(.headline)
            Text(target.bundle.rawValue).font(.body.monospaced()).textSelection(.enabled)
            Text(model.text("This removes the selected app and may permanently delete its local data. It does not erase the phone, select another device, or install anything. Clearing an orphaned restore is not guaranteed. A successful response still needs a manual App Store download test.", "這會移除選定 App，並可能永久刪除其本機資料。不會清除整支手機、改選其他裝置或安裝軟體。不保證能清除殘留回復工作；即使回報成功，仍需自行在 App Store 測試下載。"))
            Text(model.text("Type the exact bundle identifier to continue:", "請完整輸入上方 App 識別碼才能繼續：")).font(.callout)
            TextField(target.bundle.rawValue, text: $typedText).textFieldStyle(.roundedBorder).font(.body.monospaced())
            HStack {
                Button(model.text("Cancel", "取消")) { model.confirmation = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) { model.confirmUninstall(target: target, typedText: typedText) } label: {
                    Text(model.text("Uninstall this app", "卸載這個 App"))
                }.disabled(typedText != target.bundle.rawValue)
            }
        }.padding(28).frame(width: 560)
    }
}

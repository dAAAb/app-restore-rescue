import Foundation

/// Matches the languages declared in the app's CFBundleLocalizations metadata.
public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case traditionalChinese = "zh-Hant"

    public static var supportedLocalizations: [String] { allCases.map(\.rawValue) }

    /// Ask Foundation to handle language, script, and region fallback in preference order.
    public static func resolve(preferredLanguages: [String]) -> AppLanguage {
        let matches = Bundle.preferredLocalizations(from: supportedLocalizations, forPreferences: preferredLanguages)
        return matches.compactMap(AppLanguage.init(rawValue:)).first ?? .english
    }

    /// Bundle.main.preferredLocalizations includes macOS's per-app language choice.
    /// Debug overrides are ignored unless the process is explicitly in synthetic demo mode.
    public static func forApplication(preferredLocalizations: [String], arguments: [String]) -> AppLanguage {
        if arguments.contains("--demo") {
            let prefix = "--demo-language="
            if let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
               let language = AppLanguage(rawValue: String(argument.dropFirst(prefix.count))) {
                return language
            }
            if arguments.contains("--english") { return .english }
        }
        return resolve(preferredLanguages: preferredLocalizations)
    }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .traditionalChinese: return "繁體中文"
        }
    }

    public func text(_ message: AppMessage) -> String { message.translation.value(for: self) }

    public func scanSummary(matched: Int, unattributed: Int) -> String {
        String(format: text(.scanSummary), locale: Locale(identifier: rawValue), arguments: [matched, unattributed])
    }

    public func matchingRequests(_ count: Int) -> String {
        String(format: text(.matchingRequests), locale: Locale(identifier: rawValue), arguments: [count])
    }
}

public enum AppMessage: String, CaseIterable, Sendable {
    case uninstallStillRunning
    case quitDuringUninstall
    case waitForCompletion
    case quitAnyway
    case chooseLocalLog
    case idle
    case checkingTools
    case noDevice
    case chooseDevice
    case inspecting
    case appRecordFound
    case appRecordMissing
    case connectingMonitor
    case listening
    case scanning
    case scanned
    case uninstalling
    case uninstallCompleted
    case missingTools
    case unsupportedVersion
    case invalidDevice
    case invalidBundle
    case confirmationMismatch
    case inspectionRequired
    case deviceDisconnected
    case serviceUnavailable
    case launchFailed
    case readTimedOut
    case outputTooLarge
    case inspectionFailed
    case uninstallFailed
    case uninstallUncertain
    case unreadableLog
    case unsupportedLog
    case archiveReadFailed
    case subtitle
    case localPrivacy
    case demoNotice
    case connectTitle
    case connectHelp
    case checkTools
    case phoneLabel
    case selectDevice
    case manualSetupHelp
    case findErrorsTitle
    case monitorHelp
    case stopMonitoring
    case monitorFor60Seconds
    case importLocalLog
    case scanSummary
    case noCandidate
    case matchingRequests
    case useCandidate
    case scanScope
    case inspectTitle
    case bundleLabel
    case bundleHelp
    case checkSelectedApp
    case uninstallSelectedApp
    case dataLossWarning
    case privacyFooter
    case confirmUninstallTitle
    case confirmUninstallHelp
    case typeBundlePrompt
    case cancel
    case uninstallThisApp
    case systemLanguageHelp

    fileprivate var translation: Translation {
        switch self {
        case .uninstallStillRunning:
            return Translation(en: "An uninstall request is still running",
                               ja: "アンインストール要求を処理中です",
                               ko: "앱 제거 요청을 처리하고 있습니다",
                               zh: "卸載請求仍在執行")
        case .quitDuringUninstall:
            return Translation(en: "Quitting stops this tool's child process, but cannot undo a request already sent to the phone. The outcome may be unknown. Wait for completion unless you intend to stop observing it.",
                               ja: "終了するとこのツールの子プロセスは停止しますが、すでに iPhone に届いた要求は取り消せません。結果が不明になる可能性があります。処理の監視を中断する意図がなければ、完了までお待ちください。",
                               ko: "종료하면 이 도구의 하위 프로세스가 중지되지만, 이미 iPhone에 전달된 요청은 취소할 수 없습니다. 결과를 알 수 없게 될 수 있습니다. 처리를 더 이상 확인하지 않아도 되는 경우가 아니라면 완료될 때까지 기다리세요.",
                               zh: "離開會停止本工具的子程序，但無法撤回已送達手機的請求，結果可能不確定。建議等待完成後再離開。")
        case .waitForCompletion:
            return Translation(en: "Wait for completion",
                               ja: "完了まで待つ",
                               ko: "완료될 때까지 기다리기",
                               zh: "等待完成")
        case .quitAnyway:
            return Translation(en: "Quit anyway",
                               ja: "このまま終了",
                               ko: "그래도 종료",
                               zh: "仍要離開")
        case .chooseLocalLog:
            return Translation(en: "Choose a local diagnostic log",
                               ja: "この Mac に保存された診断ログを選択",
                               ko: "이 Mac에 저장된 진단 로그 선택",
                               zh: "選擇本機診斷日誌")
        case .idle:
            return Translation(en: "Nothing has been changed. Start by checking the existing tools and USB connection.",
                               ja: "まだ何も変更していません。まず既存のツールと USB 接続を確認してください。",
                               ko: "아직 아무것도 변경하지 않았습니다. 먼저 기존 도구와 USB 연결을 확인하세요.",
                               zh: "尚未變更任何內容。先檢查既有工具與 USB 連線。")
        case .checkingTools:
            return Translation(en: "Checking existing tools and USB devices…",
                               ja: "既存のツールと USB デバイスを確認中…",
                               ko: "기존 도구와 USB 기기 확인 중…",
                               zh: "正在檢查既有工具與 USB 裝置…")
        case .noDevice:
            return Translation(en: "No USB iPhone found. Unlock your phone, check the cable, then refresh. A restricted execution environment can also block the USB service.",
                               ja: "USB 接続された iPhone が見つかりません。iPhone のロックを解除し、ケーブルを確認してから再確認してください。実行環境の制限により USB サービスにアクセスできない場合もあります。",
                               ko: "USB로 연결된 iPhone을 찾지 못했습니다. iPhone의 잠금을 해제하고 케이블을 확인한 다음 다시 확인하세요. 실행 환경의 제한으로 USB 서비스에 접근하지 못할 수도 있습니다.",
                               zh: "未找到 USB iPhone。請解鎖手機、確認傳輸線後重新檢查。受限制的執行環境也可能阻擋 USB 服務。")
        case .chooseDevice:
            return Translation(en: "Choose the intended iPhone. No device is selected automatically.",
                               ja: "操作対象の iPhone を選択してください。デバイスは自動選択されません。",
                               ko: "작업할 iPhone을 선택하세요. 기기는 자동으로 선택되지 않습니다.",
                               zh: "請選擇要處理的 iPhone。工具不會自動選擇裝置。")
        case .inspecting:
            return Translation(en: "Checking only the selected app…",
                               ja: "選択したアプリだけを確認中…",
                               ko: "선택한 앱만 확인 중…",
                               zh: "只檢查選定的 App…")
        case .appRecordFound:
            return Translation(en: "An app record exists. That alone does not prove a stuck restore. Uninstalling can delete its local data.",
                               ja: "アプリの登録情報が見つかりました。それだけでは復元が止まっている証拠にはなりません。アンインストールするとローカルデータが削除される可能性があります。",
                               ko: "앱 등록 정보를 찾았습니다. 이것만으로 복원이 멈췄다고 판단할 수는 없습니다. 앱을 제거하면 로컬 데이터가 삭제될 수 있습니다.",
                               zh: "找到 App 紀錄，但這本身不能證明回復卡住。卸載可能刪除其本機資料。")
        case .appRecordMissing:
            return Translation(en: "No app record was returned. A targeted uninstall request can still be submitted, but may be rejected or fail to clear the restore.",
                               ja: "アプリの登録情報は返されませんでした。指定したアプリのアンインストール要求は送信できますが、拒否されたり、復元の問題が解消されなかったりする可能性があります。",
                               ko: "앱 등록 정보가 반환되지 않았습니다. 지정한 앱의 제거 요청을 보낼 수는 있지만, 거부되거나 복원 문제가 해결되지 않을 수 있습니다.",
                               zh: "沒有查到 App 紀錄。仍可提出指定卸載請求，但系統可能拒絕，或無法解除回復狀態。")
        case .connectingMonitor:
            return Translation(en: "Connecting to the selected phone’s log service. WAIT for the “Listening” message before pressing the cloud button.",
                               ja: "選択した iPhone のログサービスに接続中です。「監視中」と表示されるまで、雲のダウンロードボタンを押さずにお待ちください。",
                               ko: "선택한 iPhone의 로그 서비스에 연결 중입니다. “모니터링 중”이 표시될 때까지 구름 다운로드 버튼을 누르지 말고 기다리세요.",
                               zh: "正在連接選定手機的日誌服務。請等待顯示「已開始監看」，再按雲朵下載按鈕。")
        case .listening:
            return Translation(en: "Listening — the phone’s log service is connected. Tap the affected app’s cloud button ONCE in App Store. Wait for the cloud to return, then stop. This manual retry may install the app if it succeeds. Monitoring stops automatically within 60 seconds of launch.",
                               ja: "監視中 — iPhone のログサービスに接続しました。App Store で対象アプリの雲のボタンを 1 回だけ押してください。雲の表示に戻ったら監視を停止してください。手動での再試行が成功すると、アプリのインストールが始まる場合があります。監視は開始から 60 秒以内に自動停止します。",
                               ko: "모니터링 중 — iPhone의 로그 서비스에 연결되었습니다. App Store에서 문제 앱의 구름 버튼을 한 번만 누르세요. 다시 구름이 표시되면 모니터링을 중지하세요. 이 수동 재시도가 성공하면 앱 설치가 시작될 수 있습니다. 모니터링은 시작 후 60초 이내에 자동으로 중지됩니다.",
                               zh: "已開始監看 — 手機日誌服務已連線。請在 App Store 按一次該 App 的雲朵，等雲朵再次出現後停止監看。手動重試若成功，可能開始安裝 App。監看會在啟動後 60 秒內自動停止。")
        case .scanning:
            return Translation(en: "Reading the selected log locally. Nothing is uploaded…",
                               ja: "選択したログをこの Mac で読み取り中です。アップロードは行いません…",
                               ko: "선택한 로그를 이 Mac에서 읽는 중입니다. 업로드하지 않습니다…",
                               zh: "正在本機讀取選定日誌，不會上傳…")
        case .scanned:
            return Translation(en: "Scan finished. Results are candidates, not proof that a current restore is stuck. No matches does not mean the phone is healthy or the problem is gone.",
                               ja: "スキャンが完了しました。結果は候補であり、現在も復元が止まっている証拠ではありません。一致するログがなくても、iPhone が正常、または問題が解消済みとは限りません。",
                               ko: "스캔이 완료되었습니다. 결과는 후보 목록이며, 현재도 복원이 멈춰 있다는 증거는 아닙니다. 일치하는 로그가 없어도 iPhone이 정상이라거나 문제가 해결되었다고 판단할 수 없습니다.",
                               zh: "掃描完成。結果是候選項目，不能證明目前仍卡住；沒有匹配也不代表手機正常或問題已解除。")
        case .uninstalling:
            return Translation(en: "Submitting one uninstall request for the confirmed device and app. Do not disconnect the phone…",
                               ja: "確認済みのデバイスとアプリに対して、アンインストール要求を 1 件送信中です。iPhone を取り外さないでください…",
                               ko: "확인한 기기와 앱에 대해 제거 요청 한 건을 보내고 있습니다. iPhone을 분리하지 마세요…",
                               zh: "正在對確認的裝置與 App 提出一筆卸載請求。請勿拔除手機…")
        case .uninstallCompleted:
            return Translation(en: "The uninstall request completed. Now manually download the app in App Store to check whether the problem is resolved. No app was installed by this tool.",
                               ja: "アンインストール要求が完了しました。App Store から手動でダウンロードして、問題が解消したか確認してください。このツールはアプリをインストールしていません。",
                               ko: "앱 제거 요청이 완료되었습니다. App Store에서 직접 다운로드하여 문제가 해결되었는지 확인하세요. 이 도구는 앱을 설치하지 않았습니다.",
                               zh: "卸載請求已完成。請自行回到 App Store 下載，確認問題是否解除。此工具沒有安裝任何 App。")
        case .missingTools:
            return Translation(en: "Required tools were not found. Install ideviceinstaller yourself with Homebrew; the app never installs dependencies. Live monitoring also needs idevicesyslog from libimobiledevice.",
                               ja: "必要なツールが見つかりません。Homebrew で ideviceinstaller をご自身でインストールしてください。このアプリが依存ソフトをインストールすることはありません。リアルタイム監視には libimobiledevice の idevicesyslog も必要です。",
                               ko: "필요한 도구를 찾지 못했습니다. Homebrew로 ideviceinstaller를 직접 설치하세요. 이 앱은 의존 도구를 설치하지 않습니다. 실시간 모니터링에는 libimobiledevice의 idevicesyslog도 필요합니다.",
                               zh: "找不到必要工具。請自行用 Homebrew 安裝 ideviceinstaller；本工具不會安裝相依元件。即時監看另需 libimobiledevice 提供的 idevicesyslog。")
        case .unsupportedVersion:
            return Translation(en: "ideviceinstaller 1.2.0 or later is required. No software was installed or updated.",
                               ja: "ideviceinstaller 1.2.0 以降が必要です。ソフトウェアのインストールや更新は行っていません。",
                               ko: "ideviceinstaller 1.2.0 이상이 필요합니다. 소프트웨어를 설치하거나 업데이트하지 않았습니다.",
                               zh: "需要 ideviceinstaller 1.2.0 以上版本。尚未安裝或更新任何軟體。")
        case .invalidDevice:
            return Translation(en: "Unexpected device identifier. The operation was stopped.",
                               ja: "デバイス識別子の形式が正しくないため、操作を停止しました。",
                               ko: "기기 식별자의 형식이 올바르지 않아 작업을 중지했습니다.",
                               zh: "裝置識別碼格式不符，已停止操作。")
        case .invalidBundle:
            return Translation(en: "Enter one valid third-party bundle identifier. Wildcards, Apple system apps, and shell options are not accepted.",
                               ja: "有効なサードパーティ製アプリの Bundle ID を 1 つ入力してください。ワイルドカード、Apple のシステムアプリ、シェルオプションは使用できません。",
                               ko: "올바른 타사 앱의 번들 ID 하나를 입력하세요. 와일드카드, Apple 시스템 앱 및 셸 옵션은 사용할 수 없습니다.",
                               zh: "請輸入單一有效的第三方 App 識別碼。不接受萬用字元、Apple 系統 App 或命令選項。")
        case .confirmationMismatch:
            return Translation(en: "The confirmation must exactly match the bundle identifier.",
                               ja: "確認用の入力は Bundle ID と完全に一致する必要があります。",
                               ko: "확인 입력은 번들 ID와 정확히 일치해야 합니다.",
                               zh: "確認文字必須與 App 識別碼完全相同。")
        case .inspectionRequired:
            return Translation(en: "Check this exact device and app again before requesting uninstall.",
                               ja: "アンインストール要求の前に、このデバイスとアプリをもう一度確認してください。",
                               ko: "제거를 요청하기 전에 이 기기와 앱을 다시 확인하세요.",
                               zh: "提出卸載前，請重新檢查這個裝置與 App。")
        case .deviceDisconnected:
            return Translation(en: "The selected USB device is no longer available. No other device will be substituted.",
                               ja: "選択した USB デバイスに接続できなくなりました。別のデバイスに切り替えることはありません。",
                               ko: "선택한 USB 기기에 더 이상 연결할 수 없습니다. 다른 기기로 바꾸어 작업하지 않습니다.",
                               zh: "選定的 USB 裝置已無法使用。工具不會改選其他裝置。")
        case .serviceUnavailable:
            return Translation(en: "The USB device service could not be reached, or the log connection ended with an error. Check the cable, unlock/trust status, and execution restrictions. No repair was attempted.",
                               ja: "USB デバイスサービスにアクセスできないか、ログ接続でエラーが発生しました。ケーブル、ロック解除と信頼の状態、実行環境の制限を確認してください。修復は試みていません。",
                               ko: "USB 기기 서비스에 접근하지 못했거나 로그 연결에 오류가 발생했습니다. 케이블, 잠금 해제 및 신뢰 상태, 실행 환경의 제한을 확인하세요. 복구 작업은 시도하지 않았습니다.",
                               zh: "無法存取 USB 裝置服務，或日誌連線出錯。請檢查傳輸線、解鎖／信任狀態與執行限制。尚未嘗試修復。")
        case .launchFailed:
            return Translation(en: "An existing command-line tool could not start. No installer will be launched.",
                               ja: "既存のコマンドラインツールを起動できませんでした。インストーラを起動することはありません。",
                               ko: "기존 명령줄 도구를 시작하지 못했습니다. 설치 프로그램을 실행하지 않습니다.",
                               zh: "既有命令列工具無法啟動。不會啟動任何安裝程式。")
        case .readTimedOut:
            return Translation(en: "The read operation timed out. Try a smaller log or check the connection.",
                               ja: "読み取りがタイムアウトしました。ログの範囲を小さくするか、接続を確認してください。",
                               ko: "읽기 시간이 초과되었습니다. 로그 범위를 줄이거나 연결을 확인하세요.",
                               zh: "讀取逾時。請縮小日誌範圍或檢查連線。")
        case .outputTooLarge:
            return Translation(en: "The diagnostic output exceeded the memory limit. Export a shorter time range and try again. No partial result is treated as a clean scan.",
                               ja: "診断データがメモリ上限を超えました。より短い期間のログを書き出して再試行してください。不完全な結果を正常と判定することはありません。",
                               ko: "진단 데이터가 메모리 한도를 초과했습니다. 더 짧은 기간의 로그를 내보낸 후 다시 시도하세요. 불완전한 결과를 정상으로 판단하지 않습니다.",
                               zh: "診斷資料超過記憶體上限。請匯出較短時段後重試；不會把不完整結果視為正常。")
        case .inspectionFailed:
            return Translation(en: "The selected app could not be checked reliably. Uninstall remains unavailable until a new check succeeds.",
                               ja: "選択したアプリを確実に確認できませんでした。再確認が成功するまでアンインストールはできません。",
                               ko: "선택한 앱을 확실하게 확인하지 못했습니다. 다시 확인하여 성공할 때까지 제거할 수 없습니다.",
                               zh: "無法可靠檢查選定 App。必須重新檢查成功後，才可提出卸載。")
        case .uninstallFailed:
            return Translation(en: "The phone reported that uninstall failed. The result was not retried, and no other app was targeted.",
                               ja: "iPhone がアンインストール失敗を報告しました。再試行は行わず、他のアプリも対象にしていません。",
                               ko: "iPhone에서 앱 제거 실패를 보고했습니다. 다시 시도하지 않았으며 다른 앱도 대상으로 지정하지 않았습니다.",
                               zh: "手機回報卸載失敗。工具沒有重試，也沒有指定其他 App。")
        case .uninstallUncertain:
            return Translation(en: "The uninstall outcome is UNKNOWN. The request may already have reached the phone. Check the phone and App Store before doing anything else; do not blindly retry.",
                               ja: "アンインストールの結果は不明です。要求はすでに iPhone に届いている可能性があります。次の操作の前に、iPhone と App Store の状態を確認してください。状況を確認せずに再試行しないでください。",
                               ko: "앱 제거 결과를 알 수 없습니다. 요청이 이미 iPhone에 전달되었을 수 있습니다. 다음 작업을 하기 전에 iPhone과 App Store의 상태를 확인하세요. 확인 없이 다시 시도하지 마세요.",
                               zh: "卸載結果不確定。請求可能已送達手機。請先查看手機與 App Store 狀態，不要直接重試。")
        case .unreadableLog:
            return Translation(en: "The selected log could not be read as UTF-8 text.",
                               ja: "選択したログを UTF-8 テキストとして読み取れませんでした。",
                               ko: "선택한 로그를 UTF-8 텍스트로 읽지 못했습니다.",
                               zh: "無法以 UTF-8 文字讀取選定日誌。")
        case .unsupportedLog:
            return Translation(en: "Choose a .logarchive, .log, .txt, .jsonl, .ndjson, or .json log file.",
                               ja: ".logarchive、.log、.txt、.jsonl、.ndjson、または .json のログファイルを選択してください。",
                               ko: ".logarchive, .log, .txt, .jsonl, .ndjson 또는 .json 로그 파일을 선택하세요.",
                               zh: "請選擇 .logarchive、.log、.txt、.jsonl、.ndjson 或 .json 日誌。")
        case .archiveReadFailed:
            return Translation(en: "macOS could not read this archive. The app will not request sudo or collect another archive automatically.",
                               ja: "macOS がこのログアーカイブを読み取れませんでした。このアプリは sudo を要求せず、別のアーカイブを自動収集することもありません。",
                               ko: "macOS가 이 로그 아카이브를 읽지 못했습니다. 이 앱은 sudo를 요청하거나 다른 아카이브를 자동으로 수집하지 않습니다.",
                               zh: "macOS 無法讀取這份日誌封存。工具不會要求 sudo，也不會自動收集另一份日誌。")
        case .subtitle:
            return Translation(en: "A careful way out of a stuck iPhone app restore.",
                               ja: "停止した iPhone アプリの復元を調べ、対処を支援します。",
                               ko: "멈춘 iPhone 앱 복원을 확인하고 해결을 돕습니다.",
                               zh: "協助處理卡住的 iPhone App 回復。")
        case .localPrivacy:
            return Translation(en: "Local only · No telemetry · No automatic installs",
                               ja: "この Mac で処理 · テレメトリなし · 自動インストールなし",
                               ko: "이 Mac에서 처리 · 원격 측정 없음 · 자동 설치 없음",
                               zh: "本機處理 · 無遙測 · 不自動安裝")
        case .demoNotice:
            return Translation(en: "DEMO — Synthetic data. All device actions are disabled.",
                               ja: "デモ — すべて架空のデータです。デバイス操作はすべて無効です。",
                               ko: "데모 — 모두 가상 데이터입니다. 모든 기기 작업이 비활성화되어 있습니다.",
                               zh: "示範模式 — 全部為合成資料，停用所有裝置操作。")
        case .connectTitle:
            return Translation(en: "Connect and choose your iPhone",
                               ja: "iPhone を接続して選択",
                               ko: "iPhone 연결 및 선택",
                               zh: "連接並選擇 iPhone")
        case .connectHelp:
            return Translation(en: "Use USB, unlock the phone, and trust this Mac yourself if prompted. Device IDs are shown only in masked form and are not saved.",
                               ja: "USB で接続し、iPhone のロックを解除してください。信頼の確認が表示されたら、ご自身でこの Mac を信頼するか判断してください。デバイス識別子は一部を隠して表示し、保存しません。",
                               ko: "USB로 연결하고 iPhone의 잠금을 해제하세요. 신뢰 확인이 표시되면 이 Mac을 신뢰할지 직접 결정하세요. 기기 식별자는 일부를 가려 표시하며 저장하지 않습니다.",
                               zh: "透過 USB 連接並解鎖手機；若出現提示，請自行確認信任這台 Mac。裝置識別碼僅顯示遮罩，不會儲存。")
        case .checkTools:
            return Translation(en: "Check tools & USB",
                               ja: "ツールと USB を確認",
                               ko: "도구 및 USB 확인",
                               zh: "檢查工具與 USB")
        case .phoneLabel:
            return Translation(en: "iPhone",
                               ja: "iPhone",
                               ko: "iPhone",
                               zh: "iPhone")
        case .selectDevice:
            return Translation(en: "Select a device…",
                               ja: "デバイスを選択…",
                               ko: "기기 선택…",
                               zh: "請選擇裝置…")
        case .manualSetupHelp:
            return Translation(en: "If tools are missing, this is a manual setup command for you to review. This app never runs Homebrew, sudo, Xcode setup, or a software installer.",
                               ja: "ツールがない場合、上のコマンドをご確認のうえ、ご自身で設定してください。このアプリは Homebrew、sudo、Xcode の設定、ソフトウェアのインストーラを実行しません。",
                               ko: "도구가 없다면 위 명령을 검토한 후 직접 설치하세요. 이 앱은 Homebrew, sudo, Xcode 설정 또는 소프트웨어 설치 프로그램을 실행하지 않습니다.",
                               zh: "若缺少工具，以上是供你自行檢視的安裝指令。本工具不會執行 Homebrew、sudo、Xcode 設定或軟體安裝程式。")
        case .findErrorsTitle:
            return Translation(en: "Find matching restore errors",
                               ja: "一致する復元エラーを検索",
                               ko: "일치하는 복원 오류 찾기",
                               zh: "找出符合條件的回復錯誤")
        case .monitorHelp:
            return Translation(en: "Start monitoring, wait for “Listening,” then try the affected app’s cloud button once. Logs stay in memory; only matching app IDs and counts are shown. You can also import an existing local log.",
                               ja: "監視を開始し、「監視中」と表示されたら対象アプリの雲のボタンを 1 回押してください。ログはメモリ内だけに保持し、画面には一致したアプリ ID と件数だけを表示します。既存のローカルログも読み込めます。",
                               ko: "모니터링을 시작하고 “모니터링 중”이 표시되면 문제 앱의 구름 버튼을 한 번 누르세요. 로그는 메모리에만 유지되며 일치하는 앱 ID와 건수만 표시됩니다. 기존 로컬 로그를 가져올 수도 있습니다.",
                               zh: "先開始監看，等顯示「已開始監看」，再按一次問題 App 的雲朵。日誌只留在記憶體，畫面僅顯示匹配的 App 識別碼與次數。也可以匯入既有的本機日誌。")
        case .stopMonitoring:
            return Translation(en: "Stop monitoring",
                               ja: "監視を停止",
                               ko: "모니터링 중지",
                               zh: "停止監看")
        case .monitorFor60Seconds:
            return Translation(en: "Monitor for 60 seconds",
                               ja: "60 秒間監視",
                               ko: "60초 동안 모니터링",
                               zh: "監看 60 秒")
        case .importLocalLog:
            return Translation(en: "Import local log…",
                               ja: "ローカルログを読み込む…",
                               ko: "로컬 로그 가져오기…",
                               zh: "匯入本機日誌…")
        case .scanSummary:
            return Translation(en: "Matched failures: %ld · Unattributed: %ld",
                               ja: "一致したエラー：%ld · 対象不明：%ld",
                               ko: "일치한 오류: %ld · 대상 불명: %ld",
                               zh: "匹配錯誤：%ld · 無法歸屬：%ld")
        case .noCandidate:
            return Translation(en: "No confidently attributed candidate. Missing logs are not an all-clear result.",
                               ja: "対象を確実に特定できる候補はありません。ログがないことは、問題がないという意味ではありません。",
                               ko: "대상을 확실하게 식별할 수 있는 후보가 없습니다. 로그가 없다고 문제가 없다는 뜻은 아닙니다.",
                               zh: "沒有能明確歸屬的候選 App。日誌不足不代表問題已解除。")
        case .matchingRequests:
            return Translation(en: "Matching requests: %ld",
                               ja: "一致した要求：%ld 件",
                               ko: "일치한 요청: %ld건",
                               zh: "%ld 筆符合的請求")
        case .useCandidate:
            return Translation(en: "Use this app",
                               ja: "このアプリを選択",
                               ko: "이 앱 선택",
                               zh: "選擇此 App")
        case .scanScope:
            return Translation(en: "Only ASDErrorDomain 506 with “Duplicate restoring request” is matched. Imported logs may be from another phone: verify your selected device. No batch removal.",
                               ja: "ASDErrorDomain 506 と「Duplicate restoring request」の両方に一致するログだけを対象にします。読み込んだログが別の iPhone のものかもしれません。選択したデバイスを確認してください。一括削除は行いません。",
                               ko: "ASDErrorDomain 506과 “Duplicate restoring request”가 모두 일치하는 로그만 찾습니다. 가져온 로그가 다른 iPhone의 것일 수 있으므로 선택한 기기를 확인하세요. 일괄 제거는 하지 않습니다.",
                               zh: "僅匹配 ASDErrorDomain 506 與「Duplicate restoring request」。匯入日誌可能來自其他手機，請核對選定裝置。不提供批次移除。")
        case .inspectTitle:
            return Translation(en: "Check one app, then decide",
                               ja: "アプリを 1 つ確認して判断",
                               ko: "앱 하나를 확인한 후 결정",
                               zh: "檢查單一 App，再決定是否移除")
        case .bundleLabel:
            return Translation(en: "Bundle identifier",
                               ja: "Bundle ID",
                               ko: "번들 ID",
                               zh: "App 識別碼")
        case .bundleHelp:
            return Translation(en: "X uses com.atebits.Tweetie2. For another app, verify its bundle ID from a trusted source. A missing icon alone is not a diagnosis.",
                               ja: "X の Bundle ID は com.atebits.Tweetie2 です。他のアプリは信頼できる情報源で Bundle ID を確認してください。アイコンが見つからないだけでは原因を特定できません。",
                               ko: "X의 번들 ID는 com.atebits.Tweetie2입니다. 다른 앱은 신뢰할 수 있는 출처에서 번들 ID를 확인하세요. 아이콘이 보이지 않는 것만으로 원인을 판단할 수 없습니다.",
                               zh: "X 的識別碼為 com.atebits.Tweetie2。其他 App 請從可信來源確認識別碼；找不到圖示本身不能診斷問題。")
        case .checkSelectedApp:
            return Translation(en: "Check selected app",
                               ja: "選択したアプリを確認",
                               ko: "선택한 앱 확인",
                               zh: "檢查選定 App")
        case .uninstallSelectedApp:
            return Translation(en: "Uninstall selected app…",
                               ja: "選択したアプリをアンインストール…",
                               ko: "선택한 앱 제거…",
                               zh: "卸載選定 App…")
        case .dataLossWarning:
            return Translation(en: "Uninstalling can permanently delete this app’s local data, including unsynced drafts. It is not a guaranteed repair.",
                               ja: "アンインストールにより、未同期の下書きを含むアプリのローカルデータが完全に削除される可能性があります。修復を保証するものではありません。",
                               ko: "앱을 제거하면 동기화되지 않은 초안을 포함한 앱의 로컬 데이터가 영구적으로 삭제될 수 있습니다. 문제가 해결된다는 보장은 없습니다.",
                               zh: "卸載可能永久刪除這個 App 的本機資料，包括未同步草稿，且不保證能修復問題。")
        case .privacyFooter:
            return Translation(en: "Independent open-source utility. Not affiliated with Apple or any app developer. The app does not upload diagnostics or save raw captures or full device identifiers.",
                               ja: "独立したオープンソースツールです。Apple やアプリ開発者との提携はありません。診断データのアップロードや、取得した生ログ・完全なデバイス識別子の保存は行いません。",
                               ko: "독립 오픈 소스 도구이며 Apple 또는 앱 개발자와 제휴 관계가 없습니다. 진단 데이터를 업로드하거나 원본 로그 또는 전체 기기 식별자를 저장하지 않습니다.",
                               zh: "獨立開源工具，與 Apple 或 App 開發者無隸屬關係。不會上傳診斷資料，也不會另存原始監看內容或完整裝置識別碼。")
        case .confirmUninstallTitle:
            return Translation(en: "Confirm one uninstall request",
                               ja: "アンインストール要求 1 件を確認",
                               ko: "앱 제거 요청 한 건 확인",
                               zh: "確認單一卸載請求")
        case .confirmUninstallHelp:
            return Translation(en: "This removes the selected app and may permanently delete its local data. It does not erase the phone, select another device, or install anything. Clearing an orphaned restore is not guaranteed. A successful response still needs a manual App Store download test.",
                               ja: "選択したアプリを削除し、そのローカルデータが完全に削除される可能性があります。iPhone 全体の消去、他のデバイスへの切り替え、ソフトウェアのインストールは行いません。残留した復元状態の解消は保証できません。成功と返された場合も、App Store から手動でダウンロードして確認する必要があります。",
                               ko: "선택한 앱을 제거하며, 해당 앱의 로컬 데이터가 영구적으로 삭제될 수 있습니다. iPhone 전체를 지우거나 다른 기기로 바꾸거나 소프트웨어를 설치하지 않습니다. 남아 있는 복원 상태가 해소된다는 보장은 없습니다. 성공 응답을 받아도 App Store에서 직접 다운로드하여 확인해야 합니다.",
                               zh: "這會移除選定 App，並可能永久刪除其本機資料。不會清除整支手機、改選其他裝置或安裝軟體。不保證能清除殘留回復工作；即使回報成功，仍需自行在 App Store 測試下載。")
        case .typeBundlePrompt:
            return Translation(en: "Type the exact bundle identifier to continue:",
                               ja: "続行するには、上の Bundle ID を正確に入力してください：",
                               ko: "계속하려면 위의 번들 ID를 정확히 입력하세요:",
                               zh: "請完整輸入上方 App 識別碼才能繼續：")
        case .cancel:
            return Translation(en: "Cancel",
                               ja: "キャンセル",
                               ko: "취소",
                               zh: "取消")
        case .uninstallThisApp:
            return Translation(en: "Uninstall this app",
                               ja: "このアプリをアンインストール",
                               ko: "이 앱 제거",
                               zh: "卸載這個 App")
        case .systemLanguageHelp:
            return Translation(en: "Follows the macOS language preference. Change the language in System Settings, then reopen the app.",
                               ja: "macOS の言語設定に従います。システム設定で言語を変更した後、アプリを開き直してください。",
                               ko: "macOS의 언어 설정을 따릅니다. 시스템 설정에서 언어를 변경한 후 앱을 다시 여세요.",
                               zh: "依照 macOS 語言偏好顯示。請在系統設定變更語言後，重新開啟 App。")
        }
    }
}

fileprivate struct Translation {
    let en: String
    let ja: String
    let ko: String
    let zh: String

    func value(for language: AppLanguage) -> String {
        switch language {
        case .english: return en
        case .japanese: return ja
        case .korean: return ko
        case .traditionalChinese: return zh
        }
    }
}

# Privacy / 隱私說明

App Restore Rescue has no account system, analytics SDK, telemetry endpoint, remote diagnostics service, or automatic updater. Its device operations run on the Mac and target the device selected in the current session.

## What is processed locally

| Input | Purpose | App handling |
| --- | --- | --- |
| USB device identifiers | Select and address exactly one attached device | Held in memory; masked in the interface |
| A bundle identifier | Inspect or request uninstall of one app | Validated and passed as a separate process argument |
| A user-selected text, JSONL, or `.logarchive` diagnostic file | Find explicit restore-error candidates | Read locally; not uploaded or copied into the project |
| An explicitly started, bounded device log stream | Capture a manually reproduced failure | Processed locally in memory; not saved as an app log file |
| Tool results | Report completion, failure, or unknown outcome | Show coarse results; do not publish raw output |

Log files and live streams can contain unrelated private material even when the requested analysis is narrow. Only choose logs you are allowed to inspect. An imported log may describe an earlier device state; its findings are not proof of the current condition.

The app does not export new phone log archives, read photo/message content, collect an inventory of every installed app, request an Apple Account password, or upload data. It does not copy pairing records or intentionally store full device identifiers or raw logs in preferences, files, support bundles, or the clipboard. Closing the app releases its in-memory session; this is not a promise of cryptographic memory erasure.

## External boundaries

- `ideviceinstaller`, `idevice_id`, and `idevicesyslog` are independently installed tools. They communicate with Apple's local device service and the connected phone. Their behavior and licenses are separate from this app.
- macOS/iOS may maintain system logs, process metadata, crash diagnostics, connection state, or trust records. Full identifiers passed to a device tool may be visible to other sufficiently privileged local software. The app cannot guarantee zero operating-system writes or protection from a compromised Mac.
- The user's original diagnostic files remain where the user stored them. The app does not delete or sanitize those originals.
- GitHub, Homebrew, and websites opened by the user have their own network and privacy behavior. Downloading a release or installing dependencies is separate from the app's offline analysis.
- A public GitHub issue, screenshot, blog, or copied command is public disclosure. Review it yourself; masking is a safeguard, not proof that every possible personal detail is gone.

## Publication policy

This repository and its release packages must not contain a contributor's raw device logs, diagnostic archives, real device/coordinator identifiers, pairing data, personal account details, private keys, local home paths, or unrelated files. Examples use placeholders and obviously synthetic identifiers. The build packages an explicit file allowlist and excludes source checkout metadata, build caches, extended attributes, resource forks, and diagnostic files.

`scripts/privacy_audit.py` catches several high-risk input patterns without echoing their values. It is an aid to manual review, not a complete detector of personal information. Security reports should follow [SECURITY.md](SECURITY.md).

## 中文摘要

本工具沒有帳號系統、追蹤分析、診斷上傳或自動更新服務。裝置識別碼、你選取的本機日誌及明確啟動的短時間日誌串流，都只在本機用於當次操作；不另外保存原始日誌、不自動匯出手機診斷副本、不讀取照片／訊息內容、不索取 Apple 帳號密碼，也不列出全部已安裝 App。

原始日誌可能包含其他私人資訊；請只選取你有權查看的檔案。歷史日誌不能保證裝置目前仍有相同問題。完整裝置識別碼仍需傳給本機通訊工具，具有足夠權限的本機程式可能看得到程序參數。macOS、iOS 及第三方工具可能寫入各自的系統紀錄或信任狀態，因此無法承諾整台電腦／手機完全零寫入。關閉程式會釋放當次記憶體，不代表密碼學等級的記憶體抹除。

公開專案與 Release 不包含真實裝置識別碼、回復工作 UUID、原始日誌、配對資料、個人帳號、本機路徑或私密金鑰。公開截圖、issue 或命令前仍請自行檢閱；請勿上傳原始 `.logarchive`。

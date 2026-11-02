# App Restore Rescue

[English](README.md) · [下載 Release](https://github.com/dAAAb/app-restore-rescue/releases/latest) · [隱私說明](PRIVACY.md)

一個開源 macOS 小工具，協助調查 iPhone 移轉後 App 卡住的情況，並在明確確認後，**只對選定的一支 USB 裝置、選定的一個 App 提出卸載請求**。

起因是一個真實案例：換機後找不到 App，App Store 的雲朵下載按鈕轉一下就恢復原狀。日誌顯示 `ASDErrorDomain Code=506`、`Duplicate restoring request`。針對該 App 提出卸載請求並完成後，使用者成功重新下載。這是一個已確認成功的案例，不代表所有下載失敗都能用相同方法修復。

**卸載可能刪除該 App 的本機文件、草稿及尚未同步的資料。** 本工具提供有確認步驟的卸載操作，不能保證保留 App 資料，也不是通用 iPhone 修復程式。

## 下載與需求

- macOS 13 以上，Apple silicon 或 Intel Mac。
- 以 USB 連接、已解鎖，且你已信任這台電腦的 iPhone。
- 由你自行安裝的 `ideviceinstaller` **1.2 以上**，以及隨附的 `libimobiledevice` 工具。本工具不會自動安裝或更新元件。

如果你已使用 Homebrew，可自行執行：

```sh
brew install ideviceinstaller
```

Homebrew 會處理 `libimobiledevice`、`libplist`、`libzip` 等相依套件；請自行檢閱它提出的變更。這是在 Mac 安裝工具，不是在 iPhone 安裝 App。參閱 [Homebrew 套件說明](https://formulae.brew.sh/formula/ideviceinstaller)及[上游專案](https://github.com/libimobiledevice/ideviceinstaller)。

從同一個 [GitHub Release](https://github.com/dAAAb/app-restore-rescue/releases/latest) 下載 `AppRestoreRescue-vX.Y.Z-macOS-universal.zip` 與 `SHA256SUMS.txt`。在下載目錄核對檔案後再解壓縮：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

ZIP 包含通用版 `.app`、中英說明、授權、隱私說明及公開版本資訊。**沒有附帶第三方裝置工具的執行檔**。

### macOS 的安全性提示

第一版僅有 **ad-hoc 簽章，未經 Apple Developer ID 簽署或公證**。此簽章能檢查程式包完整性，不能提供 Apple 驗證的發布者身分。macOS 可能在首次開啟時阻擋它。請先檢閱原始碼與下載來源，再決定是否開啟；若你選擇繼續，可依 Apple 說明，在有該選項時透過「隱私權與安全性 → 強制打開」批准這個 App。請勿全域停用 Gatekeeper；公司管理的 Mac 請遵循管理政策。[Apple 說明](https://support.apple.com/zh-tw/102445)

## 使用流程

1. 開啟工具並確認相依元件狀態。工具不會自動安裝任何東西。
2. 連接並解鎖目標 iPhone，重新整理 USB 裝置清單，再明確選取裝置。畫面會遮蔽裝置識別碼；如果無法確認是哪一支，請先拔除其他手機。
3. 選取已有的本機日誌，或明確啟動短時間的本機監看。監看開始後，在 iPhone 上**手動按一次該 App 的雲朵下載按鈕**。這次重試可能成功並開始安裝；監看功能本身不會按下載。捕捉到相關事件就停止；若已有適用日誌，不必重現。
4. 檢閱候選 App 的識別碼與對應的回復錯誤。歷史日誌只是調查線索，不能證明現在仍卡住；單憑按鈕轉圈也無法確診。你也可以輸入已自行核實的 Bundle ID。
5. 檢查所選目標。工具只查詢該 App，不列出全部已安裝 App；查不到 App 紀錄本身不代表一定有殘留回復工作。
6. 若決定嘗試移除，先核對裝置與 Bundle ID、確認了解本機資料可能被刪除，再輸入完整 Bundle ID 進行確認。工具只送出這一筆請求，不會自動重試、改選其他裝置或批次卸載。
7. 收到卸載完成結果後，回到 iPhone 的 App Store 自行重新下載。**只有重新下載成功，才能確認原本的問題已解除。**

介面支援繁體中文與英文。X 的 Bundle ID 是 `com.atebits.Tweetie2`，可由 [X 官方網站關聯設定](https://x.com/.well-known/apple-app-site-association)確認。其他 App 請先核實識別碼，不要從顯示名稱猜測。

## 工具能做與不能保證的事

本工具協助尋找日誌中明確的回復錯誤，並向 iPhone 安裝服務提出指定 Bundle ID 的卸載請求。它不直接修改 App 資料庫、不按工作 UUID 呼叫私有取消介面，也不會修復全部 App 或保證清除孤立的回復工作。

`Uninstall: Complete` 表示裝置工具回報請求已完成，不代表已測試重新下載。若送出卸載後逾時，結果可能尚未確定；應先檢查手機狀態，再決定是否嘗試其他操作。

如果找不到 iPhone，請確認 USB、解鎖、信任狀態，以及工具執行環境的限制。沙盒或受限的遠端環境可能無法存取 macOS 裝置服務，即使手機實際已連接。請勿為此更改全域安全性設定。

## 隱私界線

- 沒有分析追蹤、當機報告上傳、帳號登入、雲端後端或自動更新服務。
- 不會自動匯出手機診斷資料；由你選擇本機檔案或啟動本機監看。
- 原始日誌與完整裝置識別碼只在本機記憶體中用於你要求的操作，不另存為 App 日誌檔，也不放進公開回報。
- 畫面遮蔽裝置識別碼；公開專案使用佔位文字或明顯的虛構測試值。
- 不透過 shell 解譯 Bundle ID、不使用 `sudo`、不自動安裝相依套件、不安裝第三方 IPA。
- 工具需要存取 macOS 裝置服務，發布版本沒有啟用 App Sandbox entitlement。

macOS、iOS 與你自行安裝的裝置工具仍可能維護它們自己的系統日誌或信任紀錄；本專案不能保證作業系統完全不寫入任何資料。分享截圖或診斷資料前，請閱讀完整的 [PRIVACY.md](PRIVACY.md)。

## 命令列替代方法

也可以直接使用上游工具，資料刪除風險相同。先以 `idevice_id -l` 在本機核對目標裝置，請勿公開該輸出。將以下佔位文字替換為你要處理的裝置識別碼：

```sh
DEVICE_UDID='YOUR_IPHONE_UDID'
APP_BUNDLE_ID='com.atebits.Tweetie2'
ideviceinstaller -u "$DEVICE_UDID" uninstall "$APP_BUNDLE_ID"
```

送出請求不需要先在主畫面找到 App 圖示，但手機是否接受紀錄缺失的 App 卸載，仍取決於當時狀態。本 GUI 要求 `ideviceinstaller` 1.2 以上，避免混用不同版本的參數語法。

## 開發與發布

Swift package 沒有第三方 Swift 相依套件。測試使用虛構輸入與模擬裝置工具，不應連接真實 iPhone 或執行真實卸載。

開發者在 **Swift／Xcode 工具鏈已安裝並設定完成**的 Mac 上，可執行：

```sh
swift test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/privacy_audit.py
bash scripts/build-release.sh 1.0.0
```

建置腳本只供開發者與 CI 使用：分別編譯 arm64、x86_64，產生 ad-hoc 簽署的 App，驗證架構，再只封裝允許清單中的程式與文件。ZIP 中繼資料會正規化；不同 SDK／編譯器仍可能產生不同二進位檔，不宣稱跨工具鏈逐位元一致。

GitHub Actions 會執行測試與發布資料檢查。推送 `v主版號.次版號.修訂號` 標籤後，建立包含通用版 ZIP 與 SHA-256 校驗檔的 **Release 草稿**。維護者檢閱實際產物、確認介面與隱私界線後，才將該版本公開。CI 不使用個人簽章憑證、鑰匙圈、手機或本機診斷副本；只有 Release 工作有寫入權限，PR 檢查只有讀取權限。

發布前仍須人工檢閱檔案；自動檢查無法證明任意文字都沒有個資。公開 issue 只放最少量、已去識別化的描述，參閱 [SECURITY.md](SECURITY.md)。

## 背景與致謝

- [繁體中文案例](docs/case-study.zh-TW.md) · [English case study](docs/case-study.en.md)
- [Apple：無法下載或更新 App](https://support.apple.com/zh-tw/102632)
- [症狀相近的親測文章與不同結果回報](https://www.ptt.cc/bbs/iOS/M.1790676452.A.A8E.html)（[可讀鏡像](https://pttdigits.com/iOS/1gkutagE)）。本工具沒有實作該文章的 IPA 安裝後再卸載流程。
- [ideviceinstaller](https://github.com/libimobiledevice/ideviceinstaller) 與 [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) 提供裝置通訊功能，其授權與責任各自獨立。

本專案原始程式碼採 MIT 授權。App Restore Rescue 與 Apple、X、libimobiledevice 專案沒有隸屬或背書關係。

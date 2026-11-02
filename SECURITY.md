# Security

## Supported scope

Only the latest released version receives fixes. App Restore Rescue is a small community utility, not an Apple-supported recovery service. An uninstall request can delete local app data. A completed request is not proof that the original App Store failure is fixed.

Important safeguards are explicit device selection, exact bundle validation, argument-array process execution, local-only analysis, a typed confirmation before one uninstall, and no automatic retry or bulk action. Tests must use mocks and synthetic data, never an attached user's phone.

## Report a vulnerability privately

If the repository's **Security → Report a vulnerability** option is available, use [GitHub private vulnerability reporting](https://github.com/dAAAb/app-restore-rescue/security/advisories/new). Do not put exploit details, account data, real device identifiers, pairing records, raw phone logs, or private keys in a public issue.

If private reporting is unavailable, open a public issue containing only a minimal request for a private reporting channel, without sensitive details. Maintainers should establish that channel before asking for reproduction material. Do not attach diagnostic archives by default.

For ordinary bugs, report the app version, macOS version/architecture, action attempted, and a sanitized error category. No serial number, Apple Account, device name, UDID, or full log is needed to start.

## Contributor and release rules

- Never add real diagnostic archives, personal identifiers, local machine paths, credentials, or pairing records to fixtures, documentation, Git history, screenshots, or release assets.
- Keep device actions allowlisted and single-target. Do not add arbitrary shell execution, automatic dependency installation, broad resets, background uninstall, or automatic retries.
- Do not equate a nearby bundle identifier in a log with a proven association. Candidate detection must be conservative and user-reviewed.
- Keep CI tests independent of real devices. Do not use `pull_request_target` to execute contributor-controlled code with write permissions or secrets.
- Review action updates, keep actions pinned to commit hashes, and limit release credentials to the publishing job.
- Published app bundles are ad-hoc signed unless release notes explicitly state otherwise. Do not describe an ad-hoc signature as Developer ID signing or notarization.
- Run tests and `python3 scripts/privacy_audit.py`, then inspect the exact staged files and release ZIP before publication. An automated scan is not a complete privacy review.

## 中文

安全漏洞請優先使用 GitHub 的私人漏洞回報功能；若未啟用，先以不含敏感資訊的 issue 請維護者提供私人管道。請勿公開原始手機日誌、裝置識別碼、配對紀錄、Apple 帳號、個人路徑或金鑰。

一般錯誤只需提供工具版本、macOS 版本／架構、操作與已去識別化的錯誤類別。卸載可能刪除本機資料；請勿將工具成功回覆誤當作 App Store 已恢復的證明。請勿全域停用 macOS 的安全保護。

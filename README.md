# App Restore Rescue

[繁體中文](README.zh-TW.md) · [Download a release](https://github.com/dAAAb/app-restore-rescue/releases/latest) · [Privacy](PRIVACY.md)

A small, open-source macOS utility for investigating iPhone apps stuck after migration, and requesting the removal of **one explicitly selected app on one explicitly selected USB device**.

It was created after an app disappeared from both the Home Screen and the iPhone app list, while App Store redownload requests failed with `ASDErrorDomain Code=506`, `Duplicate restoring request`. A targeted uninstall request completed, and the user could then download the app normally. That is one confirmed recovery, not a guarantee for every download failure.

**Uninstalling can delete the selected app's local documents, drafts, and other unsynced data.** This is an uninstall tool with safeguards, not a data-preserving cache cleaner or a general iPhone repair program.

## Download and requirements

- macOS 13 or newer, on Apple silicon or Intel.
- A USB-connected iPhone, unlocked, with the computer already trusted by you.
- `ideviceinstaller` **1.2 or newer** and its companion `libimobiledevice` tools, installed separately by you. The app does not install or update software.

If you already use Homebrew, the dependency command is:

```sh
brew install ideviceinstaller
```

Homebrew handles dependencies such as `libimobiledevice`, `libplist`, and `libzip`. Review Homebrew's proposed changes yourself. This installation is on the Mac; it does not install an iPhone app. See the [Homebrew formula](https://formulae.brew.sh/formula/ideviceinstaller) and [upstream tool](https://github.com/libimobiledevice/ideviceinstaller).

Download `AppRestoreRescue-vX.Y.Z-macOS-universal.zip` and `SHA256SUMS.txt` from the same [GitHub Release](https://github.com/dAAAb/app-restore-rescue/releases/latest). In the download directory, verify the ZIP before extracting it:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The ZIP contains a universal `.app`, this documentation, the license, privacy information, and a build revision. The third-party device tools are **not bundled**.

### macOS security prompt

The first release is **ad-hoc signed, not Apple Developer ID signed and not notarized**. The signature checks bundle integrity; it does not establish an Apple-verified publisher identity. macOS may block it on first launch. Review the source and release provenance before deciding whether to open it. If you choose to proceed, follow Apple's per-app **Privacy & Security → Open Anyway** procedure when available. Do not disable Gatekeeper globally. If an organization manages your Mac, follow its policy. [Apple's explanation](https://support.apple.com/en-us/102445)

## Use

1. Open the app and check its dependency status. Nothing is installed automatically.
2. Connect and unlock the intended iPhone. Refresh the USB device list and explicitly select the device. The interface masks its identifier; disconnect other phones if you cannot confidently distinguish them.
3. Investigate using an existing local log, or start a short local monitoring session. With monitoring active, **manually press the affected app's cloud-download button once** on the iPhone. That retry may succeed and start installing the app; monitoring itself does not press the button. Stop when the relevant event has been captured. Existing logs do not require another download attempt.
4. Review any candidate app identifier and the matching restore-error evidence. A historical log match is a lead, not proof the problem is still present. A spinning download button by itself is not a diagnosis. You may also enter a bundle identifier that you have independently verified.
5. Check the selected target. This queries the selected app only, not every installed app. A missing app record does not prove an orphaned restore exists.
6. If you decide to try removal, review the selected device and bundle identifier, acknowledge local-data loss, and type the exact bundle identifier in the confirmation. Only that one target is submitted. The app does not automatically retry, switch devices, or uninstall a batch.
7. After a successful uninstall result, return to the iPhone's App Store and redownload the app yourself. **Only a successful redownload confirms the original symptom is resolved.**

The interface supports English and Traditional Chinese. X's known bundle identifier is `com.atebits.Tweetie2`, as published in [X's own associated-domain file](https://x.com/.well-known/apple-app-site-association). Do not guess another app's identifier from its display name.

## What it can and cannot establish

The utility helps find explicit restore-related failures in logs and can ask the iPhone's installation service to uninstall a selected bundle ID. It does not directly edit an app database, cancel a private coordinator by UUID, repair all apps, or guarantee that an orphaned recovery job has been removed.

`Uninstall: Complete` means the device tool reported completion. It does not mean App Store redownload has been tested. A timeout after submitting an uninstall means the outcome may be unknown: inspect the phone before considering another attempt.

If the app cannot see the iPhone, check the USB cable, unlock/trust state, and the environment running the tool. A sandbox or restricted remote environment can block access to macOS's device service even while the phone is connected. Do not change global security settings to work around this.

## Privacy boundaries

- No analytics, crash-report upload, account login, cloud backend, or automatic update service.
- No automatic export of phone diagnostics. You choose a local file or explicitly start local monitoring.
- Raw log content and full device identifiers are used locally in memory for the requested operation; they are not saved as app log files or included in public reports.
- Displayed device identifiers are masked. Public project examples use placeholders or synthetic values.
- No shell evaluation of a supplied bundle ID, no `sudo`, no automatic dependency installation, and no third-party IPA installation.
- The app must access macOS's device service; it is not distributed with the App Sandbox entitlement.

macOS, iOS, and the independently installed device tools may maintain their own system logs or trust records. This project cannot promise that the operating systems make zero writes. See [PRIVACY.md](PRIVACY.md) for the complete boundary, especially before sharing screenshots or diagnostics.

## Manual alternative

You can use the upstream command-line tool directly. This is the same class of operation and has the same local-data deletion risk. Verify the device identifier privately using `idevice_id -l`; do not post that output publicly. Replace the placeholder with the exact device you intend to target:

```sh
DEVICE_UDID='YOUR_IPHONE_UDID'
APP_BUNDLE_ID='com.atebits.Tweetie2'
ideviceinstaller -u "$DEVICE_UDID" uninstall "$APP_BUNDLE_ID"
```

The command does not require a Home Screen icon to exist. Whether the iPhone accepts removal of an app with a missing record depends on its current state. The tool supports older `ideviceinstaller` syntax upstream, but this GUI requires version 1.2+ to keep its invocation contract small and testable.

## Development and releases

The Swift package has no third-party Swift dependencies. Unit tests use synthetic inputs and mock device tools; they must never connect to a real iPhone or invoke real uninstall commands.

On a development Mac whose Swift/Xcode toolchain is **already installed and configured**:

```sh
swift test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/privacy_audit.py
bash scripts/build-release.sh 1.0.0
```

The build script is for developers and CI only. It compiles arm64 and x86_64 executables, creates an ad-hoc signed app, verifies both architectures, and packages only allowlisted app and documentation files. ZIP metadata is normalized. SDK/compiler changes can still change the binary; this is a repeatable build process, not a claim of cross-toolchain bit-for-bit reproducibility.

GitHub Actions runs tests and a publication-input audit. Pushing a `vMAJOR.MINOR.PATCH` tag creates a **draft release** with the universal ZIP and SHA-256 checksum. A maintainer reviews the exact artifact, checks the UI and privacy boundaries, and then publishes the release. No signing certificate, personal keychain, local diagnostic archive, or phone is used by CI. Release workflows have write permissions only in the release job; pull-request CI is read-only.

Before publishing, review all staged files in addition to running the audit. Automated checks cannot prove that arbitrary prose contains no personal information. Public issues must contain only minimal, sanitized descriptions; see [SECURITY.md](SECURITY.md).

## Background and credits

- [Case study: English](docs/case-study.en.md) · [繁體中文](docs/case-study.zh-TW.md)
- [Apple: If you can't download or update apps](https://support.apple.com/102632)
- [A closely related first-person report and mixed follow-up results](https://www.ptt.cc/bbs/iOS/M.1790676452.A.A8E.html) ([readable mirror](https://pttdigits.com/iOS/1gkutagE)). Its IPA-install-then-remove workaround is not implemented by this tool.
- [ideviceinstaller](https://github.com/libimobiledevice/ideviceinstaller) and [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) provide the device communication functionality. Their licenses and responsibilities remain separate from this project.

App Restore Rescue's original source is MIT licensed. It is not affiliated with or endorsed by Apple, X, or the libimobiledevice project.

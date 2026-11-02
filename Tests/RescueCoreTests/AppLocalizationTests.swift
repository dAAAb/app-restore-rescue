import Foundation
import XCTest
@testable import RescueCore

final class AppLocalizationTests: XCTestCase {
    func testSystemLanguageMatchingSupportsRegionsAndScripts() {
        let examples: [([String], AppLanguage)] = [
            (["en-US"], .english),
            (["en-GB"], .english),
            (["ja-JP"], .japanese),
            (["ko-KR"], .korean),
            (["zh-Hant-TW"], .traditionalChinese),
            (["zh-TW"], .traditionalChinese),
            (["zh-HK"], .traditionalChinese)
        ]
        for (preferences, language) in examples {
            XCTAssertEqual(AppLanguage.resolve(preferredLanguages: preferences), language, preferences.joined(separator: ","))
        }
    }

    func testPreferenceOrderAndUnsupportedLanguageFallback() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR", "ja-JP", "en-US"]), .japanese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["ko-KR", "ja-JP"]), .korean)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-Hant", "en"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: []), .english)
    }

    func testApplicationUsesBundlePreferenceAndIgnoresProductionOverrides() {
        XCTAssertEqual(AppLanguage.forApplication(preferredLocalizations: ["ja"], arguments: []), .japanese)
        XCTAssertEqual(AppLanguage.forApplication(preferredLocalizations: ["ko"], arguments: ["--english"]), .korean)
        XCTAssertEqual(AppLanguage.forApplication(preferredLocalizations: ["zh-Hant"], arguments: ["--demo-language=en"]), .traditionalChinese)
    }

    func testDemoOverridesRemainRestrictedToSyntheticMode() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage.forApplication(preferredLocalizations: ["en"], arguments: ["--demo", "--demo-language=" + language.rawValue]), language)
        }
        XCTAssertEqual(AppLanguage.forApplication(preferredLocalizations: ["ja"], arguments: ["--demo", "--english"]), .english)
        XCTAssertEqual(AppLanguage.forApplication(preferredLocalizations: ["ko"], arguments: ["--demo", "--demo-language=invalid"]), .korean)
    }

    func testEveryMessageHasACompleteTranslation() {
        for language in AppLanguage.allCases {
            for message in AppMessage.allCases {
                let value = language.text(message)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language.rawValue): \(message.rawValue)")
                // Product names are deliberately unchanged. Every other entry must be translated,
                // so a missing row cannot silently fall back to the English safety warning.
                if language != .english && message != .phoneLabel {
                    XCTAssertNotEqual(value, AppLanguage.english.text(message), "\(language.rawValue): \(message.rawValue)")
                }
            }
        }
    }

    func testDynamicCountsAndDiagnosticLiteralsSurviveTranslation() {
        for language in AppLanguage.allCases {
            let summary = language.scanSummary(matched: 7, unattributed: 2)
            XCTAssertTrue(summary.contains("7"))
            XCTAssertTrue(summary.contains("2"))
            XCTAssertFalse(summary.contains("%"))
            let requests = language.matchingRequests(3)
            XCTAssertTrue(requests.contains("3"))
            XCTAssertFalse(requests.contains("%"))
            XCTAssertTrue(language.text(.scanScope).contains("ASDErrorDomain 506"))
            XCTAssertTrue(language.text(.scanScope).contains("Duplicate restoring request"))
            XCTAssertTrue(language.text(.bundleHelp).contains("com.atebits.Tweetie2"))
        }
    }
}

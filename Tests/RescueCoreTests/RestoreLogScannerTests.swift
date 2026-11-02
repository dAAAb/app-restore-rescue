import Foundation
import XCTest
@testable import RescueCore

final class RestoreLogScannerTests: XCTestCase {
    private let failure = "Error Domain=ASDErrorDomain Code=506 \"Duplicate restoring request\""
    private func line(_ time: String, _ message: String, pid: Int = 100) -> String {
        "2026-01-01 \(time).000000+0000 appstored[\(pid):aa] [com.apple.appstored:General] \(message)"
    }
    private func start(_ request: String, _ bundle: String) -> String {
        "[PurchaseService]: [\(request)] Starting purchase of 123456789:\(bundle) by com.apple.AppStore"
    }
    private func end(_ request: String) -> String { "[PurchaseService]: [\(request)] Purchase completed with error: \(failure)" }

    func testInterleavedRequestsAreBoundByExactRequestAndPID() {
        let log = [
            line("12:00:00", start("A1B2C3D4", "com.example.reader")),
            line("12:00:01", start("B1B2C3D4", "com.example.writer")),
            line("12:00:02", end("A1B2C3D4")),
            line("12:00:03", end("B1B2C3D4")),
            line("12:00:04", end("A1B2C3D4"))
        ].joined(separator: "\n")
        let result = RestoreLogScanner.scan(log)
        XCTAssertEqual(result.matchingFailureCount, 3)
        XCTAssertEqual(result.candidates.map(\.bundle.rawValue), ["com.example.reader", "com.example.writer"])
        XCTAssertEqual(result.candidates.map(\.failureCount), [2, 1])
        XCTAssertEqual(result.ambiguousFailureCount, 0)
    }

    func testWrongPIDOldTimeAndUnknownRequestAreNotGuessed() {
        let log = [
            line("12:00:00", start("A1B2C3D4", "com.example.reader")),
            line("12:00:01", end("A1B2C3D4"), pid: 101),
            line("12:11:00", end("A1B2C3D4")),
            line("12:01:00", end("FFFFFFFF"))
        ].joined(separator: "\n")
        let result = RestoreLogScanner.scan(log)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.ambiguousFailureCount, 3)
    }

    func testGeneric506IsNotRestoreError() {
        let log = line("12:00:00", "[BUYA1B2C3D4/com.example.reader:123456789] Error Domain=ASDErrorDomain Code=506 \"Duplicate request\"")
        XCTAssertEqual(RestoreLogScanner.scan(log).matchingFailureCount, 0)
    }

    func testSameEventContextCanAttributeWithoutNearbyStart() {
        let log = line("12:00:00", "[BUYA1B2C3D4/com.example.reader:123456789] \(failure)")
        let result = RestoreLogScanner.scan(log)
        XCTAssertEqual(result.candidates.first?.bundle.rawValue, "com.example.reader")
        XCTAssertEqual(result.ambiguousFailureCount, 0)
    }

    func testMissingAndForeignProcessMetadataNeverProduceCandidates() throws {
        let message = "[BUYA1B2C3D4/com.example.reader:123456789] \(failure)"
        let json = String(data: try JSONSerialization.data(withJSONObject: ["eventMessage": message, "process": "otherprocess", "processID": 100]), encoding: .utf8)!
        let copied = "2026-01-01 12:00:00.000000+0000 otherprocess[200:aa] copied appstored[100:aa] \(message)"
        let result = RestoreLogScanner.scan([message, json, copied].joined(separator: "\n"))
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.ambiguousFailureCount, 3)
    }

    func testReusedRequestWithConflictingBundlesIsAmbiguous() {
        let log = [
            line("12:00:00", start("A1B2C3D4", "com.example.reader")),
            line("12:00:01", start("A1B2C3D4", "com.example.writer")),
            line("12:00:02", end("A1B2C3D4"))
        ].joined(separator: "\n")
        let result = RestoreLogScanner.scan(log)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.ambiguousFailureCount, 1)
    }

    func testMalformedAndSystemBundlesCannotBecomeCandidates() {
        let log = [
            line("12:00:00", "[BUYA1B2C3D4/com.example.*:123456789] \(failure)"),
            line("12:00:01", "[BUYA1B2C3D4/com.apple.AppStore:123456789] \(failure)"),
            line("12:00:02", "[BUYA1B2C3D4/com..reader:123456789] \(failure)")
        ].joined(separator: "\n")
        let result = RestoreLogScanner.scan(log)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.ambiguousFailureCount, 3)
    }

    func testNDJSONWithProcessImagePathAndTimestamp() throws {
        let events: [[String: Any]] = [
            ["eventMessage": start("A1B2C3D4", "com.example.reader"), "processImagePath": "/usr/libexec/appstored", "processID": 100, "timestamp": "2026-01-01 12:00:00.000000+0000"],
            ["eventMessage": end("A1B2C3D4"), "processImagePath": "/usr/libexec/appstored", "processID": 100, "timestamp": "2026-01-01 12:00:01.000000+0000"]
        ]
        let json = try events.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }.joined(separator: "\n")
        XCTAssertEqual(RestoreLogScanner.scan(json).candidates.first?.bundle.rawValue, "com.example.reader")
    }

    func testBSDLiveLogTimestamp() {
        let log = "Nov  2 12:00:00 example-phone appstored[100] <Notice>: \(start("A1B2C3D4", "com.example.reader"))\nNov  2 12:00:01 example-phone appstored[100] <Notice>: \(end("A1B2C3D4"))"
        XCTAssertEqual(RestoreLogScanner.scan(log).candidates.first?.bundle.rawValue, "com.example.reader")
    }

    func testLiveLogProcessImageSuffix() {
        let log = "Nov  2 12:00:00 appstored(StoreFoundation)[100] <Notice>: \(start("A1B2C3D4", "com.example.reader"))\nNov  2 12:00:01 appstored(StoreFoundation)[100] <Notice>: \(end("A1B2C3D4"))"
        XCTAssertEqual(RestoreLogScanner.scan(log).candidates.first?.bundle.rawValue, "com.example.reader")
    }

    func testNoFailureDoesNotInventCandidate() {
        XCTAssertTrue(RestoreLogScanner.scan(line("12:00:00", start("A1B2C3D4", "com.example.reader"))).candidates.isEmpty)
    }
}

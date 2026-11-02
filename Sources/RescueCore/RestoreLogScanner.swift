import Foundation

public struct RestoreCandidate: Identifiable, Equatable, Sendable {
    public let bundle: BundleIdentifier
    public let failureCount: Int
    public var id: String { bundle.rawValue }
}

public struct LogScanResult: Equatable, Sendable {
    public let candidates: [RestoreCandidate]
    public let ambiguousFailureCount: Int
    public let matchingFailureCount: Int
    public var isEmpty: Bool { candidates.isEmpty }
}

/// Recognizes only the specific restore-duplicate error. It never assigns errors to the nearest app.
public enum RestoreLogScanner {
    private struct Event {
        let message: String
        let processID: String?
        let time: Date?
        let isAppStored: Bool
    }
    private struct Start { let bundle: BundleIdentifier; let time: Date }
    private static let startPattern = #"\[PurchaseService\]:\s*\[([A-Fa-f0-9]{8})\]\s+Starting purchase of [0-9]+:([A-Za-z][A-Za-z0-9_.-]+)\s+by\s"#
    private static let requestPattern = #"\[PurchaseService\]:\s*\[([A-Fa-f0-9]{8})\]"#
    private static let directPattern = #"\bBUY[A-Fa-f0-9]{8}/([A-Za-z][A-Za-z0-9_.-]+):[0-9]+\b"#

    public static func scan(_ contents: String) -> LogScanResult {
        var starts: [String: Start] = [:]
        var conflictingRequests: Set<String> = []
        var counts: [BundleIdentifier: Int] = [:]
        var ambiguous = 0, total = 0
        let lines: [String]
        if let data = contents.data(using: .utf8),
           let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            lines = array.compactMap { object in
                guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
                return String(data: data, encoding: .utf8)
            }
        } else { lines = contents.components(separatedBy: .newlines) }

        for line in lines {
            guard let event = event(from: line) else { continue }
            if event.isAppStored, let match = captures(startPattern, in: event.message).first,
               let pid = event.processID, let time = event.time,
               let bundle = try? BundleIdentifier(match[1]) {
                let key = pid + ":" + match[0].uppercased()
                if let previous = starts[key], abs(time.timeIntervalSince(previous.time)) <= 600 {
                    if previous.bundle != bundle { conflictingRequests.insert(key) }
                } else { conflictingRequests.remove(key) }
                starts[key] = Start(bundle: bundle, time: time)
            }
            guard event.message.contains("ASDErrorDomain"),
                  event.message.range(of: #"\bCode\s*=\s*506\b"#, options: .regularExpression) != nil,
                  event.message.contains("Duplicate restoring request") else { continue }
            total += 1
            guard event.isAppStored else { ambiguous += 1; continue }
            let direct = Set(captures(directPattern, in: event.message).compactMap { try? BundleIdentifier($0[0]) })
            if direct.count == 1, let bundle = direct.first {
                counts[bundle, default: 0] += 1
                continue
            }
            if direct.count > 1 { ambiguous += 1; continue }
            guard let request = captures(requestPattern, in: event.message).first?.first,
                  let pid = event.processID, let time = event.time,
                  !conflictingRequests.contains(pid + ":" + request.uppercased()),
                  let start = starts[pid + ":" + request.uppercased()],
                  time.timeIntervalSince(start.time) >= 0,
                  time.timeIntervalSince(start.time) <= 600 else { ambiguous += 1; continue }
            counts[start.bundle, default: 0] += 1
        }
        return LogScanResult(candidates: counts.map { RestoreCandidate(bundle: $0.key, failureCount: $0.value) }
            .sorted { $0.bundle.rawValue < $1.bundle.rawValue },
            ambiguousFailureCount: ambiguous, matchingFailureCount: total)
    }

    private static func event(from line: String) -> Event? {
        guard !line.isEmpty else { return nil }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
           let data = line.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let message = object["eventMessage"] as? String {
            let process = (object["process"] as? String) ?? (object["processImagePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            let pid: String?
            if let value = object["processID"] as? NSNumber { pid = value.stringValue }
            else { pid = object["processID"] as? String }
            return Event(message: message, processID: pid, time: (object["timestamp"] as? String).flatMap(date), isAppStored: process == "appstored")
        }
        // A malformed JSON line is not reinterpreted as trustworthy plain-text event metadata.
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("{") { return nil }
        let cleaned = line.replacingOccurrences(of: #"\u001B\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
        let stamp = captures(#"^(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)"#, in: cleaned).first?.first
            ?? captures(#"^([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?)"#, in: cleaned).first?.first
        let header = stamp.map { String(cleaned.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) } ?? cleaned
        // Only a process in the header counts. An appstored[...] quote inside another process's message does not.
        let headerPattern = stamp == nil ? #"^appstored\[([0-9]+)(?::[^\]]*)?\]"# : #"^(?:[A-Za-z0-9_.-]+\s+)?appstored\[([0-9]+)(?::[^\]]*)?\]"#
        let pid = captures(headerPattern, in: header).first?.first
        return Event(message: cleaned, processID: pid, time: stamp.flatMap(date), isAppStored: pid != nil)
    }

    private static func captures(_ pattern: String, in string: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = string as NSString
        return expression.matches(in: string, range: NSRange(location: 0, length: text.length)).map { match in
            (1..<match.numberOfRanges).map { text.substring(with: match.range(at: $0)) }
        }
    }

    private static func date(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: value) { return parsed }
        iso.formatOptions = [.withInternetDateTime]
        if let parsed = iso.date(from: value) { return parsed }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd HH:mm:ss.SSSSSSZ", "yyyy-MM-dd HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss", "MMM d HH:mm:ss.SSSSSS", "MMM d HH:mm:ss"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) { return parsed }
        }
        return nil
    }
}

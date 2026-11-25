import Foundation

public enum AgyStatusLineParser {
    private struct RawPayload: Decodable {
        let quota: [String: RawBucket]?
    }

    private struct RawBucket: Decodable {
        let remaining_fraction: Double?
        let reset_time: String?
        let reset_in_seconds: Double?
        let disabled: Bool?
    }

    public static func parse(line: String, now: Date = Date()) -> QuotaSnapshot? {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONDecoder().decode(RawPayload.self, from: data),
              let quota = payload.quota else {
            return nil
        }

        let fiveHour = parseBucket(quota[QuotaWindowKind.fiveHour.bucketKey], now: now)
        let weekly = parseBucket(quota[QuotaWindowKind.weekly.bucketKey], now: now)

        guard fiveHour != nil || weekly != nil else {
            return nil
        }

        return QuotaSnapshot(timestamp: now, fiveHour: fiveHour, weekly: weekly)
    }

    public static func parseLatest(fromNDJSON text: String, now: Date = Date()) -> QuotaSnapshot? {
        for rawLine in text.split(whereSeparator: \.isNewline).reversed() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if let snapshot = parse(line: trimmed, now: now) {
                return snapshot
            }
        }
        return nil
    }

    private static func parseBucket(_ raw: RawBucket?, now: Date) -> BucketReading? {
        guard let raw, raw.disabled != true, let fraction = raw.remaining_fraction else {
            return nil
        }

        let resetDate: Date?
        if let resetString = raw.reset_time {
            resetDate = parseISO8601(resetString)
        } else {
            resetDate = nil
        }

        let resolvedReset: Date
        if let resetDate {
            resolvedReset = resetDate
        } else if let seconds = raw.reset_in_seconds {
            resolvedReset = now.addingTimeInterval(seconds)
        } else {
            return nil
        }

        return BucketReading(remainingFraction: fraction, resetTime: resolvedReset)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

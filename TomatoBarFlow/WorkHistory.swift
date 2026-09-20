import Foundation

struct TBLockedWorkContent: Equatable {
    let current: String
    let recorded: String
}

enum TBWorkContent {
    static func lock(_ content: String, uncategorized: String) -> TBLockedWorkContent {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return TBLockedWorkContent(
            current: trimmed,
            recorded: trimmed.isEmpty ? uncategorized : trimmed
        )
    }
}

struct TBRecentWorkContents {
    private(set) var contents: [String]
    private let limit: Int

    init(stored: [String]?, fallback: [String], limit: Int = 5) {
        self.limit = limit
        var seen = Set<String>()
        contents = (stored ?? fallback)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(limit)
            .map { $0 }
    }

    mutating func record(_ content: String) {
        contents.removeAll { $0 == content }
        contents.insert(content, at: 0)
        contents = Array(contents.prefix(limit))
    }
}

struct TBLocalDay: Codable, Equatable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    static func < (lhs: TBLocalDay, rhs: TBLocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

struct TBWorkRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let content: String
    let startedAt: Date
    let endedAt: Date
    let durationMinutes: Int
    let startDay: TBLocalDay
}

struct TBWorkHistory {
    private(set) var records: [TBWorkRecord]

    init(data: Data?, now: Date, calendar: Calendar) {
        let decoded = (try? data.map { try JSONDecoder().decode([TBWorkRecord].self, from: $0) }) ?? []
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let oldestRetainedDay = TBLocalDay(date: yesterday, calendar: calendar)
        records = decoded.filter { $0.startDay >= oldestRetainedDay }
    }

    @discardableResult
    mutating func completeWork(content: String,
                               startedAt: Date,
                               endedAt: Date,
                               durationMinutes: Int,
                               calendar: Calendar) -> TBWorkRecord
    {
        let record = TBWorkRecord(
            id: UUID(),
            content: content,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMinutes: durationMinutes,
            startDay: TBLocalDay(date: startedAt, calendar: calendar)
        )
        records.append(record)
        return record
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(records)
    }

    func recentContents(limit: Int) -> [String] {
        var seen = Set<String>()
        return records
            .sorted { $0.endedAt > $1.endedAt }
            .compactMap { record in
                seen.insert(record.content).inserted ? record.content : nil
            }
            .prefix(limit)
            .map { $0 }
    }
}

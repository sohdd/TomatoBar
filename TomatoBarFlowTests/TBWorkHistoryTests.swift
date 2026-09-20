import XCTest
@testable import TomatoBarFlow

final class TBWorkHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    func testCompletingWorkCreatesOneRecordWithLockedDetails() throws {
        let startedAt = date(2026, 9, 20, 23, 50)
        let endedAt = date(2026, 9, 21, 0, 15)
        var history = TBWorkHistory(data: nil, now: startedAt, calendar: calendar)

        let record = history.completeWork(
            content: "TomatoBar 定制",
            startedAt: startedAt,
            endedAt: endedAt,
            durationMinutes: 25,
            calendar: calendar
        )

        XCTAssertEqual(history.records, [record])
        XCTAssertEqual(record.content, "TomatoBar 定制")
        XCTAssertEqual(record.startedAt, startedAt)
        XCTAssertEqual(record.endedAt, endedAt)
        XCTAssertEqual(record.durationMinutes, 25)
        XCTAssertEqual(record.startDay, TBLocalDay(year: 2026, month: 9, day: 20))
        XCTAssertNotNil(UUID(uuidString: record.id.uuidString))
    }

    func testLockingContentTrimsWhitespaceAndUsesUncategorizedForEmptyInput() {
        XCTAssertEqual(
            TBWorkContent.lock("  TomatoBar \n", uncategorized: "Uncategorized"),
            TBLockedWorkContent(current: "TomatoBar", recorded: "TomatoBar")
        )
        XCTAssertEqual(
            TBWorkContent.lock(" \n\t ", uncategorized: "Uncategorized"),
            TBLockedWorkContent(current: "", recorded: "Uncategorized")
        )
    }

    func testLoadingHistoryPermanentlyDropsRecordsBeforeYesterday() throws {
        var stored = TBWorkHistory(data: nil, now: date(2026, 9, 18, 12, 0), calendar: calendar)
        for day in 18 ... 20 {
            let startedAt = date(2026, 9, day, 9, 0)
            stored.completeWork(
                content: "Day \(day)",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(25 * 60),
                durationMinutes: 25,
                calendar: calendar
            )
        }

        let loaded = TBWorkHistory(
            data: try stored.encoded(),
            now: date(2026, 9, 20, 12, 0),
            calendar: calendar
        )

        XCTAssertEqual(loaded.records.map(\.content), ["Day 19", "Day 20"])
        XCTAssertEqual(try JSONDecoder().decode([TBWorkRecord].self, from: loaded.encoded()), loaded.records)
    }

    func testRecentContentsAreUniqueAndOrderedByLatestCompletion() {
        var history = TBWorkHistory(data: nil, now: date(2026, 9, 20, 8, 0), calendar: calendar)
        for (index, content) in ["Email", "Coding", "Email", "Planning"].enumerated() {
            let startedAt = date(2026, 9, 20, 9 + index, 0)
            history.completeWork(
                content: content,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(25 * 60),
                durationMinutes: 25,
                calendar: calendar
            )
        }

        XCTAssertEqual(history.recentContents(limit: 2), ["Planning", "Email"])
    }

    func testPersistedRecentContentsSurviveAfterTheirRecordsExpire() {
        var recent = TBRecentWorkContents(
            stored: ["Old project", "Email"],
            fallback: [],
            limit: 3
        )

        recent.record("Planning")
        recent.record("Email")

        XCTAssertEqual(recent.contents, ["Email", "Planning", "Old project"])
    }

    func testDailySummaryGroupsWorkByStartDayAndUsesRecordedDurations() {
        var history = TBWorkHistory(data: nil, now: date(2026, 9, 20, 8, 0), calendar: calendar)
        let work = [
            ("TomatoBar 定制", date(2026, 9, 20, 9, 10), 25),
            ("吃饭", date(2026, 9, 20, 12, 5), 25),
            ("TomatoBar 定制", date(2026, 9, 20, 23, 50), 40),
            ("TomatoBar 定制", date(2026, 9, 21, 9, 0), 25),
        ]
        for (content, startedAt, durationMinutes) in work {
            history.completeWork(
                content: content,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60)),
                durationMinutes: durationMinutes,
                calendar: calendar
            )
        }

        let summary = history.summary(for: TBLocalDay(year: 2026, month: 9, day: 20))

        XCTAssertEqual(summary.contentSummaries, [
            TBWorkContentSummary(content: "TomatoBar 定制", tomatoCount: 2, durationMinutes: 65),
            TBWorkContentSummary(content: "吃饭", tomatoCount: 1, durationMinutes: 25),
        ])
        XCTAssertEqual(summary.tomatoCount, 3)
        XCTAssertEqual(summary.durationMinutes, 90)
    }

    func testDailySummaryOrdersTimelineByStartTime() {
        var history = TBWorkHistory(data: nil, now: date(2026, 9, 20, 8, 0), calendar: calendar)
        for hour in [14, 9, 11] {
            let startedAt = date(2026, 9, 20, hour, 0)
            history.completeWork(
                content: "Hour \(hour)",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(25 * 60),
                durationMinutes: 25,
                calendar: calendar
            )
        }

        let summary = history.summary(for: TBLocalDay(year: 2026, month: 9, day: 20))

        XCTAssertEqual(summary.records.map(\.content), ["Hour 9", "Hour 11", "Hour 14"])
    }

    func testUpdatingRecordContentPreservesItsIdentityAndTimingAndRecalculatesSummary() throws {
        let startedAt = date(2026, 9, 20, 9, 0)
        var history = TBWorkHistory(data: nil, now: startedAt, calendar: calendar)
        let record = history.completeWork(
            content: "Planning",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(25 * 60),
            durationMinutes: 25,
            calendar: calendar
        )

        XCTAssertTrue(history.updateContent(of: record.id, to: "Coding"))

        let updatedRecord = try XCTUnwrap(history.records.first)
        XCTAssertEqual(updatedRecord.id, record.id)
        XCTAssertEqual(updatedRecord.content, "Coding")
        XCTAssertEqual(updatedRecord.startedAt, record.startedAt)
        XCTAssertEqual(updatedRecord.endedAt, record.endedAt)
        XCTAssertEqual(updatedRecord.durationMinutes, record.durationMinutes)
        XCTAssertEqual(updatedRecord.startDay, record.startDay)
        XCTAssertEqual(
            history.summary(for: record.startDay).contentSummaries,
            [TBWorkContentSummary(content: "Coding", tomatoCount: 1, durationMinutes: 25)]
        )

        let reloaded = TBWorkHistory(
            data: try history.encoded(),
            now: startedAt,
            calendar: calendar
        )
        XCTAssertEqual(reloaded.records, [updatedRecord])
    }

    func testDeletingRecordRemovesOnlyThatTomatoAndRecalculatesSummary() throws {
        let startedAt = date(2026, 9, 20, 9, 0)
        var history = TBWorkHistory(data: nil, now: startedAt, calendar: calendar)
        let deletedRecord = history.completeWork(
            content: "Coding",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(25 * 60),
            durationMinutes: 25,
            calendar: calendar
        )
        let retainedRecord = history.completeWork(
            content: "Coding",
            startedAt: startedAt.addingTimeInterval(30 * 60),
            endedAt: startedAt.addingTimeInterval(70 * 60),
            durationMinutes: 40,
            calendar: calendar
        )

        XCTAssertTrue(history.deleteRecord(withID: deletedRecord.id))

        let summary = history.summary(for: deletedRecord.startDay)
        XCTAssertEqual(summary.records, [retainedRecord])
        XCTAssertEqual(summary.tomatoCount, 1)
        XCTAssertEqual(summary.durationMinutes, 40)
        XCTAssertEqual(
            summary.contentSummaries,
            [TBWorkContentSummary(content: "Coding", tomatoCount: 1, durationMinutes: 40)]
        )

        let reloaded = TBWorkHistory(
            data: try history.encoded(),
            now: startedAt,
            calendar: calendar
        )
        XCTAssertEqual(reloaded.records, [retainedRecord])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

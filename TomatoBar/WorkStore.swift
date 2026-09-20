import Foundation
import SwiftUI

final class TBWorkStore: ObservableObject {
    private static let recordsKey = "workRecords"
    private static let recentContentsKey = "recentWorkContents"

    @Published private(set) var recentContents: [String] = []

    private let defaults: UserDefaults
    private var history: TBWorkHistory
    private var recentWorkContents: TBRecentWorkContents

    init(defaults: UserDefaults = .standard,
         now: Date = Date(),
         calendar: Calendar = .current)
    {
        self.defaults = defaults
        let history = TBWorkHistory(
            data: defaults.data(forKey: Self.recordsKey),
            now: now,
            calendar: calendar
        )
        self.history = history
        recentWorkContents = TBRecentWorkContents(
            stored: defaults.stringArray(forKey: Self.recentContentsKey),
            fallback: history.recentContents(limit: 5)
        )
        persist()
        refreshRecentContents()
    }

    func completeWork(content: String,
                      startedAt: Date,
                      endedAt: Date,
                      durationMinutes: Int,
                      calendar: Calendar)
    {
        history.completeWork(
            content: content,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMinutes: durationMinutes,
            calendar: calendar
        )
        recentWorkContents.record(content)
        persist()
        refreshRecentContents()
    }

    func summary(for day: TBLocalDay) -> TBDailyWorkSummary {
        history.summary(for: day)
    }

    func updateRecordContent(recordID: UUID, content: String, uncategorized: String) {
        let lockedContent = TBWorkContent.lock(content, uncategorized: uncategorized)
        applyHistoryChange { history in
            history.updateContent(of: recordID, to: lockedContent.recorded)
        }
    }

    func deleteRecord(recordID: UUID) {
        applyHistoryChange { history in
            history.deleteRecord(withID: recordID)
        }
    }

    private func applyHistoryChange(_ change: (inout TBWorkHistory) -> Bool) {
        var updatedHistory = history
        guard change(&updatedHistory) else {
            return
        }
        objectWillChange.send()
        history = updatedHistory
        persist()
    }

    private func persist() {
        guard let data = try? history.encoded() else {
            return
        }
        defaults.set(data, forKey: Self.recordsKey)
        defaults.set(recentWorkContents.contents, forKey: Self.recentContentsKey)
    }

    private func refreshRecentContents() {
        recentContents = recentWorkContents.contents
    }
}

import AppKit
import SwiftUI

final class TBDailySummaryWindowController: NSWindowController {
    init(store: TBWorkStore) {
        let rootView = TBDailySummaryView(store: store)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("DailySummary.title", comment: "Daily summary window title")
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 560, height: 400)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum TBDailySummaryDay: String, CaseIterable, Identifiable {
    case today
    case yesterday

    var id: Self { self }

    var label: String {
        switch self {
        case .today:
            return NSLocalizedString("DailySummary.today.label", comment: "Today label")
        case .yesterday:
            return NSLocalizedString("DailySummary.yesterday.label", comment: "Yesterday label")
        }
    }

    func localDay(now: Date, calendar: Calendar) -> TBLocalDay {
        let date: Date
        switch self {
        case .today:
            date = now
        case .yesterday:
            date = calendar.date(byAdding: .day, value: -1, to: now)!
        }
        return TBLocalDay(date: date, calendar: calendar)
    }
}

private final class TBDailySummaryClock: ObservableObject {
    @Published private(set) var now: Date

    private let calendar: Calendar
    private var midnightTimer: Timer?

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        scheduleMidnightRefresh()
    }

    deinit {
        midnightTimer?.invalidate()
    }

    private func scheduleMidnightRefresh() {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return
        }
        let timer = Timer(fire: startOfTomorrow, interval: 0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.now = Date()
            self.scheduleMidnightRefresh()
        }
        midnightTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

private struct TBDailySummaryView: View {
    @ObservedObject var store: TBWorkStore
    @StateObject private var clock = TBDailySummaryClock()
    @State private var selectedDay = TBDailySummaryDay.today

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $selectedDay) {
                ForEach(TBDailySummaryDay.allCases) { day in
                    Text(day.label).tag(day)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity, alignment: .center)

            if summary.records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        summarySection
                        timelineSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 400)
    }

    private var summary: TBDailyWorkSummary {
        store.summary(for: selectedDay.localDay(now: clock.now, calendar: calendar))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(emptyTitle)
                .font(.title3.weight(.semibold))
            Text(NSLocalizedString(
                "DailySummary.empty.message",
                comment: "Explanation shown when a day has no completed tomatoes"
            ))
            .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch selectedDay {
        case .today:
            return NSLocalizedString("DailySummary.empty.today", comment: "Empty state title for today")
        case .yesterday:
            return NSLocalizedString("DailySummary.empty.yesterday", comment: "Empty state title for yesterday")
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("DailySummary.summary.title", comment: "Summary section title"))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(summaryTotals)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(summary.contentSummaries) { item in
                    TBWorkSummaryBar(
                        summary: item,
                        largestTomatoCount: summary.contentSummaries.map(\.tomatoCount).max() ?? 1
                    )
                }
            }
        }
    }

    private var summaryTotals: String {
        String.localizedStringWithFormat(
            NSLocalizedString("DailySummary.summary.total", comment: "Daily tomato and minute totals"),
            summary.tomatoCount,
            summary.durationMinutes
        )
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("DailySummary.timeline.title", comment: "Timeline section title"))
                .font(.title3.weight(.semibold))

            ForEach(summary.records) { record in
                HStack(spacing: 16) {
                    Text(timeRange(for: record))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .leading)
                    Text(record.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("1🍅")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)

                Divider()
            }
        }
    }

    private func timeRange(for record: TBWorkRecord) -> String {
        "\(Self.timeFormatter.string(from: record.startedAt))–\(Self.timeFormatter.string(from: record.endedAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct TBWorkSummaryBar: View {
    let summary: TBWorkContentSummary
    let largestTomatoCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary.content)
                .lineLimit(1)

            GeometryReader { geometry in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: barWidth(available: geometry.size.width))
                    Text(detail)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }
            }
            .frame(height: 20)
        }
    }

    private var detail: String {
        String.localizedStringWithFormat(
            NSLocalizedString("DailySummary.summary.item", comment: "Tomato and minute totals for work content"),
            summary.tomatoCount,
            summary.durationMinutes
        )
    }

    private func barWidth(available: CGFloat) -> CGFloat {
        let detailAllowance: CGFloat = 150
        let chartWidth = max(80, available - detailAllowance)
        return chartWidth * CGFloat(summary.tomatoCount) / CGFloat(max(1, largestTomatoCount))
    }
}

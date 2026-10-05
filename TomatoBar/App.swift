import SwiftUI
import LaunchAtLogin

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

private let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) var appDelegate

    init() {
        TBStatusItem.shared = appDelegate
        LaunchAtLogin.migrateIfNeeded()
        logger.append(event: TBLogEventAppStart())
    }

    var body: some Scene {
        Settings {}
    }
}

class TBStatusItem: NSObject, NSApplicationDelegate {
    private var popover = NSPopover()
    private var statusBarItem: NSStatusItem?
    private var dailySummaryWindowController: TBDailySummaryWindowController?
    private var completionPrompt = NSPopover()
    static var shared: TBStatusItem!

    func applicationDidFinishLaunching(_: Notification) {
        let view = TBPopoverView()

        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = NSHostingView(rootView: view)
        if let contentViewController = popover.contentViewController {
            popover.contentSize.height = contentViewController.view.intrinsicContentSize.height
            popover.contentSize.width = 240
        }

        statusBarItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        statusBarItem?.button?.imagePosition = .imageLeft
        setIcon(name: .idle)
        statusBarItem?.button?.action = #selector(TBStatusItem.togglePopover(_:))
    }

    func setTitle(title: String?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.9
        paragraphStyle.alignment = NSTextAlignment.center

        let attributedTitle = NSAttributedString(
            string: title != nil ? " \(title!)" : "",
            attributes: [
                NSAttributedString.Key.font: digitFont,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
        )
        statusBarItem?.button?.attributedTitle = attributedTitle
    }

    func setIcon(name: NSImage.Name) {
        statusBarItem?.button?.image = NSImage(named: name)
    }

    func showPopover(_: AnyObject?) {
        if let button = statusBarItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    func showBreakPrompt(message: String, startBreak: @escaping () -> Void, skipBreak: @escaping () -> Void) {
        showCompletionPrompt(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            message: message,
            primaryLabel: NSLocalizedString("TBTimer.startBreak.label", comment: "Start break"),
            secondaryLabel: NSLocalizedString("TBTimer.skipBreak.label", comment: "Skip break"),
            primaryAction: startBreak,
            secondaryAction: skipBreak
        )
    }

    func showWorkPrompt(startWork: @escaping () -> Void) {
        showCompletionPrompt(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            message: NSLocalizedString("TBTimer.onRestFinish.prompt", comment: "Start new work prompt"),
            primaryLabel: NSLocalizedString("TBTimer.startWork.label", comment: "Start new work"),
            secondaryLabel: NSLocalizedString("TBTimer.later.label", comment: "Start later"),
            primaryAction: startWork,
            secondaryAction: { [weak self] in self?.dismissCompletionPrompt() }
        )
    }

    private func showCompletionPrompt(title: String, message: String,
                                      primaryLabel: String, secondaryLabel: String,
                                      primaryAction: @escaping () -> Void, secondaryAction: @escaping () -> Void) {
        guard let button = statusBarItem?.button else { return }
        closePopover(nil)
        dismissCompletionPrompt()

        completionPrompt.behavior = .applicationDefined
        let contentViewController = NSHostingController(rootView: TBCompletionPromptView(
            title: title,
            message: message,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ))
        completionPrompt.contentViewController = contentViewController
        completionPrompt.contentSize = NSSize(
            width: 240,
            height: contentViewController.view.intrinsicContentSize.height
        )
        completionPrompt.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        completionPrompt.contentViewController?.view.window?.makeKey()
    }

    func dismissCompletionPrompt() {
        completionPrompt.performClose(nil)
    }

    func showDailySummary(store: TBWorkStore) {
        closePopover(nil)
        if dailySummaryWindowController == nil {
            dailySummaryWindowController = TBDailySummaryWindowController(store: store)
        }
        dailySummaryWindowController?.present()
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if completionPrompt.isShown {
            completionPrompt.contentViewController?.view.window?.makeKey()
        } else if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
}

private struct TBCompletionPromptView: View {
    let title: String
    let message: String
    let primaryLabel: String
    let secondaryLabel: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TBTimerButton(
                    label: primaryLabel,
                    action: primaryAction
                )
                .keyboardShortcut(.defaultAction)
                TBTimerButton(
                    label: secondaryLabel,
                    action: secondaryAction
                )
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}

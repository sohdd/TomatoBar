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
    private var breakPrompt: NSPanel?
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
        dismissBreakPrompt()

        let panelSize = NSSize(width: 360, height: 150)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: TBBreakPromptView(
            message: message,
            startBreak: startBreak,
            skipBreak: skipBreak
        ))

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.maxX - panelSize.width - 16,
                y: visibleFrame.maxY - panelSize.height - 16
            ))
        }

        breakPrompt = panel
        panel.orderFrontRegardless()
    }

    func dismissBreakPrompt() {
        breakPrompt?.orderOut(nil)
        breakPrompt = nil
    }

    func showDailySummary(store: TBWorkStore) {
        closePopover(nil)
        if dailySummaryWindowController == nil {
            dailySummaryWindowController = TBDailySummaryWindowController(store: store)
        }
        dailySummaryWindowController?.present()
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
}

private struct TBBreakPromptView: View {
    let message: String
    let startBreak: () -> Void
    let skipBreak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.body)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(NSLocalizedString("TBTimer.skipBreak.label", comment: "Skip break"), action: skipBreak)
                Button(NSLocalizedString("TBTimer.startBreak.label", comment: "Start break"), action: startBreak)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 122)
    }
}

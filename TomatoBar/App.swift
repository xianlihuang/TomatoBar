import AppKit
import LaunchAtLogin
import SwiftUI

extension NSImage.Name {
    static let idle = Self("BarIconIdle")
    static let work = Self("BarIconWork")
    static let shortRest = Self("BarIconShortRest")
    static let longRest = Self("BarIconLongRest")
}

@main
struct TBApp: App {
    @NSApplicationDelegateAdaptor(TBStatusItem.self) private var appDelegate

    init() {
        LaunchAtLogin.migrateIfNeeded()
        logger.append(event: TBLogEventAppStart())
    }

    var body: some Scene {
        Settings {}
    }
}

final class TBStatusItem: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: TBStatusItem?

    private static let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let titleAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.95
        paragraphStyle.alignment = .center
        return [
            .font: TBStatusItem.digitFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor,
        ]
    }()

    private var popover: NSPopover?
    private var statusBarItem: NSStatusItem?
    private var timer: TBTimer?

    func applicationDidFinishLaunching(_: Notification) {
        TBStatusItem.shared = self

        configureStatusItem()
        configureTimer()
    }

    func applicationWillTerminate(_: Notification) {
        timer?.shutdown()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem = item

        guard let button = item.button else {
            return
        }

        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "TomatoBar"
        button.setAccessibilityLabel("TomatoBar")
        setIcon(name: .idle)
    }

    func setTitle(title: String?) {
        guard let button = statusBarItem?.button else {
            return
        }

        guard let title else {
            button.attributedTitle = NSAttributedString(string: "")
            button.setAccessibilityValue(nil)
            return
        }

        button.attributedTitle = NSAttributedString(
            string: " \(title)",
            attributes: Self.titleAttributes
        )
        button.setAccessibilityValue(title)
    }

    func setIcon(name _: NSImage.Name) {
        guard let button = statusBarItem?.button else {
            return
        }

        // Keep the tomato brand mark in every phase. The countdown in the
        // title and the popover communicate the active state; changing the
        // menu bar glyph is not necessary.
        let image = NSImage(named: .idle)
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Popover

    private func configureTimer() {
        timer = TBTimer()
    }

    /// The SwiftUI popover is created lazily. Building it at launch kept an
    /// offscreen hosting view alive (and animating) even if the user never
    /// opened the app.
    private func ensurePopover() -> Bool {
        if let popover, popover.contentViewController != nil {
            return true
        }
        guard let timer else {
            return false
        }

        let popover = self.popover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = TBPopoverView(timer: timer) { [weak self] in
            self?.closePopover(nil)
        }

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        // Let SwiftUI determine the height instead of hard-coding it. This
        // replaces the GeometryReader-based sizing workaround from older
        // versions and keeps the popover correct across localizations.
        hostingController.view.layoutSubtreeIfNeeded()
        let preferredSize = hostingController.preferredContentSize
        let fittingSize = hostingController.view.fittingSize
        popover.contentSize = NSSize(
            width: preferredSize.width > 0 ? preferredSize.width : max(fittingSize.width, 320),
            height: preferredSize.height > 0 ? preferredSize.height : max(fittingSize.height, 580)
        )

        self.popover = popover
        return true
    }

    func showPopover(_: AnyObject?) {
        guard let button = statusBarItem?.button, ensurePopover(), let popover, !popover.isShown else {
            return
        }

        timer?.isPopoverVisible = true
        timer?.refreshTimeLeft()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover(_ sender: AnyObject?) {
        popover?.performClose(sender)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover?.isShown == true {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    func popoverDidClose(_: Notification) {
        timer?.isPopoverVisible = false

        // Release the SwiftUI hosting graph after the close animation. It is
        // recreated on the next open instead of being retained for the rest of
        // the process lifetime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self,
                  self.timer?.isPopoverVisible != true,
                  self.popover?.isShown != true
            else {
                return
            }
            self.popover?.contentViewController = nil
            self.popover = nil
        }
    }
}

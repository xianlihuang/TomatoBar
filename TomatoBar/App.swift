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

final class TBStatusItem: NSObject, NSApplicationDelegate {
    static var shared: TBStatusItem?

    private static let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    private let popover = NSPopover()
    private var statusBarItem: NSStatusItem?
    private var timer: TBTimer?

    func applicationDidFinishLaunching(_: Notification) {
        TBStatusItem.shared = self

        configureStatusItem()
        configureTimer()
        configurePopover()
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

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 0.95
        paragraphStyle.alignment = .center

        button.attributedTitle = NSAttributedString(
            string: " \(title)",
            attributes: [
                .font: Self.digitFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        button.setAccessibilityValue(title)
    }

    func setIcon(name: NSImage.Name) {
        guard let button = statusBarItem?.button else {
            return
        }

        // SF Symbols render reliably in the macOS 27 menu bar and stay legible
        // in both light and dark appearances. The bundled template assets are
        // kept as a fallback.
        let symbolName: String
        switch name {
        case .work:
            symbolName = "timer"
        case .shortRest:
            symbolName = "cup.and.saucer.fill"
        case .longRest:
            symbolName = "moon.zzz.fill"
        default:
            symbolName = "timer"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TomatoBar")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(named: name)
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Popover

    private func configureTimer() {
        timer = TBTimer()
    }

    private func configurePopover() {
        guard let timer else {
            return
        }

        popover.behavior = .transient
        popover.animates = true

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
    }

    func showPopover(_: AnyObject?) {
        guard let button = statusBarItem?.button, !popover.isShown else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
}

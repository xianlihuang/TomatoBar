import AppKit
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

// MARK: - Palette

private enum TBPalette {
    static let focus = Color(red: 1.00, green: 0.36, blue: 0.27)
    static let focusDeep = Color(red: 0.90, green: 0.15, blue: 0.24)
    static let rest = Color(red: 0.20, green: 0.78, blue: 0.67)
    static let restDeep = Color(red: 0.13, green: 0.53, blue: 0.86)
    static let idle = Color(red: 0.78, green: 0.45, blue: 0.40)

    static func accent(for phase: TBStateMachineStates) -> Color {
        switch phase {
        case .idle:
            return idle
        case .work:
            return focus
        case .rest:
            return rest
        }
    }

    static func deepAccent(for phase: TBStateMachineStates) -> Color {
        switch phase {
        case .idle:
            return idle
        case .work:
            return focusDeep
        case .rest:
            return restDeep
        }
    }
}

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

// MARK: - Tabs

private enum PopoverTab: String, CaseIterable, Identifiable, Equatable {
    case intervals, settings, sounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intervals:
            return L("TBPopoverView.intervals.label")
        case .settings:
            return L("TBPopoverView.settings.label")
        case .sounds:
            return L("TBPopoverView.sounds.label")
        }
    }

    var symbol: String {
        switch self {
        case .intervals:
            return "timer"
        case .settings:
            return "slider.horizontal.3"
        case .sounds:
            return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Popover

struct TBPopoverView: View {
    @ObservedObject var timer: TBTimer
    var onClose: () -> Void

    @AppStorage("popoverActiveTab") private var activeTabRaw = PopoverTab.intervals.rawValue
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let contentHeight: CGFloat = 172

    private var activeTab: PopoverTab {
        PopoverTab(rawValue: activeTabRaw) ?? .intervals
    }

    private var accent: Color {
        TBPalette.accent(for: timer.phase)
    }

    private var deepAccent: Color {
        TBPalette.deepAccent(for: timer.phase)
    }

    private var completedInSet: Int {
        min(timer.completedWorkIntervals, max(timer.workIntervalsInSet, 1))
    }

    private var phaseTitle: String {
        switch timer.phase {
        case .idle:
            return L("TBPopoverView.phase.idle")
        case .work:
            return L("TBPopoverView.phase.work")
        case .rest:
            return timer.isLongRest
                ? L("TBPopoverView.phase.longRest")
                : L("TBPopoverView.phase.shortRest")
        }
    }

    private var dialSubtitle: String {
        switch timer.phase {
        case .idle:
            return String.localizedStringWithFormat(
                L("TBPopoverView.idle.subtitle"),
                timer.workIntervalLength
            )
        case .work:
            return String.localizedStringWithFormat(
                L("TBPopoverView.session"),
                timer.sessionNumber,
                timer.workIntervalsInSet
            )
        case .rest:
            return timer.isLongRest
                ? L("TBPopoverView.rest.long.subtitle")
                : L("TBPopoverView.rest.subtitle")
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            timerCard
            tabBar
            tabContent
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(ambientGlow)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: timer.phase)
    }

    // MARK: Header card

    private var timerCard: some View {
        VStack(spacing: 12) {
            cardHeader
            dial
            sessionDots
            actionButtons
        }
        .padding(16)
        .background(alignment: .top) {
            Circle()
                .fill(accent.opacity(0.30))
                .frame(width: 190, height: 190)
                .blur(radius: 46)
                .offset(y: -28)
                .allowsHitTesting(false)
        }
        .glassEffect(
            .regular.tint(accent.opacity(0.10)),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.015)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)

            Text("TomatoBar")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Text(phaseTitle.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.13))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(accent.opacity(0.20), lineWidth: 0.5)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: timer.phase)
        }
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 11)

            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.55), accent, deepAccent],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.35), radius: 7)
                .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: timer.progress)

            VStack(spacing: 3) {
                Text(timer.timeString)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: timer.timeString)

                Text(dialSubtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(width: 156, height: 156)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(phaseTitle))
        .accessibilityValue(Text("\(phaseTitle), \(timer.timeString), \(dialSubtitle)"))
    }

    // MARK: Session progress

    private var sessionDots: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< max(timer.workIntervalsInSet, 1), id: \.self) { index in
                Circle()
                    .fill(index < completedInSet ? accent : Color.primary.opacity(0.12))
                    .frame(
                        width: index < completedInSet ? 7 : 6,
                        height: index < completedInSet ? 7 : 6
                    )
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.3),
                        value: timer.completedWorkIntervals
                    )
            }

            Spacer(minLength: 8)

            Text("\(completedInSet)/\(timer.workIntervalsInSet)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .frame(height: 10)
    }

    // MARK: Actions

    @ViewBuilder
    private var actionButtons: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                switch timer.phase {
                case .idle:
                    Button(action: startStop) {
                        Label(L("TBPopoverView.start.label"), systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(TBPalette.focus)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint(Text(L("TBPopoverView.start.hint")))

                case .work:
                    Button(action: startStop) {
                        Label(L("TBPopoverView.stop.label"), systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(TBPalette.focus)
                    .keyboardShortcut(.defaultAction)

                case .rest:
                    Button(action: skipRest) {
                        Label(L("TBPopoverView.skipRest.label"), systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(TBPalette.rest)
                    .keyboardShortcut(.defaultAction)

                    Button(action: startStop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 18)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(Text(L("TBPopoverView.stop.label")))
                }
            }
        }
        .controlSize(.large)
        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(PopoverTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(activeTab == tab ? Color.primary : Color.secondary)
                .background {
                    if activeTab == tab {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(TBPalette.focus.opacity(0.16))
                            .matchedGeometryEffect(id: "selectedTab", in: tabNamespace)
                    }
                }
                .accessibilityAddTraits(activeTab == tab ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch activeTab {
            case .intervals:
                IntervalsView(timer: timer)
            case .settings:
                SettingsView(timer: timer)
            case .sounds:
                SoundsView(player: timer.player)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.contentHeight)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: showAbout) {
                Label(L("TBPopoverView.about.label"), systemImage: "info.circle")
            }
            .keyboardShortcut("a", modifiers: .command)

            Button(action: quit) {
                Label(L("TBPopoverView.quit.label"), systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)

            Spacer(minLength: 8)

            if let version = Self.appVersion {
                Text("v\(version)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var ambientGlow: some View {
        RadialGradient(
            colors: [accent.opacity(0.13), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 320
        )
        .allowsHitTesting(false)
    }

    // MARK: Actions

    private func startStop() {
        timer.startStop()
        onClose()
    }

    private func skipRest() {
        timer.skipRest()
        onClose()
    }

    private func select(_ tab: PopoverTab) {
        if reduceMotion {
            activeTabRaw = tab.rawValue
        } else {
            withAnimation(.snappy(duration: 0.28)) {
                activeTabRaw = tab.rawValue
            }
        }
    }

    private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private static let appVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String
}

// MARK: - Intervals

private struct IntervalsView: View {
    @ObservedObject var timer: TBTimer

    var body: some View {
        VStack(spacing: 0) {
            IntervalRow(
                symbol: "brain.head.profile",
                title: L("IntervalsView.workIntervalLength.label"),
                value: $timer.workIntervalLength,
                range: TBTimer.workIntervalRange,
                suffix: L("IntervalsView.min")
            )
            RowDivider()
            IntervalRow(
                symbol: "cup.and.saucer.fill",
                title: L("IntervalsView.shortRestIntervalLength.label"),
                value: $timer.shortRestIntervalLength,
                range: TBTimer.shortRestIntervalRange,
                suffix: L("IntervalsView.min")
            )
            RowDivider()
            IntervalRow(
                symbol: "moon.stars.fill",
                title: L("IntervalsView.longRestIntervalLength.label"),
                value: $timer.longRestIntervalLength,
                range: TBTimer.longRestIntervalRange,
                suffix: L("IntervalsView.min")
            )
            RowDivider()
            IntervalRow(
                symbol: "square.stack.3d.up.fill",
                title: L("IntervalsView.workIntervalsInSet.label"),
                value: $timer.workIntervalsInSet,
                range: TBTimer.workIntervalsInSetRange,
                suffix: nil
            )
        }
        .tbContentCard()
    }
}

private struct IntervalRow: View {
    let symbol: String
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String?

    private var valueText: String {
        guard let suffix else {
            return "\(value)"
        }
        return String.localizedStringWithFormat(suffix, value)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TBPalette.focus)
                .frame(width: 17)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(valueText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Stepper("", value: $value, in: range)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(Text(title))
        }
        .frame(height: 38)
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TBPalette.focus)
                    .frame(width: 17)

                Text(L("SettingsView.shortcut.label"))
                    .font(.system(size: 12, weight: .medium))

                Spacer(minLength: 8)

                KeyboardShortcuts.Recorder(for: .startStopTimer) {
                    EmptyView()
                }
                .fixedSize()
                .controlSize(.small)
                .accessibilityLabel(Text(L("SettingsView.shortcut.label")))
            }
            .frame(height: 38)

            RowDivider()

            ToggleRow(
                symbol: "moon.zzz.fill",
                title: L("SettingsView.stopAfterBreak.label"),
                isOn: $timer.stopAfterBreak
            )

            RowDivider()

            ToggleRow(
                symbol: "textformat.123",
                title: L("SettingsView.showTimerInMenuBar.label"),
                isOn: $timer.showTimerInMenuBar
            )

            RowDivider()

            ToggleRow(
                symbol: "power",
                title: L("SettingsView.launchAtLogin.label"),
                isOn: $launchAtLogin.isEnabled
            )
        }
        .tbContentCard()
    }
}

private struct ToggleRow: View {
    let symbol: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TBPalette.focus)
                    .frame(width: 17)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
        }
        .toggleStyle(.switch)
        .tint(TBPalette.focus)
        .frame(height: 38)
    }
}

// MARK: - Sounds

private struct SoundsView: View {
    @ObservedObject var player: TBPlayer

    var body: some View {
        VStack(spacing: 0) {
            SoundRow(
                symbol: "wind",
                title: L("SoundsView.isWindupEnabled.label"),
                volume: $player.windupVolume,
                isPreviewing: false
            ) {
                player.preview(.windup)
            }

            RowDivider()

            SoundRow(
                symbol: "bell.fill",
                title: L("SoundsView.isDingEnabled.label"),
                volume: $player.dingVolume,
                isPreviewing: false
            ) {
                player.preview(.ding)
            }

            RowDivider()

            SoundRow(
                symbol: "metronome.fill",
                title: L("SoundsView.isTickingEnabled.label"),
                volume: $player.tickingVolume,
                isPreviewing: player.isPreviewingTicking,
                isPreviewDisabled: player.isTicking
            ) {
                player.preview(.ticking)
            }
        }
        .tbContentCard()
    }
}

private struct SoundRow: View {
    let symbol: String
    let title: String
    @Binding var volume: Double
    let isPreviewing: Bool
    var isPreviewDisabled = false
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TBPalette.focus)
                .frame(width: 17)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: preview) {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    }
            }
            .buttonStyle(.plain)
            .disabled(isPreviewDisabled)
            .opacity(isPreviewDisabled ? 0.4 : 1)
            .accessibilityLabel(Text(L("TBPopoverView.preview.label")))

            Slider(value: $volume, in: 0 ... 2)
                .controlSize(.mini)
                .frame(width: 68)
                .tint(TBPalette.focus)
                .accessibilityLabel(Text(title))

            Text("\(Int((volume * 100).rounded()))%")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(height: 44)
    }
}

// MARK: - Shared pieces

private struct RowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, 26)
    }
}

private extension View {
    func tbContentCard() -> some View {
        padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thickMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    }
            }
    }
}

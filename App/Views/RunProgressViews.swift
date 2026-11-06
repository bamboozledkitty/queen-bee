import SwiftUI
import QueenBeeCore
import QueenBeeDesign

/// How far the run has got, in a pill at the top of the canvas: a ring, the number, and where the run is. Clicked,
/// it opens on the run's line of stops.
struct RunProgressPill: View {
    let controller: FlowController

    var body: some View {
        if let progress = controller.runProgress {
            VStack(spacing: DS.Space.s) {
                Ticking(isOn: controller.isRunning) { now in
                    pill(progress, now: now)
                }
                if controller.showsProgressLine {
                    RunProgressLine(controller: controller, progress: progress)
                        .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .dsAnimation(DS.Motion.standard, value: controller.showsProgressLine)
        }
    }

    private func pill(_ progress: RunProgress, now: Date) -> some View {
        let tone = progress.headline.tone
        return HStack(spacing: DS.Space.s) {
            Button { controller.showsProgressLine.toggle() } label: {
                HStack(spacing: DS.Space.s) {
                    ProgressRing(fraction: progress.fraction, tone: tone == .failed ? .fail : .pass)
                    Text("\(progress.percent)%")
                        .textRole(.label)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Palette.text.color)
                    Rectangle()
                        .fill(Palette.hairlineStrong.color)
                        .frame(width: DS.Stroke.hairline, height: DS.Size.iconSlot)
                    StatusDot(tone.status, size: 6)
                    Text(line(progress.headline, now: now))
                        .textRole(.caption)
                        .fontWeight(tone == .working || tone == .finished ? .regular : .semibold)
                        .foregroundStyle(tone.text.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .dsIcon(DS.IconSize.xs, .semibold)
                        .foregroundStyle(Palette.textMuted.color)
                        .rotationEffect(.degrees(controller.showsProgressLine ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(controller.showsProgressLine ? "Hide the run's stops" : "Show the run's stops")
            .accessibilityLabel("Run \(progress.percent) percent: \(progress.headline.text)")
            if !controller.isRunning {
                Button { controller.progressDismissed = true; controller.showsProgressLine = false } label: {
                    Image(systemName: "xmark").dsIcon(DS.IconSize.xs, .semibold)
                }
                .buttonStyle(.dsIcon)
                .help("Close until the next run")
                .accessibilityLabel("Close the run's progress")
            }
        }
        .padding(.leading, DS.Space.s)
        .padding(.trailing, DS.Space.m)
        .frame(height: DS.Size.bar)
        .frame(maxWidth: DS.Size.progressLineWidth)
        .fixedSize(horizontal: true, vertical: false)
        .floatingPanel()
        .dsAnimation(DS.Motion.standard, value: progress.percent)
    }

    /// The headline, with how long the card it is about has been at it.
    private func line(_ headline: RunProgress.Headline, now: Date) -> String {
        guard controller.isRunning, let id = headline.cardID, let since = controller.liveSince[id] else { return headline.text }
        return headline.text + " · " + RunClock.length(now.timeIntervalSince(since))
    }
}

/// The run's line of stops: every card that takes time, in the order the run reaches them.
struct RunProgressLine: View {
    let controller: FlowController
    let progress: RunProgress
    @State private var selectedID: String?
    @State private var openFlowID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            header
            StopsRow(stops: progress.stops, selectedID: selected?.id, compact: false) { selectedID = $0 }
            if let id = openFlowID, let card = controller.flow.card(id), let inner = controller.innerFlow(of: card) {
                SubflowLine(controller: inner, name: card.name, isOurs: controller.holds.contains { $0.cardID == id && inner.isRunning(forHold: $0.id) },
                            isWaitingItsTurn: controller.holds.contains { $0.cardID == id })
                    .transition(.opacity)
            }
            if let stop = selected {
                Rectangle().fill(Palette.hairline.color).frame(height: DS.Stroke.hairline)
                Ticking(isOn: controller.isRunning && stop.state != .done) { now in footer(stop, now: now) }
            }
        }
        .padding(DS.Space.l)
        .frame(maxWidth: DS.Size.progressLineWidth)
        .padding(.horizontal, DS.Space.l)
        .floatingPanel()
        .dsAnimation(DS.Motion.standard, value: openFlowID)
    }

    /// The stop picked, else the one the run is at, else the last.
    private var selected: RunProgress.Stop? {
        progress.stops.first { $0.id == selectedID }
            ?? progress.stops.first { [.needsYou, .failed, .live, .endedHere].contains($0.state) }
            ?? progress.stops.last
    }

    private var header: some View {
        HStack(spacing: DS.Space.m) {
            Text(controller.flow.name).textRole(.headline)
            Ticking(isOn: controller.isRunning) { now in
                if let time = controller.runTime(at: now) {
                    Text(RunClock.length(time)).textRole(.caption).monospacedDigit()
                }
            }
            .foregroundStyle(Palette.textMuted.color)
            Spacer(minLength: DS.Space.l)
            Text("Hand-offs \(controller.handOffs) of \(Engine.maxDeliveries)")
                .textRole(.caption).monospacedDigit()
                .foregroundStyle(Palette.textMuted.color)
            Text(spend)
                .textRole(.caption).monospacedDigit()
                .foregroundStyle(Palette.textMuted.color)
        }
        .foregroundStyle(Palette.text.color)
    }

    private var spend: String {
        let spent = controller.runSpend.price
        guard let limit = controller.flow.spendingLimit else { return spent }
        return "\(spent) of \(Usage(cost: limit).price)"
    }

    private func footer(_ stop: RunProgress.Stop, now: Date) -> some View {
        HStack(spacing: DS.Space.m) {
            Text(stop.name).textRole(.label).foregroundStyle(Palette.text.color)
            Text(detail(of: stop, now: now))
                .textRole(.caption)
                .foregroundStyle(Palette.textMuted.color)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s)
            if stop.kind == .flow {
                Button(openFlowID == stop.id ? "Hide its steps" : "Show its steps") {
                    openFlowID = openFlowID == stop.id ? nil : stop.id
                }
                .buttonStyle(.ds(.secondary))
            }
            Button("Show on canvas") {
                // The card's settings open where the line is, so the line makes way.
                controller.showsProgressLine = false
                controller.show(card: stop.id)
            }
                .buttonStyle(.ds(.primary))
        }
    }

    private func detail(of stop: RunProgress.Stop, now: Date) -> String {
        var parts = [stop.kind == .end ? "End" : stop.kind.label]
        switch stop.state {
        case .done: parts.append("passed")
        case .live:
            if let since = controller.liveSince[stop.id] { parts.append("at it for \(RunClock.length(now.timeIntervalSince(since)))") }
            else { parts.append("at work") }
        case .needsYou: parts.append("waiting for you")
        case .failed: parts.append("the run stopped here")
        case .endedHere: parts.append("the run ended while it was here")
        case .notYet: parts.append("still to come")
        case .skipped: parts.append("the run didn't go this way")
        }
        if let items = stop.items { parts.append("item \(items.current + 1) of \(items.count)") }
        if let loop = stop.loopBack { parts.append(loop.currentTry.map { "try \($0) of \(loop.mostTries)" } ?? "a loop can send it back here") }
        if let inner = stop.inner { parts.append("its flow is \(Int(inner * 100))% through") }
        if let used = controller.runUsage(forCard: stop.id), !used.isZero { parts.append(used.price) }
        return parts.joined(separator: " · ")
    }
}

/// The line of stops a Flow card's flow is going through, under the Flow card's stop.
private struct SubflowLine: View {
    let controller: FlowController
    let name: String
    /// The flow is running for this Flow card, rather than for someone else.
    let isOurs: Bool
    let isWaitingItsTurn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Text(name).textRole(.captionLabel)
                Text(controller.flow.name).textRole(.caption).foregroundStyle(Palette.textMuted.color)
                Spacer()
                if isOurs, let progress = controller.latestProgress {
                    Text("\(progress.percent)%").textRole(.captionLabel).monospacedDigit()
                } else {
                    Text(isWaitingItsTurn ? "Waiting its turn" : "Not running").textRole(.caption).foregroundStyle(Palette.textMuted.color)
                }
            }
            if isOurs, let progress = controller.latestProgress {
                StopsRow(stops: progress.stops, selectedID: nil, compact: true) { _ in }
            }
        }
        .foregroundStyle(Palette.text.color)
        .padding(DS.Space.m)
        .background(Palette.raised.color, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
    }
}

/// Stops in a row, joined by a line that is green as far as the run has come. Scrolls sideways when there are more
/// than fit, and keeps the stop the run is at in view.
private struct StopsRow: View {
    let stops: [RunProgress.Stop]
    let selectedID: String?
    let compact: Bool
    let pick: (String) -> Void

    private var liveID: String? { stops.first { [.live, .needsYou, .failed, .endedHere].contains($0.state) }?.id }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        StopView(stop: stop, isFirst: index == 0, isLast: index == stops.count - 1,
                                 previous: index > 0 ? stops[index - 1].state : nil,
                                 isSelected: stop.id == selectedID, compact: compact) { pick(stop.id) }
                            .id(stop.id)
                    }
                }
                .padding(.top, compact ? 0 : DS.Space.l)
            }
            .onAppear { if let liveID { reader.scrollTo(liveID, anchor: .center) } }
            .onChange(of: liveID) { _, id in
                guard let id else { return }
                withAnimation(Theme.Motion.standard) { reader.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct StopView: View {
    let stop: RunProgress.Stop
    let isFirst: Bool
    let isLast: Bool
    let previous: RunProgress.StopState?
    let isSelected: Bool
    let compact: Bool
    let pick: () -> Void

    private var size: CGFloat { compact ? DS.Size.stop * 0.75 : DS.Size.stop }
    private var reached: Bool { stop.state != .notYet && stop.state != .skipped }

    var body: some View {
        Button(action: pick) {
            VStack(spacing: DS.Space.xs) {
                ZStack {
                    HStack(spacing: 0) {
                        Rectangle().fill((reached ? Palette.pass : Palette.hairlineStrong).color).opacity(isFirst ? 0 : 1)
                        Rectangle().fill((stop.state == .done ? Palette.pass : Palette.hairlineStrong).color).opacity(isLast ? 0 : 1)
                    }
                    .frame(height: DS.Stroke.track)
                    dot
                }
                .frame(height: size)
                .overlay(alignment: .top) { if !compact, let loop = stop.loopBack { loopMark(loop) } }
                Text(stop.name)
                    .textRole(compact ? .footnote : .caption)
                    .fontWeight(reached && stop.state != .done ? .semibold : .regular)
                    .foregroundStyle((stop.state == .notYet || stop.state == .skipped ? Palette.textFaint : Palette.text).color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !compact, let note {
                    Text(note)
                        .textRole(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(noteColor.color)
                        .lineLimit(1)
                }
                if !compact, let items = stop.items, items.count <= 12 { ticks(items) }
            }
            .frame(width: compact ? DS.Size.stopColumn * 0.8 : DS.Size.stopColumn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stop.name): \(note ?? stop.state.rawValue)")
    }

    @ViewBuilder private var dot: some View {
        let shape = Circle()
        switch stop.state {
        case .done:
            shape.fill(Palette.pass.color).frame(width: size, height: size)
                .overlay(Image(systemName: "checkmark").dsIcon(DS.IconSize.xxs, .bold).foregroundStyle(Palette.onAccent.color))
        case .live:
            shape.fill(Palette.overlay.color).frame(width: size, height: size)
                .overlay(shape.strokeBorder(Palette.live.color, lineWidth: DS.Stroke.track))
                .background(shape.fill(Palette.liveTint.color).padding(-size * 0.25))
        case .needsYou:
            shape.fill(Palette.live.color).frame(width: size, height: size)
                .background(shape.fill(Palette.liveTint.color).padding(-size * 0.25))
        case .failed:
            shape.fill(Palette.fail.color).frame(width: size, height: size)
                .overlay(Image(systemName: "xmark").dsIcon(DS.IconSize.xxs, .bold).foregroundStyle(Palette.onAccent.color))
        case .endedHere:
            shape.fill(Palette.textFaint.color).frame(width: size, height: size)
        case .notYet:
            shape.fill(Palette.overlay.color).frame(width: size, height: size)
                .overlay(shape.strokeBorder(Palette.hairlineStrong.color, lineWidth: DS.Stroke.focus))
        case .skipped:
            shape.fill(Palette.hairline.color).frame(width: size * 0.6, height: size * 0.6)
        }
        if isSelected {
            shape.strokeBorder(Palette.accent.color, lineWidth: DS.Stroke.focus).frame(width: size + DS.Space.s, height: size + DS.Space.s)
        }
    }

    private func loopMark(_ loop: RunProgress.LoopBack) -> some View {
        let going = (loop.currentTry ?? 0) > 1
        return HStack(spacing: DS.Space.xxs) {
            Image(systemName: "arrow.counterclockwise").dsIcon(DS.IconSize.xxs, .bold)
            if let now = loop.currentTry, now > 1 { Text("try \(now) of \(loop.mostTries)").textRole(.micro).monospacedDigit() }
        }
        .foregroundStyle((going ? Palette.liveText : Palette.textFaint).color)
        .padding(.horizontal, DS.Space.xs)
        .frame(minHeight: DS.Space.l)
        .background((going ? Palette.liveTint : Palette.panel.opacity(0)).color, in: Capsule())
        .offset(y: -(DS.Space.l + DS.Space.xxs))
        .help(going ? "A loop sent the message back here" : "A loop can send the message back here")
    }

    private func ticks(_ items: RunSnapshot.Items) -> some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(0..<items.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: DS.Space.xxs / 2)
                    .fill((index < items.current ? Palette.pass : index == items.current ? Palette.live : Palette.hairlineStrong).color)
                    .frame(width: DS.Size.itemTick, height: DS.Size.itemTick)
            }
        }
    }

    private var note: String? {
        switch stop.state {
        case .needsYou: return "Needs you"
        case .failed: return "Stopped here"
        case .endedHere: return "Ended here"
        case .skipped: return "Skipped"
        default: break
        }
        if let items = stop.items { return "item \(items.current + 1) of \(items.count)" }
        if let inner = stop.inner { return "\(Int(inner * 100))% through" }
        return nil
    }

    private var noteColor: Shade {
        switch stop.state {
        case .needsYou: Palette.liveText
        case .failed: Palette.failText
        default: Palette.textFaint
        }
    }
}

/// A ring that fills as the run goes.
private struct ProgressRing: View {
    let fraction: Double
    let tone: StatusTone

    var body: some View {
        ZStack {
            Circle().stroke(Palette.hairline.color, lineWidth: DS.Stroke.track)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(tone.mark.color, style: StrokeStyle(lineWidth: DS.Stroke.track, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(DS.Stroke.track / 2)
        .frame(width: DS.Size.progressRing, height: DS.Size.progressRing)
        .accessibilityHidden(true)
    }
}

/// Redraws what it holds every second while `isOn`, for times that count up. Off, it draws once.
private struct Ticking<Content: View>: View {
    let isOn: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isOn {
            TimelineView(.periodic(from: .now, by: 1)) { context in content(context.date) }
        } else {
            content(Date())
        }
    }
}

private extension RunProgress.Headline.Tone {
    var status: StatusTone {
        switch self {
        case .working, .needsYou: .live
        case .failed: .fail
        case .finished: .pass
        case .stopped: .neutral
        }
    }

    var text: Shade {
        switch self {
        case .working: Palette.text
        case .needsYou: Palette.liveText
        case .failed: Palette.failText
        case .finished: Palette.passText
        case .stopped: Palette.textMuted
        }
    }
}

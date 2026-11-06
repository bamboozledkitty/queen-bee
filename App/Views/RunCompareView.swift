import SwiftUI
import QueenBeeCore
import QueenBeeDesign

/// Two runs of a flow side by side, in a sheet: how each ended and what it took, then what each card did,
/// the cards that changed first.
struct RunCompareSheet: View {
    let flowName: String
    let comparison: RunComparison
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Compare runs").textRole(.title).foregroundStyle(Palette.text.color)
                    Text("\(flowName): \(comparison.before.name) and \(comparison.after.name)")
                        .textRole(.caption)
                        .foregroundStyle(Palette.textMuted.color)
                }
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.l)
            DSDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    totals
                    overall
                    let changed = comparison.rows.filter(\.isChanged), same = comparison.rows.filter { !$0.isChanged }
                    if !changed.isEmpty { cards("Cards that changed", changed) }
                    if !same.isEmpty { cards("Cards that did the same", same) }
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: DS.Size.compareSheet)
        .frame(minHeight: DS.Size.sheetMinHeight, idealHeight: DS.Size.sheetHeight, maxHeight: DS.Size.sheetMaxHeight)
    }

    private var totals: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.s) {
            GridRow {
                Color.clear.frame(width: DS.Size.compareName, height: 1)
                runHeader(comparison.before)
                runHeader(comparison.after)
            }
            total("Ended", comparison.before.summary, comparison.after.summary)
            total("Took", comparison.before.length, comparison.after.length)
            total("Cost", Self.cost(comparison.before), Self.cost(comparison.after))
            total("Hand-offs", "\(comparison.before.handOffs)", "\(comparison.after.handOffs)")
        }
    }

    private func runHeader(_ side: RunComparison.Side) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(side.name).textRole(.headline).foregroundStyle(Palette.text.color)
            Text(RunClock.moment(side.started)).textRole(.caption).foregroundStyle(Palette.textFaint.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func total(_ label: String, _ before: String, _ after: String) -> some View {
        GridRow {
            Text(label).textRole(.captionLabel).foregroundStyle(Palette.textMuted.color)
            Text(before).textRole(.body).foregroundStyle(Palette.text.color)
            Text(after).textRole(.body).foregroundStyle((before == after ? Palette.text : StatusTone.accent.text).color)
        }
    }

    @ViewBuilder
    private var overall: some View {
        let nothing = comparison.changes.isEmpty && !comparison.rows.contains(where: \.isChanged)
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if nothing {
                Text("Both runs went the same way, as far as they were kept.").textRole(.body).foregroundStyle(Palette.text.color)
            }
            if let note = comparison.repliesNote {
                Text(note).textRole(.caption).foregroundStyle(Palette.textMuted.color).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cards(_ title: String, _ rows: [RunComparison.Row]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title) { CountBadge(rows.count) }
            ForEach(rows) { row in
                DSDivider()
                CompareCardRow(comparison: comparison, row: row)
                    .padding(.vertical, DS.Space.s)
                    .padding(.horizontal, DS.Space.s)
            }
        }
    }

    private static func cost(_ side: RunComparison.Side) -> String {
        side.cost.map(\.price) ?? "Not worked out"
    }
}

/// One card in both runs: its name and what changed on the left, then what it did in each run.
private struct CompareCardRow: View {
    let comparison: RunComparison
    let row: RunComparison.Row

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(row.name).textRole(.label).foregroundStyle((row.kind == nil ? Palette.textMuted : Palette.text).color)
                ForEach(row.changes, id: \.self) { change in
                    Text(change).textRole(.caption).foregroundStyle(StatusTone.accent.text.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: DS.Size.compareName, alignment: .leading)
            side(row.before)
            side(row.after)
        }
        .accessibilityElement(children: .combine)
    }

    private func side(_ run: RunComparison.CardRun) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(comparison.line(for: run, in: row))
                .textRole(.body)
                .foregroundStyle((run.failed ? StatusTone.fail.text : run.reached ? Palette.text : Palette.textFaint).color)
            if let words = run.answer ?? run.reply {
                Text(words)
                    .textRole(.caption)
                    .foregroundStyle(Palette.textMuted.color)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI
import QueenBeeCore
import QueenBeeDesign

/// Two of a flow's kept runs side by side, the Mac's Compare with…: how each ended and what it took, then what
/// each card did, the cards that changed first. The runs are picked here, the two latest to begin with.
struct RunCompareSheet: View {
    @Environment(RemoteClient.self) private var client
    @Environment(\.dismiss) private var dismiss
    /// The runs picked here. Until one is picked it is one of the two latest, as the Mac's list of runs is now:
    /// a run that ends while the sheet is open comes into it.
    @State private var pickedFirst: String?
    @State private var pickedSecond: String?

    /// "Run 12 · 14:02 · finished", newest first.
    static func choices(in runs: [RunRecord]) -> [(id: String, label: String)] {
        runs.reversed().map { run in
            (run.id, "\(run.number.map { "Run \($0) · " } ?? "")\(Clock.run(run.started)) · \(run.summary)")
        }
    }

    /// A picked run, while it is still kept. One that has since dropped out of the kept runs goes back to the
    /// default, so the sheet never asks for a run it no longer has.
    private static func kept(_ id: String?, in runs: [RunRecord]) -> String? {
        id.flatMap { id in runs.contains { $0.id == id } ? id : nil }
    }

    var body: some View {
        let snapshot = client.mirror.snapshot
        let runs = snapshot?.runs ?? []
        let first = Self.kept(pickedFirst, in: runs) ?? runs.dropLast().last?.id ?? ""
        let second = Self.kept(pickedSecond, in: runs) ?? runs.last?.id ?? ""
        let comparison = snapshot.flatMap { snapshot in
            runs.first { $0.id == first }.flatMap { one in
                runs.first { $0.id == second }.flatMap { RunComparison(one, $0, in: snapshot.flow) }
            }
        }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    PanelSection(title: "Runs") {
                        picker("One run", Binding(get: { first }, set: { pickedFirst = $0 }), runs)
                        Hairline()
                        picker("The other", Binding(get: { second }, set: { pickedSecond = $0 }), runs)
                    }
                    if let comparison {
                        CompareTotals(comparison: comparison)
                        if let note = comparison.repliesNote {
                            Text(note).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui).fixedSize(horizontal: false, vertical: true)
                        }
                        let changed = comparison.rows.filter(\.isChanged), same = comparison.rows.filter { !$0.isChanged }
                        if changed.isEmpty && comparison.changes.isEmpty {
                            Text("Both runs went the same way, as far as they were kept.").textRole(.body).foregroundStyle(Theme.ink.ui)
                        }
                        if !changed.isEmpty { cards("Cards that changed", changed, comparison) }
                        if !same.isEmpty { cards("Cards that did the same", same, comparison) }
                    } else {
                        Text("Pick two different runs to set side by side.").textRole(.body).foregroundStyle(Theme.inkSecondary.ui)
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: DS.Size.sheetWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.surface.ui)
            .navigationTitle("Compare runs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.ink.ui)
        #if DEBUG
        .onAppear { DebugLaunch.compared = comparison.map(Self.described) }
        .onChange(of: comparison) { _, now in DebugLaunch.compared = now.map(Self.described) }
        .onDisappear { DebugLaunch.compared = nil }
        #endif
    }

    #if DEBUG
    private static func described(_ c: RunComparison) -> [String: Any] {
        ["before": c.before.name, "after": c.after.name, "changes": c.changes, "comparesReplies": c.comparesReplies,
         "rows": c.rows.map { ["name": $0.name, "changes": $0.changes, "before": c.line(for: $0.before, in: $0), "after": c.line(for: $0.after, in: $0)] }]
    }
    #endif

    private func picker(_ label: String, _ selection: Binding<String>, _ runs: [RunRecord]) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text(label).textRole(.body).foregroundStyle(Theme.ink.ui)
            Spacer(minLength: Theme.Space.s)
            Picker(label, selection: selection) {
                ForEach(Self.choices(in: runs), id: \.id) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: Theme.Touch.target)
    }

    private func cards(_ title: String, _ rows: [RunComparison.Row], _ comparison: RunComparison) -> some View {
        PanelSection(title: title) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Hairline() }
                CompareCard(comparison: comparison, row: row)
            }
        }
    }
}

/// How each run ended, how long it took, what it cost and how many hand-offs it made.
private struct CompareTotals: View {
    let comparison: RunComparison

    var body: some View {
        let a = comparison.before, b = comparison.after
        // "#11 and #12", or "The earlier run and the later run" for runs from before runs were numbered.
        let title = "\(a.name) and \(b.name)"
        PanelSection(title: title.prefix(1).uppercased() + title.dropFirst()) {
            line("Ended", a.summary, b.summary)
            Hairline()
            line("Took", a.length, b.length)
            Hairline()
            line("Cost", a.cost?.price ?? "Not worked out", b.cost?.price ?? "Not worked out")
            Hairline()
            line("Hand-offs", "\(a.handOffs)", "\(b.handOffs)")
        }
    }

    private func line(_ label: String, _ one: String, _ two: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label).textRole(.body).foregroundStyle(Theme.ink.ui)
            Spacer(minLength: Theme.Space.s)
            Text(one).textRole(.body).foregroundStyle(Theme.inkSecondary.ui)
            Image(systemName: "arrow.right").dsIcon(DS.IconSize.xs, .semibold).foregroundStyle(Theme.inkSecondary.ui).accessibilityHidden(true)
            Text(two).textRole(.body).foregroundStyle((one == two ? Theme.inkSecondary : Theme.select).ui)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: Theme.Touch.target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(one) in \(comparison.before.name), \(two) in \(comparison.after.name)")
    }
}

/// One card in both runs: its name and what changed, then what it did in each.
private struct CompareCard: View {
    let comparison: RunComparison
    let row: RunComparison.Row

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(row.name).textRole(.label).foregroundStyle((row.kind == nil ? Theme.inkSecondary : Theme.ink).ui)
            ForEach(row.changes, id: \.self) { change in
                Text(change).textRole(.caption).foregroundStyle(Theme.select.ui)
            }
            side(comparison.before.name, row.before)
            side(comparison.after.name, row.after)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func side(_ name: String, _ run: RunComparison.CardRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(name).textRole(.monoLabel).foregroundStyle(Theme.inkSecondary.ui)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(comparison.line(for: run, in: row))
                    .textRole(.body)
                    .foregroundStyle((run.failed ? Theme.failInk : Theme.ink).ui)
                if let words = run.answer ?? run.reply {
                    Text(words).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui).lineLimit(4)
                }
            }
        }
    }

    /// Read out as one passage.
    private var spoken: String {
        let changes = row.changes.isEmpty ? "The same in both runs." : row.changes.joined(separator: ". ") + "."
        return "\(row.name). \(changes) In \(comparison.before.name): \(comparison.line(for: row.before, in: row)). "
            + "In \(comparison.after.name): \(comparison.line(for: row.after, in: row))."
    }
}

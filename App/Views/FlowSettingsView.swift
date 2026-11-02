import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// Settings that belong to a whole flow, shown as a page under the flow's Settings tab.
struct FlowSettingsView: View {
    /// How wide the page's column is. Wider than this and the lines are too long to read.
    static let pageWidth: CGFloat = 520

    let controller: FlowController
    @State private var name = ""
    @State private var limit = ""
    @State private var spending = ""
    @State private var cleared = false
    private var services: AppServices { AppServices.shared }

    var body: some View {
        let top = controller.topFlows
        let isTop = top.count == 1 && top[0] === controller
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "slider.horizontal.3").dsIcon(DS.IconSize.l, .medium).frame(width: DS.Size.iconSlot)
                TextField("Flow name", text: $name)
                    .textFieldStyle(.plain)
                    .textRole(.label)
                    .onSubmit { controller.rename(to: name) }
                    .help("Rename this flow")
                Text(controller.flow.isSubflow == true ? "Sub-flow" : "Flow")
                    .textRole(.caption)
                    .foregroundStyle(Theme.inkSecondary.ui)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)

            if isTop {
                line("Sub-flows can go") {
                    HStack(spacing: DS.Space.tight) {
                        TextField("3", text: $limit)
                            .textFieldStyle(.plain)
                            .textRole(.monoLabel)
                            .multilineTextAlignment(.center)
                            .frame(width: 34)
                            .fieldBox()
                            .onSubmit(commitLimit)
                            .onChange(of: limit) {
                                // Digits only, and the change is taken as soon as it is a number.
                                let digits = limit.filter(\.isNumber)
                                if digits != limit { limit = digits }
                                if !digits.isEmpty { commitLimit() }
                            }
                        Text(Nesting.levels(controller.ownSubflowLimit).hasSuffix("s") ? "levels deep" : "level deep")
                            .textRole(.caption)
                            .foregroundStyle(Theme.inkSecondary.ui)
                    }
                }
                let below = controller.levelsBelow
                if below > controller.ownSubflowLimit {
                    // Lowering the limit under what is already built deletes nothing.
                    Label("This flow already goes \(Nesting.levels(below)) deep. The levels past the limit are kept, marked on their Flow cards, and come out Fail when a run reaches them.",
                          systemImage: "exclamationmark.triangle")
                        .textRole(.caption)
                        .foregroundStyle(Theme.failInk.ui)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.Space.m)
                        .padding(.bottom, DS.Space.s)
                } else {
                    text("A Flow card runs another flow, which can hold Flow cards of its own. This is how far down that may go under this flow. 0 means no sub-flows. It goes \(below) deep now.")
                }
            } else {
                // A sub-flow goes by the flow at the top, so there is one place to set the limit.
                VStack(alignment: .leading, spacing: DS.Space.tight) {
                    Text(controller.levelsLeft >= 0
                         ? "This sub-flow may go \(Nesting.levels(controller.levelsLeft)) further down."
                         : "This sub-flow is past the limit, so it is kept but won't be run from the flow above.")
                        .textRole(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(top, id: \.flow.id) { outer in
                        Button {
                            services.selectedFlow = outer
                            outer.showsFlowSettings = true
                        } label: {
                            Text("The limit is set on \(outer.flow.name): \(Nesting.levels(outer.ownSubflowLimit))")
                        }
                        .buttonStyle(.panel())
                        .help("Go to \(outer.flow.name)'s settings")
                    }
                }
                .padding(DS.Space.m)
                .overlay(alignment: .top) { divider }
            }

            line("Stop a run once it has spent") {
                HStack(spacing: DS.Space.xs) {
                    Text("$").textRole(.monoLabel)
                    TextField("No limit", text: $spending)
                        .textFieldStyle(.plain)
                        .textRole(.monoLabel)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .fieldBox()
                        .onSubmit(commitSpending)
                        .help("In US dollars. Leave it empty for no limit.")
                }
            }
            text("Queen Bee adds up what a run's agents have used, at API prices, each time one of them finishes a turn. A run that goes past this amount is stopped, its agents are interrupted, and you're told. A sub-flow keeps to its own limit.")

            line("Tell the orchestrator when a run ends") {
                Toggle("", isOn: Binding(get: { controller.flow.notifyOrchestrator }, set: { controller.setNotifiesOrchestrator($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.select.ui)
            }
            text("When on, the orchestrator is sent what each run did and replies about it. That reply uses its model, so turning this off makes runs cheaper.")

            line("Browser data for \(controller.project.name)") {
                Button(cleared ? "Cleared" : "Clear browser data") {
                    cleared = true
                    Task { await controller.project.browser.clearData() }
                }
                .buttonStyle(.panel())
                .disabled(cleared || !controller.project.browser.hasData)
                .help("Signs the agents' browser out of every site and forgets the pages it has kept. It covers every flow in this project.")
            }
            text("Agent cards with a browser share one set of sign-ins across this project, kept apart from your own browser.")
        }
        .frame(maxWidth: Self.pageWidth)
        .foregroundStyle(Theme.ink.ui)
        .raisedSurface()
        .onAppear {
            name = controller.flow.name
            limit = "\(controller.ownSubflowLimit)"
            spending = Self.dollars(controller.flow.spendingLimit)
        }
        .onDisappear(perform: commitSpending)
        .onChange(of: controller.flow.spendingLimit) { spending = Self.dollars(controller.flow.spendingLimit) }
        .onChange(of: controller.flow.name) { name = controller.flow.name }
        .onChange(of: controller.ownSubflowLimit) { if Int(limit) != controller.ownSubflowLimit { limit = "\(controller.ownSubflowLimit)" } }
    }

    private func commitLimit() {
        guard let wanted = Int(limit) else { return limit = "\(controller.ownSubflowLimit)" }
        controller.setSubflowLimit(wanted)
        // A number out of range is brought back into it where you can see it.
        if wanted != controller.ownSubflowLimit { limit = "\(controller.ownSubflowLimit)" }
    }

    /// Takes what was typed as the limit: empty for none, and anything that isn't an amount puts back what was there.
    private func commitSpending() {
        let typed = spending.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ".")
        if typed.isEmpty { return controller.setSpendingLimit(nil) }
        guard let amount = Double(typed) else { return spending = Self.dollars(controller.flow.spendingLimit) }
        controller.setSpendingLimit(amount)
        spending = Self.dollars(controller.flow.spendingLimit)
    }

    /// "5", "2.50", or empty for no limit.
    static func dollars(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return amount == amount.rounded() ? String(format: "%.0f", amount) : String(format: "%.2f", amount)
    }

    private var divider: some View { DSDivider() }

    private func line<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DS.Space.s) {
            Text(title).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
            Spacer(minLength: DS.Space.s)
            content()
        }
        .padding(.horizontal, DS.Space.m)
        .frame(minHeight: 34)
        .overlay(alignment: .top) { divider }
    }

    private func text(_ words: String) -> some View {
        Text(words)
            .textRole(.caption)
            .foregroundStyle(Theme.inkSecondary.ui)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.s)
    }
}

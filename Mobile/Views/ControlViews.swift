import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// The controls this device has when the Mac lets it do more than watch: the run bar, the buttons that
/// answer what a run is waiting on, and the questions asked before anything that stops work or runs a
/// command. What is on offer is decided in one place, `Abilities`. Nothing here decides it again.

/// A row of buttons that each ask the Mac for one thing. The same buttons are on the card, in the banner
/// and in the details, so they are drawn from the same values everywhere.
struct PressButtons: View {
    @Environment(RemoteClient.self) private var client
    let buttons: [PressButton]
    /// The card they are about, for VoiceOver, which hears each button by itself.
    var about = ""

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(buttons) { button in
                Button(button.title) { client.press(button.press) }
                    .buttonStyle(.panel(button.isMain ? .filled : .outline))
                    .disabled(!button.isEnabled)
                    .accessibilityLabel(about.isEmpty ? button.title : "\(button.title), \(about)")
                    .accessibilityHint(button.hint)
            }
        }
    }
}

/// What floats over the foot of the canvas, and the one place its order is set: a refusal on top, since it
/// is about what was just pressed, then the editing bar while the flow is being edited, then the run bar
/// and the connection strip. Side by side where there is
/// room, the connection at the left as before and the run bar at the right, under the thumb. One above the
/// other where there isn't. The canvas is told how tall all of it is, and fits the flow clear of it. The
/// banners are at the canvas's top, so nothing here can meet them.
struct CanvasFoot: View {
    @Environment(RemoteClient.self) private var client
    let showSettings: () -> Void

    var body: some View {
        let abilities = client.abilities
        VStack(alignment: .trailing, spacing: Theme.Space.s) {
            if let refusal = client.controls.refusal {
                RefusalNotice(text: refusal.text) { client.controls.refusal = nil }
                    .transition(.opacity)
            }
            EditBar()
            // When the connection is well and has nothing to explain, a phone folds it into a dot beside the buttons
            // rather than spend a bar of its own on it. Otherwise it keeps its strip, where the help can be read.
            let status = ConnectionStatus(client)
            let folds = status.isConnected && !status.hasHelp
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: Theme.Space.m) {
                    ConnectionBar(showSettings: showSettings)
                    Spacer(minLength: 0)
                    CanvasMore()
                    RunBar(abilities: abilities, showSettings: showSettings)
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .bottom, spacing: Theme.Space.s) {
                        RunBar(abilities: abilities, showSettings: showSettings)
                        CanvasMore()
                        if folds {
                            Spacer(minLength: 0)
                            ConnectionBar(showSettings: showSettings, isCompact: true)
                        }
                    }
                    if !folds { ConnectionBar(showSettings: showSettings) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .dsAnimation(DS.Motion.standard, value: client.controls.refusal)
    }
}

/// Run and Stop, as the Mac's toolbar has them: Run when nothing is going, Stop while a run is. The Mac's
/// Run takes no words of its own, and neither does this one: a run starts with what its Start card says.
/// When this device may only watch, one short line here says so, with a button that opens the settings, where how
/// to change that is written. There are no run buttons.
struct RunBar: View {
    @Environment(RemoteClient.self) private var client
    @Environment(\.horizontalSizeClass) private var sizeClass
    let abilities: Abilities
    let showSettings: () -> Void

    var body: some View {
        if let hint = abilities.hint {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                // A device that only watches is told of a rehearsal too, on a line of its own as for one that controls.
                if abilities.isRehearsing {
                    rehearsalBadge
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.top, Theme.Space.xs)
                }
                HStack(spacing: Theme.Space.xs) {
                    Text("Watching only")
                        .textRole(.caption)
                        .foregroundStyle(Theme.inkSecondary.ui)
                        .lineLimit(1)
                        .padding(.leading, Theme.Space.s)
                    Button("Settings", action: showSettings)
                        .buttonStyle(.panel(.quiet))
                        .accessibilityHint(hint)
                }
            }
            .padding(Theme.Space.xs)
            .floatingPanel()
            .accessibilityElement(children: .contain)
        } else if !abilities.bar.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // The bar's note has a line of its own above the buttons, on a phone and on an iPad: beside them it is a
            // column a few words wide, which wraps to six lines and spills out of the bar.
            if let note = abilities.barNote {
                Text(note)
                    .textRole(.caption)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: DS.Size.calloutWidth, alignment: .leading)
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.top, Theme.Space.xs)
            }
            // While a rehearsal goes, the bar says so on a line of its own, as the Mac's run pill does. Beside the buttons
            // it would squeeze them on a phone.
            if abilities.isRehearsing {
                rehearsalBadge
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.top, Theme.Space.xs)
            }
            // Stop and Run side by side in a rehearsal leave no room for Restart's name on a narrow canvas, so it is
            // its arrow alone then, and no button's name is cut short.
            buttons(compact: abilities.isRehearsing)
            }
            .padding(Theme.Space.xs)
            .floatingPanel()
        }
    }

    private var rehearsalBadge: some View {
        Badge(text: "Rehearsal", symbol: "theatermasks", tone: .live)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A rehearsal is going")
    }

    /// On a phone, Run and Stop are their symbols alone when the bar has more than one of them, or Run's arrow for
    /// Rehearse: their names don't fit beside each other. VoiceOver still reads the names.
    private var symbolsOnly: Bool { sizeClass == .compact && (abilities.isRehearsing || abilities.rehearse != nil) }

    private func buttons(compact: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            // Editing is a mode, and this is the way in. The way out is Done, on the bar that takes its place.
            if let edit = client.editBar.first, edit.kind == .edit {
                Button(edit.title) { client.press(.edit) }
                    .buttonStyle(.panel(.tool))
                    // Beside Stop and Run in a rehearsal its name would be cut short to nothing: they are symbols then, and it is whole.
                    .fixedSize(horizontal: compact, vertical: false)
                    .accessibilityHint(edit.hint)
                Rectangle().fill(Theme.hairline.ui).frame(width: 1, height: Theme.Touch.target - Theme.Space.s).accessibilityHidden(true)
            }
            ForEach(abilities.bar) { button in
                if button.press == .run, !abilities.runMenu.isEmpty {
                    // Several Start cards: the Mac's Run has a menu of them, "Run from X", and Rehearse under them.
                    Menu {
                        ForEach(abilities.runMenu) { start in
                            Button(start.title) { client.press(start.press) }.disabled(!start.isEnabled)
                        }
                        if let rehearse = abilities.rehearse {
                            Divider()
                            rehearseItem(rehearse)
                        }
                    } label: {
                        Label(button.title, systemImage: "play.fill")
                    }
                    .buttonStyle(.panel(.run))
                    .disabled(!button.isEnabled && abilities.runMenu.allSatisfy { !$0.isEnabled })
                    .accessibilityHint("This flow has \(abilities.runMenu.count) Start cards. Lists them, to run the flow on your Mac from one\(abilities.rehearse == nil ? "" : ", or to rehearse it").")
                } else if button.press == .run, let rehearse = abilities.rehearse {
                    // One Start card: Run, and an arrow beside it with Rehearse, the two halves of one button as on the Mac.
                    HStack(spacing: 0) {
                        Button { client.press(button.press) } label: { runLabel(button.title, systemImage: "play.fill") }
                            .buttonStyle(.ds(.primary, joined: .trailing))
                            .disabled(!button.isEnabled)
                            .accessibilityHint(button.hint)
                        Menu { rehearseItem(rehearse) } label: {
                            Image(systemName: "chevron.down").dsIcon(DS.IconSize.s, .semibold)
                        }
                        .buttonStyle(.ds(.primary, joined: .leading))
                        .disabled(!rehearse.isEnabled)
                        .accessibilityLabel("More ways to run")
                        .accessibilityHint("Rehearse the flow: a cheap run on Haiku that leaves your files and your agents' conversations alone.")
                    }
                } else {
                    Button { client.press(button.press) } label: {
                        switch button.press {
                        case .run: runLabel(button.title, systemImage: "play.fill")
                        case .stop: runLabel(button.title, systemImage: "stop.fill")
                        // Made a little smaller rather than cut short, on a phone's narrow bar.
                        default: Text(button.title).lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                    .buttonStyle(.panel(button.press == .run ? .run : button.press == .stop ? .stop : .outline))
                    .disabled(!button.isEnabled)
                    .accessibilityHint(button.hint)
                }
            }
            if let menu = client.restartMenu { RestartMenuButton(menu: menu, iconOnly: compact) }
        }
    }

    @ViewBuilder
    private func runLabel(_ title: String, systemImage: String) -> some View {
        if symbolsOnly {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    private func rehearseItem(_ rehearse: PressButton) -> some View {
        Button(rehearse.title, systemImage: "theatermasks") { client.press(rehearse.press) }
            .disabled(!rehearse.isEnabled)
            .accessibilityHint(rehearse.hint)
    }
}

/// The Mac's Restart menu, at the end of the run bar for a device that may control: all the agents, all but the
/// orchestrator, the ones selected on this device's canvas, and the ones with new settings waiting. Each keeps its
/// conversation so far. Those in the middle of a task are asked about first.
struct RestartMenuButton: View {
    @Environment(RemoteClient.self) private var client
    @Environment(\.horizontalSizeClass) private var sizeClass
    let menu: RestartMenu
    /// The arrow alone, with no name, where the bar is short of room. A phone's bar always is.
    var iconOnly = false

    var body: some View {
        let isSending = client.mirror.waiting.values.contains { if case .restartAgents = $0 { true } else { false } }
        Menu {
            ForEach(menu.items) { item in
                if item.startsGroup { Divider() }
                Button(item.title) { client.press(.restart(item.which)) }
                    .disabled(!item.isEnabled)
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "arrow.clockwise")
                // A phone's bar is narrow: the arrow alone says it, and VoiceOver reads the name.
                if sizeClass != .compact, !iconOnly { Text("Restart").lineLimit(1) }
                // A phone short of room keeps the arrow that says what it is, and leaves out the one that says it opens a menu.
                if !(iconOnly && sizeClass == .compact) {
                    Image(systemName: "chevron.down").dsIcon(DS.IconSize.s, .semibold).foregroundStyle(Theme.inkSecondary.ui)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.panel(.outline))
        .disabled(isSending)
        .accessibilityLabel("Restart agents")
        .accessibilityHint("Restarts every agent, all but the orchestrator, the agents selected on the canvas, or the ones with new settings waiting. Each keeps its conversation so far.")
    }
}

/// Something the Mac wouldn't do, in its own words. A tap puts it away, and so does the next thing that works.
struct RefusalNotice: View {
    let text: String
    /// Which side it keeps to where there is more room than it needs.
    var alignment = Alignment.trailing
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(text)
                    .textRole(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark").dsIcon(DS.IconSize.l, .semibold).accessibilityHidden(true)
            }
            .foregroundStyle(Theme.failInk.ui)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .frame(minHeight: Theme.Touch.target)
            .background(Theme.failTint.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.failInk.ui, lineWidth: Theme.Stroke.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: DS.Size.messageWidth, alignment: alignment)
        .accessibilityHint("Puts this message away.")
    }
}

/// The answer to a held message, under the message in a card's details: the card's own buttons, and for an
/// approval the Mac's way of changing the message before it is sent on.
struct HoldAnswer: View {
    @Environment(RemoteClient.self) private var client
    let hold: PendingHold
    let buttons: [PressButton]
    /// The message as the person is rewriting it. Nil until they ask to.
    @State private var draft: String?

    var body: some View {
        if hold.kind == .approval {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if let draft {
                    TextEditor(text: Binding { draft } set: { self.draft = $0 })
                        .textRole(.body)
                        .foregroundStyle(Theme.ink.ui)
                        .scrollContentBackground(.hidden)
                        .frame(height: DS.Size.textAreaTall)
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, Theme.Space.xs)
                        .background(Theme.surface.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.live.ui))
                        .accessibilityLabel("The message to send on")
                }
                HStack(spacing: Theme.Space.s) {
                    ForEach(buttons.filter { !$0.isMain }) { button in
                        Button(button.title) { client.press(button.press) }
                            .buttonStyle(.panel())
                            .disabled(!button.isEnabled)
                            .accessibilityHint(button.hint)
                    }
                    Spacer(minLength: 0)
                    Button(draft == nil ? "Edit" : "Don't edit") { draft = draft == nil ? hold.text : nil }
                        .buttonStyle(.panel(.quiet))
                        .accessibilityHint(draft == nil ? "Lets you change the message before approving it." : "Puts the message back as it was.")
                    let edited = draft.map { $0 != hold.text } ?? false
                    Button(edited ? "Approve edited" : "Approve") { client.press(.approve(holdID: hold.id, text: draft ?? hold.text)) }
                        .buttonStyle(.panel(.filled))
                        .disabled(buttons.contains { !$0.isEnabled })
                        .accessibilityHint("Sends the message on along the Approved link.")
                }
            }
        } else {
            HStack(spacing: Theme.Space.s) {
                ForEach(buttons) { button in
                    if button.isMain { Spacer(minLength: 0) }
                    Button(button.title) { client.press(button.press) }
                        .buttonStyle(.panel(button.isMain ? .filled : .outline))
                        .disabled(!button.isEnabled)
                        .accessibilityHint(button.hint)
                }
            }
        }
    }
}

/// What can be done to the selected card from here: start or restart its agent, put its settings back or restart it
/// to apply them, run the flow from a Start card, and start a run at it.
struct CardActions: View {
    /// The buttons a card's details have at their foot, besides "Run from here…".
    static func buttons(for card: Card, in abilities: Abilities) -> [PressButton] {
        switch card.kind {
        case .agent: abilities.details[card.id] ?? []
        case .start: [abilities.starts[card.id]].compactMap { $0 }
        default: []
        }
    }

    @Environment(RemoteClient.self) private var client
    let card: Card
    let buttons: [PressButton]
    let canRunFrom: Bool
    /// The last message that reached the card in the run on show, which "Run from here" starts with.
    let lastMessage: String
    /// The message the run will start with. Nil until "Run from here…" is pressed.
    @State private var draft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let draft {
                Text("The message \(card.name) gets").textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
                TextEditor(text: Binding { draft } set: { self.draft = $0 })
                    .textRole(.body)
                    .foregroundStyle(Theme.ink.ui)
                    .scrollContentBackground(.hidden)
                    .frame(height: DS.Size.textArea)
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.vertical, Theme.Space.xs)
                    .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.hairline.ui))
                    .accessibilityLabel("The message \(card.name) gets")
                HStack(spacing: Theme.Space.s) {
                    Button("Cancel") { self.draft = nil }.buttonStyle(.panel(.quiet))
                    Spacer(minLength: 0)
                    Button("Run from here") {
                        self.draft = nil
                        Task { await client.run(from: card.id, text: draft) }
                    }
                    .buttonStyle(.panel(.filled))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityHint("Starts a run on your Mac at this card, skipping everything that comes before.")
                }
            } else {
                let runFrom = Button("Run from here…") { draft = lastMessage }
                    .buttonStyle(.panel(.quiet))
                    .fixedSize()
                    .accessibilityHint("Starts a run at this card with a message you give it, skipping everything that comes before.")
                // Side by side where both names fit whole, and one above the other where they don't.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        if canRunFrom { runFrom }
                        Spacer(minLength: 0)
                        PressButtons(buttons: buttons, about: card.name).fixedSize()
                    }
                    VStack(alignment: .trailing, spacing: Theme.Space.s) {
                        PressButtons(buttons: buttons, about: card.name)
                        if canRunFrom { runFrom }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        // "Run from here…" was chosen from the card's menu on the canvas: the same question is asked here.
        .onChange(of: client.controls.runFrom, initial: true) { _, wanted in
            guard wanted == card.id else { return }
            client.controls.runFrom = nil
            if canRunFrom { draft = lastMessage }
            #if DEBUG
            // A test can't see the box that has just come up.
            client.controls.debugNote("asked:runFrom:\(card.name)", canRunFrom ? nil : "This card can't be run from.")
            #endif
        }
    }
}

/// Turning a held message down: what it says, and room for a few words on why. The note is the Mac's:
/// it goes out ahead of the message along the Rejected link, and may be left empty.
private struct RejectSheet: View {
    @Environment(RemoteClient.self) private var client
    let ask: Ask
    let name: String
    let from: String
    let text: String
    @State private var note = ""
    @FocusState private var isWriting: Bool

    var body: some View {
        AskSheet(title: "Reject this message?") {
            Text("From \(from), held at \(name)").textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
            LongText(text: text, lines: 6).foregroundStyle(Theme.ink.ui).fieldBox()
            TextField("Why you're rejecting it (optional)", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .textRole(.body)
                .foregroundStyle(Theme.ink.ui)
                .fieldBox()
                .focused($isWriting)
                #if DEBUG
                // A test can't tap the box, and what the sheet does with the keyboard up has to be seen.
                .task { if DebugLaunch.writesNote { isWriting = true } }
                #endif
            Text("The message goes on along the Rejected link, with your reason ahead of it if you give one.")
                .textRole(.caption)
                .foregroundStyle(Theme.inkSecondary.ui)
                .fixedSize(horizontal: false, vertical: true)
        } action: {
            Button("Reject") { client.confirm(ask, note: note) }.buttonStyle(.panel(.filled))
        }
    }
}

/// Letting a script's command run: the whole command first, and that it runs on the Mac.
private struct AllowSheet: View {
    @Environment(RemoteClient.self) private var client
    let ask: Ask
    let name: String
    let command: String

    var body: some View {
        AskSheet(title: "Allow \(name) to run this?") {
            Text("This command will run on your Mac, in the project's folder, as if you had typed it in Terminal. Read all of it first.")
                .textRole(.body)
                .foregroundStyle(Theme.ink.ui)
                .fixedSize(horizontal: false, vertical: true)
            // All of it, however long: nothing is cut short behind a button here.
            Text(command)
                .textRole(.monoCaption)
                .foregroundStyle(Theme.ink.ui)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldBox()
                .accessibilityLabel("The command: \(command)")
            Text("This card won't ask again unless the command changes.")
                .textRole(.caption)
                .foregroundStyle(Theme.inkSecondary.ui)
                .fixedSize(horizontal: false, vertical: true)
        } action: {
            Button("Allow and run") { client.confirm(ask) }.buttonStyle(.panel(.filled))
        }
    }
}

/// The frame of a question asked in a sheet: what is being asked, what to read, and Cancel beside the answer.
private struct AskSheet<Content: View, Action: View>: View {
    @Environment(RemoteClient.self) private var client
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var action: Action
    /// How tall what is asked is, and the strip of buttons under it, once they have been laid out.
    @State private var askedHeight: CGFloat = 0
    @State private var footHeight: CGFloat = 0

    /// The sheet's height where it comes up from the foot of the screen, as on an iPhone: as tall as what it
    /// asks, and no taller. Left to itself it would be the whole screen, with the question adrift in the middle.
    private var height: CGFloat { askedHeight > 0 && footHeight > 0 ? askedHeight + footHeight + 1 : 420 }

    var body: some View {
        let asked = VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title)
                .textRole(.heading)
                .foregroundStyle(Theme.ink.ui)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        VStack(spacing: 0) {
            // As tall as what it asks, and no taller. Only something too long for the room it has scrolls: a
            // long command, or any of it once the keyboard is up. It is one view either way, so the box
            // being written in is never taken away from under the keyboard.
            ScrollView {
                asked.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { askedHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(idealHeight: askedHeight > 0 ? askedHeight : nil)
            Hairline()
            HStack(spacing: Theme.Space.s) {
                Button("Cancel") { client.controls.asking = nil }.buttonStyle(.panel(.quiet))
                Spacer(minLength: 0)
                action
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.bar.ui)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footHeight = $0 }
        }
        .background(Theme.surface.ui)
        // Where the sheet is a panel in the middle of the screen, as on an iPad.
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        // Where it comes up from the foot of the screen.
        .presentationDetents([.height(height)])
        .presentationBackground(Theme.surface.ui)
    }
}

private struct AsksBeforeActing: ViewModifier {
    @Environment(RemoteClient.self) private var client
    /// True for the one inside the details' sheet on an iPhone, which asks while that sheet is up. The one
    /// on the whole app asks the rest of the time. Only one of them ever has the question.
    let overSheet: Bool

    private var isMine: Bool { overSheet ? client.panel.isSheetSettled : !client.isSheetUp }

    /// What is being asked, if it is asked the way this binding is for: in a sheet, or in an alert.
    private func asking(sheet: Bool) -> Binding<Ask?> {
        Binding {
            !isMine ? nil : client.controls.asking.flatMap { $0.isSheet == sheet ? $0 : nil }
        } set: { new in
            if new == nil, isMine, client.controls.asking?.isSheet == sheet { client.controls.asking = nil }
        }
    }

    func body(content: Content) -> some View {
        let alert = asking(sheet: false)
        content
            .sheet(item: asking(sheet: true)) { ask in
                switch ask {
                case .reject(_, let name, let from, let text): RejectSheet(ask: ask, name: name, from: from, text: text)
                case .allow(_, let name, let command): AllowSheet(ask: ask, name: name, command: command)
                case .stop, .restart, .restartOrchestrator, .restartAgents, .runForReal: EmptyView()
                }
            }
            .alert(alertTitle, isPresented: Binding { alert.wrappedValue != nil } set: { if !$0 { alert.wrappedValue = nil } },
                   presenting: alert.wrappedValue) { ask in
                switch ask {
                case .stop: Button("Stop", role: .destructive) { client.confirm(ask) }
                case .restartOrchestrator, .restartAgents: Button("Restart") { client.confirm(ask) }
                case .runForReal: Button("Run for Real") { client.confirm(ask) }
                default: Button("Restart agent") { client.confirm(ask) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { ask in
                switch ask {
                case .stop: Text("The run on your Mac stops where it is.")
                case .restart(_, _, let isWorking):
                    Text(isWorking ? "Restarting interrupts what the agent is doing now. It keeps its conversation so far." : "The agent keeps its conversation so far.")
                case .restartOrchestrator(let isWorking):
                    Text(isWorking ? "Restarting interrupts what the orchestrator is doing now. It keeps its conversation so far." : "The orchestrator keeps its conversation so far.")
                case .restartAgents(_, let busy):
                    // The Mac's words for the same question.
                    Text("Restarting cuts short what \(busy.count == 1 ? "it is" : "they are") doing now, or a question \(busy.count == 1 ? "it is" : "they are") waiting on you to answer. Every agent keeps its conversation so far.")
                // The Mac's words for the same question.
                case .runForReal: Text("The rehearsal stops where it is, and the flow runs with its own agents.")
                default: Text("")
                }
            }
            // What was being asked about may have gone while the question was up: answered on the Mac, or the link dropped.
            .onChange(of: client.abilities) { _, now in
                if let ask = client.controls.asking, !now.stillOffers(ask) { client.controls.asking = nil }
            }
    }

    /// "A", "A and B", "A, B and C".
    private static func list(_ names: [String]) -> String {
        names.count <= 1 ? names.first ?? "" : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    private var alertTitle: String {
        switch client.controls.asking {
        case .restart(_, let name, _): "Restart \(name)?"
        case .restartOrchestrator: "Restart the orchestrator?"
        case .restartAgents(_, let busy): "Restart while \(Self.list(busy)) \(busy.count == 1 ? "is" : "are") busy?"
        case .runForReal: "Stop the rehearsal and run for real?"
        default: "Stop the run?"
        }
    }
}

extension Abilities {
    /// Whether what a question is about can still be done.
    func stillOffers(_ ask: Ask) -> Bool {
        let presses = (bar + cards.values.joined() + details.values.joined() + [orchestrator].compactMap { $0 }).map(\.press)
        return switch ask {
        case .stop: presses.contains(.stop)
        case .restart(let cardID, _, _): presses.contains(.startAgent(cardID: cardID))
        case .allow(let holdID, _, _): presses.contains(.allow(holdID: holdID))
        case .reject(let holdID, _, _, _): presses.contains(.reject(holdID: holdID))
        case .restartOrchestrator: presses.contains(.startOrchestrator)
        case .restartAgents: canAct
        // Only while the rehearsal goes: once it ends, Run runs without asking.
        case .runForReal: isRehearsing
        }
    }
}

extension View {
    /// Puts up the questions that are asked before a press is sent: stopping a run, restarting an agent
    /// that is running, letting a command run, and the note that goes with a rejection.
    func asksBeforeActing(overSheet: Bool = false) -> some View { modifier(AsksBeforeActing(overSheet: overSheet)) }
}

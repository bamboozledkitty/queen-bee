import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// What floats over the top of the canvas when there is something to say about the flow as a whole: the way back
/// out of a sub-flow, the Mac's message when something didn't work, which cards are waiting on the person, that an
/// earlier run is on show, and the note an empty flow shows. Nothing is there when none of them is.
struct CanvasBanners: View {
    @Environment(RemoteClient.self) private var client

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let snapshot = client.mirror.snapshot {
                if let parent = client.parentOfOpenFlow { BackToParent(parent: parent) }
                if let workplace = snapshot.run.workplace { WorkplaceTag(text: workplace) }
                if let banner = snapshot.run.banner, client.canvas.viewedRun == nil { FailureBanner(text: banner) }
                let waiting = WaitingCard.all(in: snapshot)
                if !waiting.isEmpty { NeedsYouBanner(waiting: waiting) }
                if let run = client.canvas.viewedRun {
                    EarlierRunNotice(run: run)
                        .padding(.horizontal, Theme.Space.m)
                        .floatingPanel()
                }
                if client.canvas.runHeldBack && client.canvas.viewedRun == nil {
                    Text("A run is going, so the earlier run can't be shown yet. It stays in Runs for when this one ends.")
                        .textRole(.caption)
                        .foregroundStyle(Theme.ink.ui)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, DS.Space.tight)
                        .floatingPanel()
                }
                if let callout = client.callout { CalloutView(callout: callout) }
            }
        }
        .frame(maxWidth: DS.Size.bannerWidth, alignment: .leading)
    }
}

/// One line over the canvas saying that a card is waiting on the person, with a button that goes to it. The
/// decision itself is asked once, on the card and in its details, and not here a third time. With several waiting
/// the line names the first, in canvas order, and counts the rest; the Needs you list has them all. An agent waiting
/// in its terminal gets the button that opens it, which is what answers it, and what can't be answered from here
/// is said under the line.
private struct NeedsYouBanner: View {
    @Environment(RemoteClient.self) private var client
    let waiting: [WaitingCard]

    var body: some View {
        if let first = waiting.first {
            let abilities = client.abilities
            let others = waiting.count - 1
            let summary = "\(first.name)\(others > 0 ? " and \(others) more" : "") · waiting for you"
            HStack(spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(summary)
                        .textRole(.label)
                        .foregroundStyle(Theme.liveInk.ui)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let answerLine = abilities.answerLine {
                        Text(answerLine).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if abilities.inTerminal.contains(first.id), client.terminals.sizes[first.id] != nil {
                    OpenTerminalButton(cardID: first.id, name: first.name)
                } else {
                    Button("Go to") { client.go(to: first) }
                        .buttonStyle(.panel(.outline))
                        .accessibilityLabel("Go to \(first.name)")
                        .accessibilityHint("Goes to this card on the canvas, where it can be answered.")
                }
            }
            .padding(.leading, Theme.Space.m)
            .padding(.trailing, Theme.Space.m)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
            .liveRule()
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .floatingPanel()
            .accessibilityElement(children: .contain)
        }
    }
}

/// For an agent that is waiting on the person in its terminal: opens the terminal full screen with the keys
/// out, which is what answers it.
struct OpenTerminalButton: View {
    @Environment(RemoteClient.self) private var client
    let cardID: String
    let name: String
    static let title = "Open its terminal"

    var body: some View {
        Button(Self.title) { client.openTerminal(cardID, keys: true) }
            .buttonStyle(.panel(.live))
            .accessibilityLabel("\(Self.title), \(name)")
            .accessibilityHint("Opens \(name)'s terminal full screen, with keys to answer it.")
    }
}

extension RemoteClient {
    /// Goes to a card that is waiting: puts it in the middle of the canvas and selects it, which brings up its
    /// details, where what it is waiting with can be read.
    func go(to card: WaitingCard) {
        canvas.select(.card(card.id))
        canvas.centre(onCard: card.id)
    }
}

/// Where the flow works, as the Mac's branch chip says it: a branch, or a worktree's branch. Only shown: it is chosen on the Mac.
struct WorkplaceTag: View {
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "arrow.triangle.branch")
                .dsIcon(DS.IconSize.l, .semibold)
                .foregroundStyle(Theme.inkSecondary.ui)
                .accessibilityHidden(true)
            // A long branch name is cut short in the middle rather than taking over the top of the canvas.
            Text(text)
                .textRole(.monoCaption)
                .foregroundStyle(Theme.ink.ui)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: DS.Size.chip)
        .floatingPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Works on \(text)")
        .accessibilityHint("Where this flow works. It is changed on your Mac.")
    }
}

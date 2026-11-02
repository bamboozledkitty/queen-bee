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

/// The cards waiting on the person, in canvas order. Tapping one goes to it. When this device may answer,
/// each has its card's buttons under it, at full size however small the card is on screen. An agent waiting
/// in its terminal has a button that opens the terminal. What can't be answered from here is said in the last line.
private struct NeedsYouBanner: View {
    @Environment(RemoteClient.self) private var client
    let waiting: [WaitingCard]
    /// More than this many and the rest are counted, so the banner never covers the canvas it points at.
    private static let most = 4

    var body: some View {
        let abilities = client.abilities
        VStack(alignment: .leading, spacing: 0) {
            Label(waiting.count == 1 ? "1 needs you" : "\(waiting.count) need you", systemImage: "hand.raised")
                .textRole(.label)
                .foregroundStyle(Theme.liveInk.ui)
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, minHeight: DS.Size.rowCompact, alignment: .leading)
                .background(Theme.liveTint.ui)
                .accessibilityAddTraits(.isHeader)
            ForEach(waiting.prefix(Self.most)) { card in
                Hairline()
                Button { client.go(to: card) } label: {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: CanvasGeometry.icon(for: card.kind))
                            .dsIcon(DS.IconSize.xl)
                            .frame(width: DS.Size.iconSlotWide)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(card.name).textRole(.label).lineLimit(1)
                            Text(card.reason).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: Theme.Space.s)
                        Image(systemName: "scope").dsIcon(DS.IconSize.xl).foregroundStyle(Theme.inkSecondary.ui)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.ink.ui)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, DS.Space.tight)
                    .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.name). \(card.reason).")
                .accessibilityHint("Goes to this card on the canvas.")
                if let buttons = abilities.cards[card.id] {
                    PressButtons(buttons: buttons, about: card.name)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.bottom, Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else if abilities.inTerminal.contains(card.id), client.terminals.sizes[card.id] != nil {
                    OpenTerminalButton(cardID: card.id, name: card.name)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.bottom, Theme.Space.s)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            let more = waiting.count > Self.most ? "And \(waiting.count - Self.most) more." : nil
            let last = [more, abilities.answerLine].compactMap { $0 }.joined(separator: " ")
            if !last.isEmpty {
                Hairline()
                Text(last)
                    .textRole(.caption)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .floatingPanel()
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.live.ui, lineWidth: Theme.Stroke.card))
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

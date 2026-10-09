import AppKit
import QueenBeeCore
import SwiftUI

@main
struct QueenBeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @FocusedValue(\.project) private var project

    var body: some Scene {
        WindowGroup(id: "project", for: URL.self) { $folder in
            ProjectWindow(folder: $folder)
        }
        .defaultSize(width: 1500, height: 950)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Flow") { project?.newFlow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(project == nil)
            }
            CommandMenu("Flow") {
                Button("Run") { if let c = project?.current { Task { await c.run() } } }
                    .keyboardShortcut("r")
                    .disabled(project?.current == nil || project?.current?.isRunning == true)
                Button("Stop") { if let c = project?.current { Task { await c.stop() } } }
                    .keyboardShortcut(".")
                    .disabled(project?.current?.isRunning != true)
                Divider()
                Menu("Add Card") {
                    ForEach(CardKindMenu.kinds, id: \.self) { kind in
                        Button(kind.label) { project?.current?.addCard(kind) }
                    }
                }
                .disabled(project?.current == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { project?.current?.canvas?.zoom(by: 1.25) }
                    .keyboardShortcut("=")
                Button("Zoom Out") { project?.current?.canvas?.zoom(by: 0.8) }
                    .keyboardShortcut("-")
                Button("Actual Size") { project?.current?.canvas?.zoomToActualSize() }
                    .keyboardShortcut("0")
                Button("Zoom to Fit") { project?.current?.canvas?.zoomToFit() }
                    .keyboardShortcut("9")
                Divider()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var termSignal: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A second copy would fight the first over the socket: hand over to the first and quit.
        let me = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != me }
        if let first = others.first, !TestHarness.isEnabled {
            first.activate()
            exit(0)
        }
        AppServices.shared.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill` and a logout send SIGTERM, which would skip applicationWillTerminate. Turn it into a normal quit.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSignal = source

        // A second copy of the app, which is what a test run is, starts without a window. Ask for one.
        if TestHarness.isEnabled {
            Task {
                try? await Task.sleep(for: .seconds(1))
                guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                let file = NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.items.contains { $0.keyEquivalent == "n" } }
                if let item = file?.items.first(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }), let action = item.action {
                    NSApp.sendAction(action, to: item.target, from: item)
                }
            }
        }
    }

    /// Stops every session the app started, so no `claude` process outlives the window it ran in.
    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.shutDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

}

enum CardKindMenu {
    static let kinds: [CardKind] = [.agent, .start, .ifElse, .switchCard, .and, .or, .prompt, .loop, .end, .note]
}

struct ProjectKey: FocusedValueKey {
    typealias Value = ProjectModel
}

extension FocusedValues {
    var project: ProjectModel? {
        get { self[ProjectKey.self] }
        set { self[ProjectKey.self] = newValue }
    }
}

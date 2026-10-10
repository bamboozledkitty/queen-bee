import CoreServices
import Foundation
import QueenBeeCore

/// Which schedules the person has turned on. A schedule starts runs with nobody at the
/// keyboard, so one only counts once it has been set or switched on in this app, and only for
/// the command it was set with: change what the run starts with and it is off again.
enum ScheduleArming {
    private static func fingerprint(_ trigger: Trigger, command: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return ((try? encoder.encode(trigger)) ?? Data()).sha256Hex + "\u{0}" + command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isArmed(_ trigger: Trigger, command: String, scope: String, cardID: String) -> Bool {
        ConsentStore.schedules.isGranted(fingerprint(trigger, command: command), scope: scope, cardID: cardID)
    }

    static func arm(_ trigger: Trigger?, command: String, scope: String, cardID: String) {
        ConsentStore.schedules.grant(trigger.map { fingerprint($0, command: command) }, scope: scope, cardID: cardID)
    }
}

/// Watches a file or folder, and everything inside a folder, for changes.
nonisolated final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable ([String]) -> Void

    /// `onChange` gets every path in a batch of changes. One batch can hold a real change and the app's own.
    init?(url: URL, onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, count > 0 else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange((unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? [])
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        // Changes within two seconds of each other arrive as one.
        guard let made = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                             FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2, flags) else { return nil }
        stream = made
        FSEventStreamSetDispatchQueue(made, .main)
        FSEventStreamStart(made)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

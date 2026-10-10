import CoreServices
import CryptoKit
import Foundation
import QueenBeeCore

/// Which schedules the person has turned on. A schedule starts runs with nobody at the
/// keyboard, so one only counts once it has been set or switched on in this app. That is kept
/// in the app's own settings, never in the flow file, so a flow that arrives with a schedule
/// in it stays quiet until its owner agrees.
enum ScheduleArming {
    private static let key = "armedSchedules"

    private static func fingerprint(_ trigger: Trigger) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(trigger)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isArmed(_ trigger: Trigger, flowID: String, cardID: String) -> Bool {
        let armed = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return armed["\(flowID)/\(cardID)"] == fingerprint(trigger)
    }

    static func arm(_ trigger: Trigger?, flowID: String, cardID: String) {
        var armed = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        armed["\(flowID)/\(cardID)"] = trigger.map(fingerprint)
        UserDefaults.standard.set(armed, forKey: key)
    }
}

/// Watches a file or folder, and everything inside a folder, for changes.
nonisolated final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable (String) -> Void

    init?(url: URL, onChange: @escaping @Sendable (String) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info, count > 0 else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String])?.first ?? ""
            watcher.onChange(changed)
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

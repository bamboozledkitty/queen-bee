import Foundation
import Security

/// One place keys can be kept, by account name: a keychain, or memory in a test.
public protocol KeyStore {
    func lookUp(_ account: String) -> StoredKey
    /// `errSecSuccess`, or why the key couldn't be kept. A key already kept under that name is replaced.
    func write(_ data: Data, _ account: String) -> OSStatus
    /// `errSecSuccess` or `errSecItemNotFound` when no key is kept under that name any more, or why it couldn't be deleted.
    @discardableResult func delete(_ account: String) -> OSStatus
    /// The names of every key kept here. Empty when they can't be listed.
    func accounts() -> [String]
}

/// Keys kept in `modern`, with any an earlier version kept in `legacy` moved over the first time each is read:
/// written to `modern`, read back from it, and only then deleted from `legacy`. When `modern` can't be used at
/// all, as in a copy of the app built without the entitlement it needs, keys stay in `legacy`.
///
/// No step here can lose a key: a key is never deleted from one place until it has been read back from the
/// other, and a key `modern` couldn't say anything about is looked for in `legacy` too.
public struct MigratingKeyStore: KeyStore {
    public let modern: any KeyStore
    public let legacy: any KeyStore

    public init(modern: any KeyStore, legacy: any KeyStore) {
        self.modern = modern
        self.legacy = legacy
    }

    public func lookUp(_ account: String) -> StoredKey {
        switch modern.lookUp(account) {
        case .found(let key):
            return .found(key)
        case .missing:
            let old = legacy.lookUp(account)
            if case .found(let key) = old, modern.write(key, account) == errSecSuccess, modern.lookUp(account) == .found(key) {
                legacy.delete(account)
            }
            return old
        case .unreadable(let status):
            // Locked, or not usable at all. The key may be in either place, and isn't known to be gone from either.
            let old = legacy.lookUp(account)
            if case .found = old { return old }
            return status == errSecMissingEntitlement ? old : .unreadable(status)
        }
    }

    public func write(_ data: Data, _ account: String) -> OSStatus {
        let status = modern.write(data, account)
        guard status == errSecSuccess else {
            // `modern` is read first, so an older key left there would be found in place of the new one kept in
            // `legacy`. The new key is kept in `legacy` before the older one goes, so a failure on the way never
            // leaves no key at all; if the older one can't be seen to have gone, the write fails and it still works.
            let held = modern.lookUp(account)
            if case .unreadable(let why) = held, why != errSecMissingEntitlement { return status }
            let kept = legacy.write(data, account)
            guard kept == errSecSuccess else { return kept }
            guard case .found = held else { return kept }
            modern.delete(account)
            if case .found = modern.lookUp(account) {
                legacy.delete(account)
                return status
            }
            return kept
        }
        // An older copy of the key would otherwise be found again if `modern` ever couldn't be read.
        legacy.delete(account)
        return status
    }

    /// Deleted from both places. The first that couldn't be deleted says why; a place that can't be used at all
    /// holds nothing to delete.
    @discardableResult public func delete(_ account: String) -> OSStatus {
        let statuses = [modern.delete(account), legacy.delete(account)]
        return statuses.first { !Self.gone($0) } ?? errSecSuccess
    }

    /// Whether a delete that answered `status` leaves no key behind.
    public static func gone(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement
    }

    public func accounts() -> [String] { Array(Set(modern.accounts() + legacy.accounts())).sorted() }
}

/// Keys in memory, for tests and for a test copy of the app.
public final class MemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: Data] = [:]
    /// What `lookUp` answers instead of looking, and what `write` and `delete` fail with, when set.
    public var lookUpFails: OSStatus?
    public var writeFails: OSStatus?
    public var deleteFails: OSStatus?

    public init(_ keys: [String: Data] = [:]) { self.keys = keys }

    public func lookUp(_ account: String) -> StoredKey {
        if let lookUpFails { return .unreadable(lookUpFails) }
        return lock.withLock { keys[account] }.map(StoredKey.found) ?? .missing
    }

    public func write(_ data: Data, _ account: String) -> OSStatus {
        if let writeFails { return writeFails }
        lock.withLock { keys[account] = data }
        return errSecSuccess
    }

    @discardableResult public func delete(_ account: String) -> OSStatus {
        if let deleteFails { return deleteFails }
        return lock.withLock { keys.removeValue(forKey: account) } == nil ? errSecItemNotFound : errSecSuccess
    }

    public func accounts() -> [String] { lock.withLock { Array(keys.keys) }.sorted() }

    public var stored: [String: Data] { lock.withLock { keys } }
}

/// Keys in one file that only this account can read, for a copy of the app built from source. Such a copy is
/// signed afresh by every build, and the login keychain asks again each time whether the "new" app may read what
/// the last one kept. A file asks nobody.
///
/// Several such copies can share the file, so changes take a lock other processes see too, and the file is always
/// replaced whole: reading it needs no lock. It is left out of backups, as a key in the Keychain would be.
public final class FileKeyStore: KeyStore, @unchecked Sendable {
    public let url: URL
    /// Where a file that can't be read is moved when a key has to be written.
    public var damagedURL: URL { url.deletingPathExtension().appendingPathExtension("unreadable.json") }
    private let lock = NSLock()
    /// What the file held when it last changed, so a file that hasn't changed isn't decoded again.
    private var loaded: (stamp: [FileAttributeKey: AnyHashable], keys: [String: Data])?

    public init(url: URL) { self.url = url }

    public func lookUp(_ account: String) -> StoredKey {
        guard let keys = load() else { return .unreadable(errSecIO) }
        return keys[account].map(StoredKey.found) ?? .missing
    }

    public func write(_ data: Data, _ account: String) -> OSStatus {
        changing {
            var kept = load()
            // Nothing can be read from it, and a device can't be paired while it is in the way. It is kept aside.
            if kept == nil {
                guard FileManager.default.fileExists(atPath: damagedURL.path) ? unlink(damagedURL.path) == 0 : true,
                      rename(url.path, damagedURL.path) == 0 else { return errSecIO }
                kept = [:]
            }
            kept?[account] = data
            return kept.map(save) ?? errSecIO
        }
    }

    @discardableResult public func delete(_ account: String) -> OSStatus {
        changing {
            guard var keys = load() else { return errSecIO }
            guard keys.removeValue(forKey: account) != nil else { return errSecItemNotFound }
            return save(keys)
        }
    }

    public func accounts() -> [String] { load().map { Array($0.keys).sorted() } ?? [] }

    /// One change at a time, across every copy of the app using this file.
    private func changing(_ change: () -> OSStatus) -> OSStatus {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return errSecIO
        }
        let held = open(url.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard held >= 0 else { return errSecIO }
        defer { close(held) }
        guard flock(held, LOCK_EX) == 0 else { return errSecIO }
        return change()
    }

    /// Every key kept, or nil when the file is there but can't be read: a key in it isn't known to be gone.
    private func load() -> [String: Data]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return FileManager.default.fileExists(atPath: url.path) ? nil : [:]
        }
        // Every save makes a new file, so its number and time change together.
        let stamp = attributes.filter { $0.key == .systemFileNumber || $0.key == .modificationDate || $0.key == .size }
            .compactMapValues { $0 as? AnyHashable }
        if let kept = lock.withLock({ loaded }), kept.stamp == stamp { return kept.keys }
        guard let data = try? Data(contentsOf: url), let keys = try? JSONDecoder().decode([String: Data].self, from: data) else { return nil }
        lock.withLock { loaded = (stamp, keys) }
        return keys
    }

    private func save(_ keys: [String: Data]) -> OSStatus {
        guard let data = try? JSONEncoder().encode(keys) else { return errSecIO }
        // A name of its own, and made unreadable to anyone else before the keys go in. Replaced whole, so a crash
        // leaves the old file.
        let next = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        let file = open(next.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
        guard file >= 0 else { return errSecIO }
        do {
            try FileHandle(fileDescriptor: file, closeOnDealloc: true).write(contentsOf: data)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var named = next
            try named.setResourceValues(values)
            guard rename(next.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            return errSecSuccess
        } catch {
            unlink(next.path)
            return errSecIO
        }
    }
}

/// How the Mac names each paired device's key: `device-` and the device's id.
public enum DeviceKeys {
    public static let prefix = "device-"

    public static func account(_ id: String) -> String { prefix + id }

    /// The ids of the devices whose keys are among `accounts`, less those in `removed`: devices that were unpaired
    /// and whose key couldn't be deleted, which would otherwise come back when the list is made again from the keys.
    public static func pairedIDs(in accounts: [String], leavingOut removed: Set<String>) -> [String] {
        accounts.compactMap { account in
            guard account.hasPrefix(prefix) else { return nil }
            let id = String(account.dropFirst(prefix.count))
            return removed.contains(id) ? nil : id
        }
    }
}

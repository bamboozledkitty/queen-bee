import Foundation
import Testing
@testable import QueenBeeCore

@Suite struct TranscriptsTests {
    @Test func aFolderIsNamedAsClaudeCodeNamesIt() {
        #expect(Transcripts.folderName(for: "/Volumes/Work/my project.v2") == "-Volumes-Work-my-project-v2")
        // Each UTF-16 unit is one character, so an emoji is two.
        #expect(Transcripts.folderName(for: "/a/é😀") == "-a----")
    }

    @Test func aLongPathMatchesOnItsFirstPartOnly() {
        let long = "/" + String(repeating: "a", count: 250)
        let name = String(Transcripts.folderName(for: long).prefix(200)) + "-k3x9"
        #expect(Transcripts.isFolder(name, for: long))
        #expect(!Transcripts.isFolder(String(Transcripts.folderName(for: long).prefix(200)), for: long))
        #expect(Transcripts.isFolder("-tmp-x", for: "/tmp/x"))
        #expect(!Transcripts.isFolder("-tmp-x-y", for: "/tmp/x"))
    }

    @Test func onlyAShortFolderNameIsKnownExactly() {
        #expect(Transcripts.exactFolderName(for: "/tmp/x") == "-tmp-x")
        #expect(Transcripts.exactFolderName(for: "/" + String(repeating: "a", count: 250)) == nil)
    }

    @Test func theLongestCopyIsTheLatestWhateverItsDate() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projects) }
        let id = UUID().uuidString.lowercased()
        func write(_ folder: String, _ text: String, at date: Date) throws {
            let dir = projects.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(id).jsonl")
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        // The copy left behind was touched later, but the one in use is longer.
        try write("-new", "a\nb\nc\n", at: Date(timeIntervalSince1970: 1_000))
        try write("-old", "a\n", at: Date(timeIntervalSince1970: 2_000))
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("-none"), withIntermediateDirectories: true)
        #expect(Transcripts.copies(of: id, in: projects).map { $0.deletingLastPathComponent().lastPathComponent } == ["-new", "-old"])
        // Of two the same length, the later one.
        try write("-same", "a\nb\nc\n", at: Date(timeIntervalSince1970: 3_000))
        #expect(Transcripts.copies(of: id, in: projects).first?.deletingLastPathComponent().lastPathComponent == "-same")
    }

    @Test func removingACopysTranscriptsTakesItsFoldersOnly() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projects) }
        let copy = "/tmp/rehearsals/abc123"
        let inside = "/tmp/rehearsals/abc123/App/" + String(repeating: "a", count: 250)
        let names = [Transcripts.folderName(for: copy), Transcripts.folderName(for: copy + "/App"),
                     String(Transcripts.folderName(for: inside).prefix(200)) + "-k3x9",
                     Transcripts.folderName(for: "/tmp/rehearsals"), Transcripts.folderName(for: "/tmp/rehearsals/abc1234"), "-other"]
        for name in names { try FileManager.default.createDirectory(at: projects.appendingPathComponent(name), withIntermediateDirectories: true) }
        Transcripts.removeFolder(for: copy, projects: projects)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: projects.path))
        #expect(left == [Transcripts.folderName(for: "/tmp/rehearsals"), Transcripts.folderName(for: "/tmp/rehearsals/abc1234"), "-other"])
    }

    @Test func removingALongCopysTranscriptsTakesItsFoldersOnly() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projects) }
        // The copy's id starts inside the first 200 characters of its folder's name and runs past them.
        let parent = "/" + String(repeating: "p", count: 170) + "/rehearsals"
        let copy = parent + "/1b4e28ba-2fa1-11d2-883f-0016d3cca427"
        let sibling = parent + "/9c1f0d2e-77aa-4b3e-9d10-5e6f7a8b9c0d"
        #expect(Transcripts.folderName(for: copy).count > 200)
        func cut(_ path: String, _ hash: String) -> String { String(Transcripts.folderName(for: path).prefix(200)) + "-" + hash }
        let names = [cut(copy, "a1"), cut(copy + "/App", "b2"), cut(sibling, "c3"), Transcripts.folderName(for: parent)]
        for name in names { try FileManager.default.createDirectory(at: projects.appendingPathComponent(name), withIntermediateDirectories: true) }
        Transcripts.removeFolder(for: copy, projects: projects)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: projects.path))
        #expect(left == [cut(sibling, "c3"), Transcripts.folderName(for: parent)])
    }

    @Test func aCopyWhoseNameIsAllPastTheCutGoesBySessionOnly() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projects) }
        let files = FileManager.default
        // The project's own path is past the cut, so its folder and the copy's start the same way.
        let project = "/" + String(repeating: "p", count: 230)
        let copy = project + "/.queenbee/rehearsals/1b4e28ba-2fa1-11d2-883f-0016d3cca427"
        func cut(_ path: String, _ hash: String) -> String { String(Transcripts.folderName(for: path).prefix(200)) + "-" + hash }
        let own = projects.appendingPathComponent(cut(project, "a1"))
        let copys = projects.appendingPathComponent(cut(copy, "b2"))
        #expect(own.lastPathComponent.hasPrefix(String(copys.lastPathComponent.prefix(200))))
        let standIn = UUID().uuidString.lowercased(), real = UUID().uuidString.lowercased()
        for dir in [own, copys] { try files.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data("a\n".utf8).write(to: own.appendingPathComponent("\(real).jsonl"))
        try Data("a\n".utf8).write(to: copys.appendingPathComponent("\(standIn).jsonl"))
        Transcripts.removeFolder(for: copy, sessions: [standIn], projects: projects)
        // The person's own conversation stays; the stand-in's goes.
        #expect(files.fileExists(atPath: own.appendingPathComponent("\(real).jsonl").path))
        #expect(!files.fileExists(atPath: copys.appendingPathComponent("\(standIn).jsonl").path))
    }

    @Test func removingASessionTakesItsTranscriptAndFilesOnly() throws {
        let projects = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projects) }
        let id = UUID().uuidString.lowercased()
        let other = UUID().uuidString.lowercased()
        let files = FileManager.default
        for folder in ["-project", "-project-App"] {
            let dir = projects.appendingPathComponent(folder)
            try files.createDirectory(at: dir.appendingPathComponent(id), withIntermediateDirectories: true)
            try files.createDirectory(at: dir.appendingPathComponent(other), withIntermediateDirectories: true)
            for name in ["\(id).jsonl", "\(other).jsonl", "\(id).jsonl.bak"] { try Data("a\n".utf8).write(to: dir.appendingPathComponent(name)) }
        }
        Transcripts.removeSession(id, projects: projects)
        for folder in ["-project", "-project-App"] {
            let left = Set(try files.contentsOfDirectory(atPath: projects.appendingPathComponent(folder).path))
            #expect(left == [other, "\(other).jsonl", "\(id).jsonl.bak"])
        }
        // Nothing that isn't a plain id is taken as one.
        Transcripts.removeSession("", projects: projects)
        Transcripts.removeSession("../-project", projects: projects)
        #expect(files.fileExists(atPath: projects.appendingPathComponent("-project").path))
    }

    @Test func aTranscriptLeftInAnotherFolderStartsANewConversation() {
        #expect(Transcripts.start(inFolder: true, elsewhere: true) == .resume)
        #expect(Transcripts.start(inFolder: true, elsewhere: false) == .resume)
        #expect(Transcripts.start(inFolder: false, elsewhere: true) == .freshWithNewID)
        #expect(Transcripts.start(inFolder: false, elsewhere: false) == .fresh)
    }

    @Test func summarisingMidTurnLeavesTheSessionAtWork() {
        #expect(SessionState.working.afterSessionStart(source: "compact") == .working)
        #expect(SessionState.needsYou.afterSessionStart(source: "compact") == .needsYou)
        #expect(SessionState.starting.afterSessionStart(source: "compact") == .idle)
        // Asked for with /compact, the session is back at its prompt afterwards.
        #expect(SessionState.working.afterSessionStart(source: "compact", compactedByPerson: true) == .idle)
        for source in ["startup", "resume", "clear", nil] {
            #expect(SessionState.starting.afterSessionStart(source: source) == .idle)
            #expect(SessionState.working.afterSessionStart(source: source) == .idle)
        }
    }
}

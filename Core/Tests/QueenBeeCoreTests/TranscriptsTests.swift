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

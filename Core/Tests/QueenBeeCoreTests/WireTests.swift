import Foundation
import Testing
@testable import QueenBeeCore

@Suite struct WireTests {
    @Test func framesCarryABigEndianLength() {
        let framed = Wire.frame(Data("hello".utf8))
        #expect(Array(framed) == [0, 0, 0, 5] + Array("hello".utf8))
        #expect(Array(Wire.frame(Data(count: 258)).prefix(4)) == [0, 0, 1, 2])
        #expect(Wire.frame(Data()) == Data([0, 0, 0, 0]))
    }

    @Test func unframePopsOneWholeFrameAtATime() {
        var buffer = Wire.frame(Data("one".utf8)) + Wire.frame(Data("two!".utf8)) + Wire.frame(Data())
        #expect(Wire.unframe(&buffer) == Data("one".utf8))
        #expect(Wire.unframe(&buffer) == Data("two!".utf8))
        #expect(Wire.unframe(&buffer) == Data())
        #expect(buffer.isEmpty)
        #expect(Wire.unframe(&buffer) == nil)
    }

    @Test func unframeWaitsForTheRestOfAFrame() {
        let whole = Wire.frame(Data("partial".utf8))
        var buffer = Data()
        for byte in whole.dropLast() {
            buffer.append(byte)
            #expect(Wire.unframe(&buffer) == nil)
        }
        #expect(buffer.count == whole.count - 1)
        buffer.append(whole.last!)
        #expect(Wire.unframe(&buffer) == Data("partial".utf8))
    }

    @Test func unframeWorksOnASliceThatDoesNotStartAtZero() {
        let padded = Data([9, 9, 9]) + Wire.frame(Data("x".utf8)) + Data([7])
        var buffer = padded.dropFirst(3)
        #expect(Wire.unframe(&buffer) == Data("x".utf8))
        #expect(Array(buffer) == [7])
    }

    @Test func requestsSurviveEncoding() throws {
        let request = WireRequest(kind: "route", session: "card-1", payload: ["answer": "Old pond"])
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(WireRequest.self, from: data) == request)
        #expect(try JSONValue.parse(data) == ["kind": "route", "session": "card-1", "payload": ["answer": "Old pond"]])
    }

    // MARK: A real socket

    /// Listens on a unix socket and serves one connection on a background thread: reads a framed request and
    /// writes back whatever `answer` makes of it. A nil answer holds the connection open without replying.
    private func serveOnce(at path: String, answer: @escaping @Sendable (Data) -> Data?) throws {
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listener >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(bound == 0)
        try #require(listen(listener, 1) == 0)

        Thread.detachNewThread {
            let client = accept(listener, nil, nil)
            defer { close(client); close(listener); unlink(path) }
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            var request: Data?
            while request == nil {
                let count = read(client, &chunk, chunk.count)
                guard count > 0 else { return }
                buffer.append(contentsOf: chunk[0..<count])
                request = Wire.unframe(&buffer)
            }
            guard let request, let reply = answer(request) else {
                usleep(700_000)
                return
            }
            // Two writes, so the client has to put a split reply back together.
            let framed = Array(Wire.frame(reply))
            let half = framed.count / 2
            _ = framed[..<half].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            usleep(20_000)
            _ = framed[half...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        }
    }

    private func socketPath() -> String {
        // Unix socket paths cap at 104 bytes, so keep the name short.
        NSTemporaryDirectory() + "qb-\(Flow.newID()).sock"
    }

    @Test func sendWritesOneRequestAndReadsOneReply() throws {
        let path = socketPath()
        try serveOnce(at: path) { request in
            guard let parsed = try? JSONValue.parse(request) else { return nil }
            return JSONValue.object(["echo": parsed]).data()
        }
        let request = WireRequest(kind: "may-send", session: "card-7", payload: ["to": "Reviewer", "big": .string(String(repeating: "x", count: 200_000))])
        let reply = try Wire.send(request, socketPath: path, timeout: 5)
        #expect(reply["echo"]?["kind"] == "may-send")
        #expect(reply["echo"]?["session"] == "card-7")
        #expect(reply["echo"]?["payload"]?["to"] == "Reviewer")
        #expect(reply["echo"]?["payload"]?["big"]?.stringValue?.count == 200_000)
    }

    @Test func sendThrowsWhenNothingIsListening() {
        let request = WireRequest(kind: "hook", session: "", payload: [:])
        #expect(throws: WireError.self) { try Wire.send(request, socketPath: socketPath(), timeout: 1) }
    }

    @Test func sendThrowsWhenThePathIsTooLong() {
        let request = WireRequest(kind: "hook", session: "", payload: [:])
        let path = NSTemporaryDirectory() + String(repeating: "x", count: 120) + ".sock"
        #expect(throws: WireError.self) { try Wire.send(request, socketPath: path, timeout: 1) }
    }

    @Test func sendTimesOutWhenNoReplyComes() throws {
        let path = socketPath()
        try serveOnce(at: path) { _ in nil }
        let request = WireRequest(kind: "route", session: "card-1", payload: ["answer": "hi"])
        let error = #expect(throws: WireError.self) { try Wire.send(request, socketPath: path, timeout: 0.2) }
        #expect(error?.description.contains("timed out") == true)
    }

    @Test func sendThrowsOnAReplyThatIsNotJSON() throws {
        let path = socketPath()
        try serveOnce(at: path) { _ in Data("not json".utf8) }
        let request = WireRequest(kind: "route", session: "card-1", payload: [:])
        #expect(throws: (any Error).self) { try Wire.send(request, socketPath: path, timeout: 5) }
    }
}

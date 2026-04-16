import Foundation
import Testing
@testable import sbx_ui

// MARK: - EditorPath Scope Validation

struct EditorPathTests {
    @Test func allowsPathEqualToRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let result = try EditorPath.validate(root, within: root)
        #expect(result.standardizedFileURL == root.standardizedFileURL)
    }

    @Test func allowsChildPath() throws {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let child = URL(fileURLWithPath: "/tmp/workspace/src/app.swift")
        let result = try EditorPath.validate(child, within: root)
        #expect(result.path == "/tmp/workspace/src/app.swift")
    }

    @Test func rejectsParentTraversal() {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let escapee = URL(fileURLWithPath: "/tmp/workspace/../etc/passwd")
        do {
            _ = try EditorPath.validate(escapee, within: root)
            #expect(Bool(false), "Should have thrown")
        } catch let error as EditorError {
            if case .pathOutsideWorkspace = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test func rejectsUnrelatedAbsolutePath() {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let unrelated = URL(fileURLWithPath: "/etc/passwd")
        do {
            _ = try EditorPath.validate(unrelated, within: root)
            #expect(Bool(false), "Should have thrown")
        } catch let error as EditorError {
            if case .pathOutsideWorkspace = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test func rejectsSiblingThatSharesPrefix() {
        // /tmp/workspace2 starts with the same prefix as /tmp/workspace but
        // isn't a child — the "+/" delimiter check must reject it.
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let sibling = URL(fileURLWithPath: "/tmp/workspace2/foo.txt")
        do {
            _ = try EditorPath.validate(sibling, within: root)
            #expect(Bool(false), "Should have thrown")
        } catch let error as EditorError {
            if case .pathOutsideWorkspace = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }

    @Test func relativeReturnsSuffix() {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        let child = URL(fileURLWithPath: "/tmp/workspace/src/app.swift")
        #expect(EditorPath.relative(child, to: root) == "src/app.swift")
    }

    @Test func relativeRootReturnsEmpty() {
        let root = URL(fileURLWithPath: "/tmp/workspace")
        #expect(EditorPath.relative(root, to: root) == "")
    }
}

// MARK: - DefaultEditorDocumentProvider Round-Trip (integration with real FS)

struct DefaultProviderTests {
    private func withTempDir<T>(_ body: (URL) async throws -> T) async throws -> T {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        return try await body(tempRoot)
    }

    @Test func roundTripsBytesExactlyIncludingNoTrailingNewline() async throws {
        try await withTempDir { root in
            let provider = DefaultEditorDocumentProvider()
            let url = root.appendingPathComponent("no-newline.txt")
            let contents = Data("hello, world".utf8) // no trailing newline
            try await provider.writeFile(at: url, contents: contents)
            let read = try await provider.readFile(at: url)
            #expect(read == contents)
            #expect(read.last != 0x0A)
        }
    }

    @Test func roundTripsBytesWithEOFSentinel() async throws {
        try await withTempDir { root in
            let provider = DefaultEditorDocumentProvider()
            let url = root.appendingPathComponent("eof.txt")
            // 0x1A (Ctrl-Z) is the DOS EOF sentinel — some editors strip it.
            let contents = Data([0x68, 0x69, 0x1A, 0x0A])
            try await provider.writeFile(at: url, contents: contents)
            let read = try await provider.readFile(at: url)
            #expect(read == contents)
        }
    }

    @Test func statReturnsCurrentAttributes() async throws {
        try await withTempDir { root in
            let provider = DefaultEditorDocumentProvider()
            let url = root.appendingPathComponent("s.txt")
            try await provider.writeFile(at: url, contents: Data("xyz".utf8))
            let s = try await provider.stat(at: url)
            #expect(s.size == 3)
            #expect(!s.isDirectory)
        }
    }

    @Test func listDirectoryReturnsImmediateChildren() async throws {
        try await withTempDir { root in
            let provider = DefaultEditorDocumentProvider()
            let f1 = root.appendingPathComponent("a.txt")
            let f2 = root.appendingPathComponent("b.txt")
            let sub = root.appendingPathComponent("sub", isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try await provider.writeFile(at: f1, contents: Data("a".utf8))
            try await provider.writeFile(at: f2, contents: Data("b".utf8))
            let entries = try await provider.listDirectory(at: root)
            let names = Set(entries.map(\.name))
            #expect(names == Set(["a.txt", "b.txt", "sub"]))
            #expect(entries.first(where: { $0.name == "sub" })?.isDirectory == true)
            #expect(entries.first(where: { $0.name == "a.txt" })?.size == 1)
        }
    }
}

// MARK: - FakeEditorDocumentProvider Contract Parity

struct FakeProviderTests {
    @Test func readsBackSeededFile() async throws {
        let fake = FakeEditorDocumentProvider()
        let url = URL(fileURLWithPath: "/ws/a.txt")
        await fake.seedFile(url, text: "hi")
        let data = try await fake.readFile(at: url)
        #expect(data == Data("hi".utf8))
    }

    @Test func writeThenReadRoundTrips() async throws {
        let fake = FakeEditorDocumentProvider()
        let url = URL(fileURLWithPath: "/ws/a.txt")
        let payload = Data([0x00, 0x01, 0xFE, 0xFF])
        try await fake.writeFile(at: url, contents: payload)
        let got = try await fake.readFile(at: url)
        #expect(got == payload)
    }

    @Test func statReturnsDeterministicAdvancingMtime() async throws {
        let fake = FakeEditorDocumentProvider()
        let url = URL(fileURLWithPath: "/ws/a.txt")
        await fake.seedFile(url, text: "v1")
        let before = try await fake.stat(at: url)
        try await fake.writeFile(at: url, contents: Data("v2".utf8))
        let after = try await fake.stat(at: url)
        #expect(after.mtime > before.mtime)
    }

    @Test func listDirectoryShowsSeededImmediateChildren() async throws {
        let fake = FakeEditorDocumentProvider()
        let root = URL(fileURLWithPath: "/ws")
        await fake.seedDirectory(root)
        await fake.seedFile(URL(fileURLWithPath: "/ws/a.txt"), text: "A")
        await fake.seedDirectory(URL(fileURLWithPath: "/ws/sub"))
        await fake.seedFile(URL(fileURLWithPath: "/ws/sub/b.txt"), text: "B")
        let entries = try await fake.listDirectory(at: root)
        let names = Set(entries.map(\.name))
        #expect(names == Set(["a.txt", "sub"]))
    }

    @Test func readFailsWhenRiggedAndMissingFile() async throws {
        let fake = FakeEditorDocumentProvider()
        let url = URL(fileURLWithPath: "/ws/absent.txt")
        do {
            _ = try await fake.readFile(at: url)
            #expect(Bool(false), "Should have thrown")
        } catch let error as NSError {
            #expect(error.domain == NSCocoaErrorDomain)
        }
    }

    @Test func riggedWriteFailurePropagates() async throws {
        let fake = FakeEditorDocumentProvider()
        await fake.setFailWrite(NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: "no space"]))
        let url = URL(fileURLWithPath: "/ws/a.txt")
        do {
            try await fake.writeFile(at: url, contents: Data("x".utf8))
            #expect(Bool(false), "Should have thrown")
        } catch let error as NSError {
            #expect(error.code == 513)
        }
    }
}

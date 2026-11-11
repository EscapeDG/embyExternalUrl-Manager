import XCTest
@testable import EmbyExternalUrlManager

final class MountedLogReaderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("logs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: mounts

    func testFindsLogMountSource() {
        let json = """
        [{"Type":"bind","Source":"/srv/deploy/cache","Destination":"/var/cache/nginx"},
         {"Type":"bind","Source":"/srv/deploy/logs","Destination":"/var/log/nginx/"}]
        """
        XCTAssertEqual(MountedLogReader.hostLogDirectory(mountsJSON: json), "/srv/deploy/logs")
    }

    func testNoLogMountOrBadJSON() {
        XCTAssertNil(MountedLogReader.hostLogDirectory(mountsJSON: #"[{"Source":"/a","Destination":"/etc/nginx/conf.d"}]"#))
        XCTAssertNil(MountedLogReader.hostLogDirectory(mountsJSON: "[]"))
        XCTAssertNil(MountedLogReader.hostLogDirectory(mountsJSON: "not json"))
    }

    func testStripsHostMntPrefixWhenPathMissing() {
        let json = #"[{"Source":"/host_mnt/Users/x/logs","Destination":"/var/log/nginx"}]"#
        XCTAssertEqual(MountedLogReader.hostLogDirectory(mountsJSON: json), "/Users/x/logs")
    }

    // MARK: files

    func testLogFilesOrderAndFilter() throws {
        try write("access.log", "")
        try write("zeta.log", "")
        try write("error.log", "")
        try write("access.log.1", "")
        try write("notes.txt", "")
        XCTAssertEqual(MountedLogReader.logFiles(in: dir.path), ["error.log", "access.log", "zeta.log"])
    }

    func testTailReturnsLastLines() throws {
        try write("error.log", (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n")
        let text = MountedLogReader.tail(path: dir.appendingPathComponent("error.log").path, lines: 3)
        XCTAssertEqual(text, "line 8\nline 9\nline 10")
    }

    func testTailOnLargeFileDropsPartialFirstLine() throws {
        try write("access.log", (1...1000).map { String(format: "row %04d", $0) }.joined(separator: "\n"))
        // 只读最后 50 字节：开头那行可能被截断，必须丢掉
        let text = MountedLogReader.tail(path: dir.appendingPathComponent("access.log").path, lines: 100, maxBytes: 50)
        let rows = text?.components(separatedBy: "\n") ?? []
        XCTAssertEqual(rows.last, "row 1000")
        XCTAssertTrue(rows.allSatisfy { $0.count == 8 }, "\(rows)")
    }

    func testRender() throws {
        XCTAssertNil(MountedLogReader.render(directory: dir.path, lines: 5))
        try write("error.log", "boom\n")
        try write("access.log", "")
        let text = try XCTUnwrap(MountedLogReader.render(directory: dir.path, lines: 5))
        XCTAssertTrue(text.contains("== error.log（末 5 行）==\nboom"))
        XCTAssertTrue(text.contains("== access.log（末 5 行）==\n（空）"))
        XCTAssertLessThan(text.range(of: "error.log")!.lowerBound, text.range(of: "access.log")!.lowerBound)
    }
}

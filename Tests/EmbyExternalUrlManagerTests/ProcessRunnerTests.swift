import XCTest
@testable import EmbyExternalUrlManager

final class ProcessRunnerTests: XCTestCase {
    func testFastExitReturnsOutputAndStatus() {
        let result = ProcessRunner.run("/bin/sh", args: ["-c", "echo out; echo err >&2; exit 3"], timeout: 5)
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stdout, "out\n")
        XCTAssertEqual(result.stderr, "err\n")
    }

    func testLargeOutputDoesNotDeadlock() {
        // 远超管道缓冲区（64 KiB）
        let result = ProcessRunner.run("/bin/sh", args: ["-c", "head -c 1000000 /dev/zero | tr '\\0' a"], timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 1_000_000)
    }

    func testTimeoutTerminatesProcess() {
        let start = Date()
        let result = ProcessRunner.run("/bin/sleep", args: ["10"], timeout: 0.5)
        XCTAssertEqual(result.exitCode, -9)
        XCTAssertTrue(result.stderr.contains("timed out"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testLaunchFailure() {
        let result = ProcessRunner.run("/nonexistent/tool", args: [], timeout: 1)
        XCTAssertEqual(result.exitCode, -1)
    }

    func testDisplayLineQuotesOnlyWhenNeeded() {
        XCTAssertEqual(Shell.displayLine(["docker", "exec", "a b", "it's"]), "docker exec 'a b' 'it'\\''s'")
        XCTAssertEqual(Shell.displayLine(["plain", "--flag=1"]), "plain --flag=1")
    }
}

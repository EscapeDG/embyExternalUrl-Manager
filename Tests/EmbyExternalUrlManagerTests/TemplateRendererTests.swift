import XCTest
@testable import EmbyExternalUrlManager

final class TemplateRendererTests: XCTestCase {
    private let renderer = TemplateRenderer()

    func testReplacesKnownPlaceholders() {
        let (text, unresolved) = renderer.render(
            template: "url={{URL}} port={{PORT}} again={{URL}}",
            variables: ["URL": "http://a", "PORT": "8091"]
        )
        XCTAssertEqual(text, "url=http://a port=8091 again=http://a")
        XCTAssertEqual(unresolved, [])
    }

    func testUnknownPlaceholdersStayAndAreReportedOnce() {
        let (text, unresolved) = renderer.render(
            template: "{{A}} {{MISSING}} {{OTHER}} {{MISSING}}",
            variables: ["A": "1"]
        )
        XCTAssertEqual(text, "1 {{MISSING}} {{OTHER}} {{MISSING}}")
        XCTAssertEqual(unresolved, ["MISSING", "OTHER"])
    }

    func testValuesContainingPlaceholdersAreNotRescanned() {
        let (text, unresolved) = renderer.render(
            template: "a={{A}} b={{B}}",
            variables: ["A": "{{B}}", "B": "{{NOPE}}"]
        )
        XCTAssertEqual(text, "a={{B}} b={{NOPE}}")
        XCTAssertEqual(unresolved, [])
    }

    func testNonASCIIAndEmptyValues() {
        let (text, unresolved) = renderer.render(
            template: "中文{{X}}🎬{{Y}}尾",
            variables: ["X": "值", "Y": ""]
        )
        XCTAssertEqual(text, "中文值🎬尾")
        XCTAssertEqual(unresolved, [])
    }

    func testTemplateWithoutPlaceholders() {
        let (text, unresolved) = renderer.render(template: "plain { text }", variables: ["X": "1"])
        XCTAssertEqual(text, "plain { text }")
        XCTAssertEqual(unresolved, [])
    }
}

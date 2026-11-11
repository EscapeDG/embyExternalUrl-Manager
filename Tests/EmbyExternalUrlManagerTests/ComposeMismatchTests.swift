import XCTest
@testable import EmbyExternalUrlManager

final class ComposeMismatchTests: XCTestCase {
    private let candidates = MediaServerType.emby.containerCandidates

    private func check(_ yaml: String, nginxDir: String = "/srv/deploy/nginx", composeDir: String = "/srv/deploy") -> [String] {
        ConfigService.composeMismatches(yaml, containerCandidates: candidates, nginxDir: nginxDir, composeDir: composeDir)
    }

    func testMatchingComposeHasNoProblems() {
        let yaml = """
        services:
          nginx:
            container_name: emby2Alist-nginx
            volumes:
              - ./nginx/nginx.conf:/etc/nginx/nginx.conf
              - ./nginx/conf.d:/etc/nginx/conf.d
        """
        XCTAssertEqual(check(yaml), [])
    }

    func testQuotedAbsoluteSourcesAndLegacyContainerName() {
        let yaml = """
        container_name: "nginx-emby"
        volumes:
          - "/srv/deploy/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
          - '/srv/deploy/nginx/conf.d:/etc/nginx/conf.d'
        """
        XCTAssertEqual(check(yaml), [])
    }

    func testTildeSourcesAreExpanded() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let yaml = """
        container_name: emby2Alist-nginx
          - ~/deploy/nginx/nginx.conf:/etc/nginx/nginx.conf
          - ~/deploy/nginx/conf.d:/etc/nginx/conf.d
        """
        XCTAssertEqual(check(yaml, nginxDir: home + "/deploy/nginx"), [])
    }

    func testWrongContainerName() {
        let yaml = """
        container_name: plex2Alist-nginx
          - ./nginx/nginx.conf:/etc/nginx/nginx.conf
          - ./nginx/conf.d:/etc/nginx/conf.d
        """
        let problems = check(yaml)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("plex2Alist-nginx"))
    }

    func testMissingContainerNameAndMounts() {
        let problems = check("services:\n  nginx:\n    image: nginx\n")
        XCTAssertEqual(problems.count, 3)
        XCTAssertTrue(problems[0].contains("未设置"))
        XCTAssertTrue(problems[1].contains("/etc/nginx/nginx.conf"))
        XCTAssertTrue(problems[2].contains("/etc/nginx/conf.d"))
    }

    func testMountFromOtherDirectoryIsReported() {
        let yaml = """
        container_name: emby2Alist-nginx
          - ../old/nginx/nginx.conf:/etc/nginx/nginx.conf
          - ./nginx/conf.d:/etc/nginx/conf.d
        """
        let problems = check(yaml)
        XCTAssertEqual(problems, ["/etc/nginx/nginx.conf 的挂载源为 /srv/old/nginx/nginx.conf，期望 /srv/deploy/nginx/nginx.conf"])
    }
}

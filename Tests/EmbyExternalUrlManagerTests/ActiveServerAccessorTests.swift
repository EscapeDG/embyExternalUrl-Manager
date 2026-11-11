import XCTest
@testable import EmbyExternalUrlManager

final class ActiveServerAccessorTests: XCTestCase {
    func testReadsAndWritesFollowMediaServerType() {
        var config = AppConfig()
        for type in [MediaServerType.plex, .emby, .jellyfin] {
            config.mediaServerType = type
            config.activeServerURL = "http://\(type.rawValue)"
            config.activeProxyPort = 1000
            config.activeProxyHttpsPort = 2000
            config.activeAPIKey = "key-\(type.rawValue)"
        }

        XCTAssertEqual(config.plex.serverURL, "http://Plex")
        XCTAssertEqual(config.emby.serverURL, "http://Emby")
        XCTAssertEqual(config.jellyfin.serverURL, "http://Jellyfin")
        XCTAssertEqual(config.emby.apiKey, "key-Emby")
        XCTAssertEqual(config.jellyfin.apiKey, "key-Jellyfin")
        XCTAssertEqual(config.plex.proxyHttpsPort, 2000)

        config.mediaServerType = .plex
        XCTAssertEqual(config.activeAPIKey, "", "Plex 没有 API Key")
        config.mediaServerType = .emby
        XCTAssertEqual(config.activeServerURL, "http://Emby")
        XCTAssertEqual(config.activeProxyPort, 1000)
    }

    func testWritingOneTypeLeavesOthersUntouched() {
        var config = AppConfig()
        let before = config
        config.mediaServerType = .jellyfin
        config.activeProxyPort = 9999
        XCTAssertEqual(config.plex, before.plex)
        XCTAssertEqual(config.emby, before.emby)
        XCTAssertEqual(config.jellyfin.proxyPort, 9999)
    }
}

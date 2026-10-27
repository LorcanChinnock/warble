import AppKit
import Foundation
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: "artist")

/// Finds the page of the artist that's playing, only where it can be found exactly rather than by matching names:
/// Spotify, whose track page names the artist, and a YouTube video in a browser Warble can script, whose channel
/// YouTube's oEmbed endpoint gives. Nothing is scripted or fetched until a click.
public enum ArtistPage {
    /// Where the artist's page is, and the app to open it in, or `nil` for the one that opens the address.
    public struct Page: Equatable, Sendable {
        public var url: URL
        public var app: String?
    }

    private static let spotify = "com.spotify.client"

    /// The artist's page for the track titled `title` that `bundleIdentifier` is playing, or `nil` when there's no exact one.
    public static func find(bundleIdentifier: String, title: String) async -> Page? {
        if bundleIdentifier == spotify {
            return await spotifyArtist().map { Page(url: $0, app: nil) }
        }
        guard let tab = await BrowserTabs.url(bundleIdentifier: bundleIdentifier, title: title),
              let channel = await youTubeChannel(of: tab)
        else { return nil }
        return Page(url: channel, app: bundleIdentifier)
    }

    // MARK: - Spotify

    /// The current track's address, such as `spotify:track:4cOd…`, or an empty string when nothing is loaded.
    static let spotifyTrackScript = """
    with timeout of 5 seconds
        tell application id "com.spotify.client"
            if player state is stopped then return ""
            return spotify url of current track
        end tell
    end timeout
    """

    /// The track's ID in an address such as `spotify:track:4cOd…`, or `nil` for an episode, an ad or anything else.
    static func spotifyTrackID(_ address: String) -> String? {
        let parts = address.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", parts[1] == "track", parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return String(parts[2])
    }

    /// The first artist the track's page on open.spotify.com names, as an address that opens in Spotify.
    static func spotifyArtist(inTrackPage html: String) -> URL? {
        guard let match = html.firstMatch(of: /<meta name="music:musician" content="https:\/\/open\.spotify\.com\/artist\/([A-Za-z0-9]+)"/)
        else { return nil }
        return URL(string: "spotify:artist:\(match.1)")
    }

    private static func spotifyArtist() async -> URL? {
        // A script that names Spotify would open it if it has just quit.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: spotify).isEmpty,
              let address = await BrowserTabs.run(spotifyTrackScript)?.stringValue,
              let id = spotifyTrackID(address),
              let page = URL(string: "https://open.spotify.com/track/\(id)"),
              let html = await fetch(page).flatMap({ String(data: $0, encoding: .utf8) })
        else { return nil }
        return spotifyArtist(inTrackPage: html)
    }

    // MARK: - YouTube

    /// The oEmbed request for the video at `tab`, or `nil` when `tab` isn't a YouTube video.
    static func oEmbedURL(for tab: URL) -> URL? {
        guard let host = tab.host()?.lowercased(), let components = URLComponents(url: tab, resolvingAgainstBaseURL: false)
        else { return nil }
        let video: String?
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            video = components.path == "/watch" ? components.queryItems?.first { $0.name == "v" }?.value : nil
        case "youtu.be":
            video = String(components.path.dropFirst())
        default:
            video = nil
        }
        guard let video, !video.isEmpty, video.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return URL(string: "https://www.youtube.com/oembed?format=json&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D\(video)")
    }

    /// The channel in an oEmbed response, if it's on YouTube.
    static func channel(inOEmbed response: Data) -> URL? {
        struct Response: Decodable {
            var author_url: String?
        }
        guard let address = (try? JSONDecoder().decode(Response.self, from: response))?.author_url,
              let url = URL(string: address), url.scheme == "https",
              let host = url.host()?.lowercased(), host == "youtube.com" || host.hasSuffix(".youtube.com")
        else { return nil }
        return url
    }

    private static func youTubeChannel(of tab: URL) async -> URL? {
        guard let request = oEmbedURL(for: tab), let response = await fetch(request) else { return nil }
        return channel(inOEmbed: response)
    }

    // MARK: - Fetching

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    private static func fetch(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            log.error("Artist lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

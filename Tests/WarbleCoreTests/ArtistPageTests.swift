import Foundation
import Testing
@testable import WarbleCore

@Test func onlyASpotifyTrackHasATrackID() {
    #expect(ArtistPage.spotifyTrackID("spotify:track:4cOdK2wGLETKBW3PvgPWqT") == "4cOdK2wGLETKBW3PvgPWqT")
    #expect(ArtistPage.spotifyTrackID("spotify:episode:4cOdK2wGLETKBW3PvgPWqT") == nil)
    #expect(ArtistPage.spotifyTrackID("spotify:ad:4cOdK2wGLETKBW3PvgPWqT") == nil)
    #expect(ArtistPage.spotifyTrackID("") == nil)
}

@Test func theFirstArtistOnASpotifyTrackPageOpensInSpotify() {
    let html = """
    <meta property="og:title" content="Never Gonna Give You Up"/><meta name="music:musician" \
    content="https://open.spotify.com/artist/0gxyHStUsqpMadRV0Di1Qt"/><meta name="music:musician_description" \
    content="Rick Astley"/><meta name="music:musician" content="https://open.spotify.com/artist/second"/>
    """
    #expect(ArtistPage.spotifyArtist(inTrackPage: html) == URL(string: "spotify:artist:0gxyHStUsqpMadRV0Di1Qt"))
    #expect(ArtistPage.spotifyArtist(inTrackPage: "<html></html>") == nil)
}

@Test func aYouTubeVideoIsLookedUpByItsID() {
    let expected = URL(string: "https://www.youtube.com/oembed?format=json&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ")
    for tab in [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RD",
        "https://youtu.be/dQw4w9WgXcQ",
    ] {
        #expect(ArtistPage.oEmbedURL(for: URL(string: tab)!) == expected, "\(tab)")
    }
}

@Test func pagesThatAreNotYouTubeVideosAreNotLookedUp() {
    for tab in [
        "https://www.youtube.com/",
        "https://www.youtube.com/@RickAstleyYT",
        "https://soundcloud.com/artist/song",
        "https://www.youtube.com/watch?v=a%26b",
    ] {
        #expect(ArtistPage.oEmbedURL(for: URL(string: tab)!) == nil, "\(tab)")
    }
}

@Test func theChannelIsTheOEmbedAuthorOnYouTube() {
    let response = Data(#"{"title":"Never Gonna Give You Up","author_name":"Rick Astley","author_url":"https://www.youtube.com/@RickAstleyYT"}"#.utf8)
    #expect(ArtistPage.channel(inOEmbed: response) == URL(string: "https://www.youtube.com/@RickAstleyYT"))
    #expect(ArtistPage.channel(inOEmbed: Data(#"{"author_url":"https://example.com/@x"}"#.utf8)) == nil)
    #expect(ArtistPage.channel(inOEmbed: Data("not json".utf8)) == nil)
}

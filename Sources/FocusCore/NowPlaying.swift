import Foundation

/// What Spotify is playing, as read through AppleScript or its playback notification.
public struct NowPlaying: Equatable, Sendable {
    public var playing: Bool
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var shuffling: Bool
    public var repeating: Bool

    public init(playing: Bool, title: String, artist: String, album: String = "", artworkURL: URL? = nil,
                shuffling: Bool = false, repeating: Bool = false) {
        self.playing = playing
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.shuffling = shuffling
        self.repeating = repeating
    }

    /// Field separator in the AppleScript reply (unit separator, never part of a title).
    public static let separator: Character = "\u{1F}"

    /// Only Spotify's own image servers over https: the cover is the app's one network request.
    static func spotifyImage(_ url: URL) -> URL? {
        guard url.scheme == "https", let host = url.host else { return nil }
        return host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com") ? url : nil
    }

    /// Parses "state␟title␟artist␟album␟artwork url␟shuffling␟repeating". A bare state (no track loaded) is nil.
    public static func parse(_ reply: String) -> NowPlaying? {
        let f = reply.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 7, !f[1].isEmpty else { return nil }
        return NowPlaying(playing: f[0] == "playing", title: f[1], artist: f[2], album: f[3],
                          artworkURL: URL(string: f[4]).flatMap(spotifyImage),
                          shuffling: f[5] == "true", repeating: f[6] == "true")
    }
}

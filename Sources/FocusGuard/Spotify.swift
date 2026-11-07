import AppKit
import FocusCore

/// What Spotify is playing, and its play / skip / shuffle / repeat controls.
/// Track changes arrive as Spotify's own distributed notification, which needs no permission. The cover, shuffle and
/// repeat, and every control go through AppleScript, which macOS asks the user to allow once ("control Spotify").
/// FocusGuard never launches Spotify: nothing is sent unless Spotify is already running.
@MainActor
final class Spotify: ObservableObject {
    enum Access { case unknown, granted, denied }

    nonisolated static let bundleID = "com.spotify.client"

    @Published private(set) var running = false
    @Published private(set) var track: NowPlaying?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var access = Access.unknown

    var playing: Bool { running && track?.playing == true }

    private let queue = DispatchQueue(label: "FocusGuard.spotify")
    private var artworkURL: URL?
    /// Bumped when a notification or Spotify quitting replaces the track, so a read started earlier cannot bring the old one back.
    private var generation = 0

    nonisolated private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    init() {
        running = Self.isRunning
        DistributedNotificationCenter.default().addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"),
                                                            object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.changed(info) }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                let launched = name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated {
                    self?.running = launched
                    if !launched { self?.generation += 1; self?.track = nil; self?.dropArtwork() }
                }
            }
        }
        refresh(ask: false)
    }

    /// Spotify said the track or the play state changed. The notification has no cover or shuffle state,
    /// so keep those from the last read and read again if we may.
    private func changed(_ info: [AnyHashable: Any]) {
        running = Self.isRunning // a late notification from a Spotify that just quit must not bring it back
        guard running else { return }
        generation += 1
        let state = info["Player State"] as? String
        if state == "Stopped" {
            track = nil
            dropArtwork()
        } else if let title = info["Name"] as? String, !title.isEmpty {
            var t = NowPlaying(playing: state == "Playing", title: title, artist: info["Artist"] as? String ?? "",
                               album: info["Album"] as? String ?? "")
            let sameTrack = track.map { $0.title == t.title && $0.artist == t.artist && $0.album == t.album } ?? false
            if let old = track {
                t.shuffling = old.shuffling
                t.repeating = old.repeating
                if sameTrack { t.artworkURL = old.artworkURL }
            }
            if !sameTrack { dropArtwork() } // never show the last album's cover next to a new song
            track = t
        }
        refresh(ask: false)
    }

    /// Reads the player through AppleScript. With `ask`, macOS may show its Automation prompt; without it,
    /// nothing is read until the user has allowed it once.
    func refresh(ask: Bool) {
        guard running else { return }
        let started = generation
        queue.async {
            let allowed = Self.permission(ask: ask)
            let reply = allowed == noErr ? Self.run(Self.readScript) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if allowed == OSStatus(errAEEventNotPermitted) { self.access = .denied }
                    // Spotify may have quit, or moved on to another track, while this was read.
                    guard allowed == noErr, self.running, started == self.generation else { return }
                    self.access = .granted
                    if let reply { self.track = NowPlaying.parse(reply) }
                    self.loadArtwork()
                }
            }
        }
    }

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
        case shuffle = "set shuffling to not shuffling"
        case `repeat` = "set repeating to not repeating"
    }

    func send(_ command: Command) {
        guard running else { return }
        queue.async {
            let allowed = Self.permission(ask: true)
            guard allowed == noErr else {
                let denied = allowed == OSStatus(errAEEventNotPermitted) // otherwise Spotify just quit
                DispatchQueue.main.async { MainActor.assumeIsolated { if denied { self.access = .denied } } }
                return
            }
            _ = Self.run(Self.whileRunning("\(command.rawValue)"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { self.refresh(ask: false) } }
        }
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            NSWorkspace.shared.open(URL(string: "https://open.spotify.com")!)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    #if DEBUG
    /// Debug fixtures: show a track without Spotify.
    func preview(_ track: NowPlaying, artwork: NSImage?) {
        running = true
        access = .granted
        self.track = track
        self.artwork = artwork
    }
    #endif

    /// Forgets the cover; a download still on its way for it is ignored when it lands.
    private func dropArtwork() {
        artwork = nil
        artworkURL = nil
    }

    /// The cover is the one network request the app makes: Spotify's own image server, over https (NowPlaying.parse checks the host).
    private func loadArtwork() {
        guard let url = track?.artworkURL else { dropArtwork(); return }
        guard url != artworkURL else { return }
        artwork = nil // the old cover never sits next to the new song while this one loads
        artworkURL = url
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let image = ok ? data.flatMap(NSImage.init(data:)) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.artworkURL == url else { return }
                    self.artwork = image
                    if image == nil { self.artworkURL = nil } // failed: the next refresh tries again
                }
            }
        }.resume()
    }

    // MARK: AppleScript, only ever run on `queue`

    nonisolated private static let readScript = whileRunning("""
            set d to character id 31
            set s to player state as string
            try
                set t to current track
                return s & d & (name of t) & d & (artist of t) & d & (album of t) & d & (artwork url of t) & d & (shuffling as string) & d & (repeating as string)
            on error
                return s
            end try
    """)

    /// Wraps commands so they only reach a Spotify that is running at that moment: `tell` alone would launch it.
    nonisolated private static func whileRunning(_ body: String) -> String {
        """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)"
                with timeout of 3 seconds
                    \(body)
                end timeout
            end tell
        end if
        """
    }

    /// noErr when allowed; errAEEventNotPermitted when the user said no; errAEEventWouldRequireUserConsent when not asked yet.
    nonisolated private static func permission(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }

    nonisolated private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("FocusGuard: Spotify script failed: \(error)") }
        return error == nil ? result?.stringValue : nil
    }
}

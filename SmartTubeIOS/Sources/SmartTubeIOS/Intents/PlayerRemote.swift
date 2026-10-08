#if os(iOS)
import Foundation

// MARK: - PlayerRemote (App Intents)
//
// Lets the player-control App Intents (play/pause, skip, next video) act on whichever
// player is open without bringing the app forward. AppEntry attaches the two player
// stores at launch; each call returns false when nothing is playing.

@MainActor
public enum PlayerRemote {
    private static weak var playerState: PlayerStateStore?
    private static weak var tosState: TOSPlayerStateStore?

    public static func attach(playerState: PlayerStateStore, tosState: TOSPlayerStateStore) {
        self.playerState = playerState
        self.tosState = tosState
    }

    private static var tosVM: TOSPlayerViewModel? {
        guard let tosState, tosState.presentation != .hidden else { return nil }
        return tosState.vm
    }

    private static var playbackVM: PlaybackViewModel? {
        guard let playerState, playerState.presentation != .hidden else { return nil }
        return playerState.vm
    }

    @discardableResult
    public static func togglePlayPause() -> Bool {
        if let vm = tosVM {
            if vm.playerState == .playing { vm.pause() } else { vm.play() }
            return true
        }
        if let vm = playbackVM {
            vm.togglePlayPause()
            return true
        }
        return false
    }

    @discardableResult
    public static func skip(by seconds: TimeInterval) -> Bool {
        if let vm = tosVM {
            vm.seekRelative(seconds)
            return true
        }
        if let vm = playbackVM {
            vm.seekRelative(seconds: seconds)
            return true
        }
        return false
    }

    @discardableResult
    public static func playNext() -> Bool {
        if let vm = tosVM {
            vm.playNext()
            return true
        }
        if let vm = playbackVM {
            vm.playNext()
            return true
        }
        return false
    }
}
#endif

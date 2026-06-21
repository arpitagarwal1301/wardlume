//  AssetSlotViews.swift
//  Wardlume
//
//  AudioPreviewPlayer — ObservableObject wrapper for AVAudioPlayer with delegate,
//  used by the audio asset row to audition a sound before/after committing.
//
//  (The original Phase 4c drop-slot widgets were superseded by the row-based
//  AssetRow in AssetRowViews.swift.)

import SwiftUI
import AVFoundation
import Combine

/// ObservableObject wrapper for AVAudioPlayer with delegate support.
///
/// SwiftUI Views are structs and can't conform to AVAudioPlayerDelegate directly.
/// This class owns the AVAudioPlayer, serves as its delegate, and publishes
/// playback state so the UI can toggle between play/stop buttons.
final class AudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    /// True while audio is playing, false otherwise. Drives the play/stop icon.
    @Published private(set) var isPlaying: Bool = false

    private var player: AVAudioPlayer?

    /// Start playing audio from the given URL. Stops any in-flight playback first.
    func play(url: URL) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("Wardlume [AudioPreviewPlayer]: failed to play \(url.lastPathComponent): \(error)")
            isPlaying = false
        }
    }

    /// Stop playback and release the player.
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    /// Fired when audio finishes naturally; dispatched to main to update @Published state.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlaying = false
        }
    }
}

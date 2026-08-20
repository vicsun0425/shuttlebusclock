import Foundation
import AVFoundation
import AudioToolbox
import Observation

/// Owns the AVAudioSession + AVAudioPlayer used to play the alarm sound.
///
/// Critical design notes (see plan for full rationale):
///   * `AVAudioSession.Category.playback` is the ONLY iOS audio category that
///     bypasses the silent switch. Must be paired with the `audio` background
///     mode in Info.plist, otherwise the session is torn down in seconds when
///     the app is backgrounded.
///   * The session is reactivated after every `AVAudioSession.interruption`
///     (phone call, Siri, music app) — otherwise the alarm dies silently
///     after the interruption ends.
@Observable
@MainActor
final class AlarmManager {
    // MARK: - Public state observed by SwiftUI

    /// Whether the alarm audio is currently playing.
    var isPlaying: Bool = false

    /// The stop that triggered the active alarm, used by the alarm UI.
    var activeStopName: String?

    /// Distance (meters) at which the alarm fired.
    var activeDistance: Double?

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        setupInterruptionObserver()
    }

    // MARK: - Public API

    /// Activate the audio session and start looping the alarm sound.
    /// Idempotent — calling twice while playing is a no-op.
    func start(stopName: String, distance: Double) {
        activeStopName = stopName
        activeDistance = distance

        if isPlaying { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // .playback is mandatory for bypassing silent mode.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            guard let url = Bundle.main.url(
                forResource: "alarm",
                withExtension: "caf"
            ) else {
                print("⚠️ alarm.caf not found in bundle")
                return
            }

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // loop forever until stopped
            player.volume = 1.0
            player.prepareToPlay()
            player.play()

            self.audioPlayer = player
            self.isPlaying = true

            // Immediate haptic burst.
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

            // Periodic haptic pulses so even a deaf user notices.
            startVibrationTimer()
        } catch {
            print("❌ Failed to start alarm: \(error)")
        }
    }

    /// Stop the alarm and tear down the audio session.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        activeStopName = nil
        activeDistance = nil
        stopVibrationTimer()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Vibration

    private func startVibrationTimer() {
        vibrationTimer?.invalidate()
        vibrationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.5,
            repeats: true
        ) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private func stopVibrationTimer() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }

    // MARK: - Interruption handling

    private func setupInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            // Phone call / Siri / other audio app. The system pauses us.
            isPlaying = false
            stopVibrationTimer()

        case .ended:
            guard
                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    audioPlayer?.play()
                    isPlaying = true
                    startVibrationTimer()
                } catch {
                    print("❌ Failed to resume after interruption: \(error)")
                }
            }

        @unknown default:
            break
        }
    }
}
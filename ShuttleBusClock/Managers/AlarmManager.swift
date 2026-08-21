import Foundation
import AVFoundation
import AudioToolbox
import Observation

/// Owns the AVAudioSession + AVAudioPlayer used to play the alarm sound.
///
/// Critical design notes:
///   * `AVAudioSession.Category.playback` is the ONLY iOS audio category that
///     bypasses the silent switch. Must be paired with the `audio` background
///     mode in Info.plist, otherwise the session is torn down in seconds when
///     the app is backgrounded.
///   * **The session is pre-warmed for the whole armed trip.** Activating a
///     non-mixing session from the background while another app is already
///     playing fails with `AVAudioSessionErrorCodeCannotInterruptOthers` — iOS
///     will not let a dormant app seize audio focus. So from the moment a trip
///     is armed we hold an *active but silent and mixable* session: inaudible,
///     doesn't disturb anything, but it means that when the alarm fires we
///     already own a session and only have to drop `.mixWithOthers` to take
///     the focus. Without this, the alarm silently loses to whatever the user
///     fell asleep watching.
///   * The session is reactivated after every `AVAudioSession.interruption`
///     (phone call, Siri, music app) — otherwise the alarm dies silently
///     after the interruption ends.
///   * Vibration is started *before* audio and is never stopped by an audio
///     interruption. It's the fallback for exactly the cases where audio fails.
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

    /// Last audio failure, surfaced in the UI. These used to only be `print`ed,
    /// which on a device means they vanished.
    var lastAudioError: String?

    /// True while the silent keep-alive session is held.
    private(set) var isPrewarmed: Bool = false

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?
    private var interruptionObserver: NSObjectProtocol?

    private var alarmURL: URL? {
        Bundle.main.url(forResource: "alarm", withExtension: "caf")
    }

    init() {
        setupInterruptionObserver()
    }

    // MARK: - Public API

    /// Take and hold a silent, mixable audio session for the duration of an
    /// armed trip. Safe to call repeatedly.
    ///
    /// Plays the alarm file at volume 0 rather than shipping a separate silent
    /// asset — same effect, one less thing to keep in the bundle.
    func prewarm() {
        guard !isPrewarmed, !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers keeps Bilibili/Spotify/etc. playing untouched.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            guard let url = alarmURL else {
                fail("预热失败", "bundle 内找不到 alarm.caf")
                return
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            player.play()

            audioPlayer = player
            isPrewarmed = true
            lastAudioError = nil
            AlarmDiagnostics.record("音频预热成功", "静音占位会话已激活")
        } catch {
            fail("预热失败", error.localizedDescription)
        }
    }

    /// Release the keep-alive session when a trip ends without an alarm.
    func stopPrewarm() {
        guard isPrewarmed, !isPlaying else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        isPrewarmed = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        AlarmDiagnostics.record("音频预热已释放")
    }

    /// Escalate to a full-volume alarm that interrupts all other audio.
    /// Idempotent — calling twice while playing only refreshes the metadata.
    func start(stopName: String, distance: Double) {
        activeStopName = stopName
        activeDistance = distance

        if isPlaying { return }

        AlarmDiagnostics.record(
            "闹钟触发",
            "\(stopName) · \(Int(distance)) 米 · 预热=\(isPrewarmed ? "是" : "否")"
        )

        // Haptics first and unconditionally: they need no audio session, so
        // they still fire when audio is the thing that's broken.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        startVibrationTimer()
        isPlaying = true

        escalateAudio(attempt: 1)
    }

    /// Stop the alarm and tear down the audio session.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isPrewarmed = false
        activeStopName = nil
        activeDistance = nil
        stopVibrationTimer()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        AlarmDiagnostics.record("闹钟已停止")
    }

    // MARK: - Audio escalation

    /// Drop `.mixWithOthers` so iOS pauses whatever else is playing, then run
    /// the alarm file at full volume.
    ///
    /// Retries a few times: `setActive` can transiently fail with
    /// `CannotInterruptOthers` right as another app is grabbing focus, and an
    /// alarm that gives up after one attempt is an alarm that doesn't ring.
    /// Go loud, then *try* to quiet other apps — in that order, and never the
    /// other way round.
    ///
    /// A device trace of a real failure is why this is shaped like this. An
    /// earlier version deactivated the session first so iOS would re-arbitrate
    /// audio focus and pause the other app. iOS did re-arbitrate — against us:
    ///
    ///     抢占音频失败  第 1 次:Session activation failed   (×5)
    ///     音频彻底失败  已重试 5 次,仅靠振动提醒
    ///
    /// Deactivating surrenders the session, and a *background* app cannot take
    /// focus back from an app that is actively playing. The keep-alive session
    /// is the only reason we can make any sound at all from the background, so
    /// it must never be given up. Pausing the other app is best-effort;
    /// being audible is not negotiable.
    private func escalateAudio(attempt: Int) {
        // Step 1 — guaranteed noise on the session we already hold.
        do {
            let player: AVAudioPlayer
            if let existing = audioPlayer {
                player = existing
            } else {
                guard let url = alarmURL else {
                    fail("播放失败", "bundle 内找不到 alarm.caf")
                    return
                }
                player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.prepareToPlay()
                audioPlayer = player
            }
            player.volume = 1.0
            if !player.isPlaying {
                player.currentTime = 0
                player.play()
            }
            lastAudioError = nil
            AlarmDiagnostics.record("闹钟已出声", "音量 100%,会话未中断")
        } catch {
            fail("播放失败", error.localizedDescription)
            return
        }

        // Step 2 — best effort: ask iOS to duck whatever else is playing.
        // Ducking is applied while we output audio, unlike interruption which
        // is decided once at activation, so this is the only lever still
        // available to a background app. If it's refused we stay audible.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.duckOthers]
            )
            AlarmDiagnostics.record("已请求压低其他音频")
        } catch {
            AlarmDiagnostics.record("压低其他音频被拒", error.localizedDescription)
        }
    }

    private func fail(_ event: String, _ detail: String) {
        lastAudioError = "\(event):\(detail)"
        AlarmDiagnostics.record(event, detail)
    }

    // MARK: - Vibration

    private func startVibrationTimer() {
        vibrationTimer?.invalidate()
        // Scheduled on .common so it keeps firing while the run loop is busy
        // with UI tracking; the default mode alone can stall it.
        let timer = Timer(timeInterval: 1.2, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        RunLoop.main.add(timer, forMode: .common)
        vibrationTimer = timer
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
            // Phone call / Siri / another audio app. The system paused us.
            // Deliberately do NOT stop the vibration: an interrupted alarm is
            // precisely when the haptic fallback matters most.
            AlarmDiagnostics.record("音频被中断", isPlaying ? "闹钟响铃中,继续振动" : "预热会话被中断")

        case .ended:
            guard
                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                if isPlaying {
                    escalateAudio(attempt: 1)
                } else if isPrewarmed {
                    isPrewarmed = false
                    prewarm()
                }
                AlarmDiagnostics.record("中断结束", "已尝试恢复")
            }

        @unknown default:
            break
        }
    }
}

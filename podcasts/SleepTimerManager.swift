import Foundation
import CoreMotion
import PocketCastsUtils

class SleepTimerManager {
    private var restartSleepTimerIfPlayingAgainWithin: TimeInterval = 5.minutes

    private let backgroundShakeObserver: BackgroundShakeObserver

    private lazy var tonePlayer: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "sleep-timer-restarted-sound", withExtension: "mp3") else {
            FileLog.shared.addMessage("[Sleep Timer] Unable to create tone player because the sound file is missing from the bundle.")
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            FileLog.shared.addMessage("[Sleep Timer] Unable to create tone player because of an exception: \(error)")
            return nil
        }
    }()

    let sleepTimerFadeDuration = 5.seconds

    private lazy var fadeOutManager = FadeOutManager()

    init(backgroundShakeObserver: BackgroundShakeObserver = BackgroundShakeObserver()) {
        self.backgroundShakeObserver = backgroundShakeObserver
        backgroundShakeObserver.whenShook = { [weak self] in
            self?.restartSleepTimerAndPlayTone()
        }
    }

    func recordSleepTimerFinished() {
        Settings.sleepTimerFinishedDate = .now
        FileLog.shared.addMessage("Sleep Timer: finished (\(Settings.sleepTimerFinishedDate?.description ?? ""))")
    }

    func recordSleepTimerDuration(duration: TimeInterval?, onEpisodeEnd: Bool?) {
        let setting = SleepTimerSetting(duration: duration, sleepOnEpisodeEnd: onEpisodeEnd)
        Settings.sleepTimerLastSetting = setting
    }

    func cancelSleepTimer(userInitiated: Bool) {
        guard userInitiated else {
            return
        }

        Settings.sleepTimerFinishedDate = .distantPast
    }

    func restartSleepTimerIfNeeded() {
        guard !PlaybackManager.shared.sleepTimerActive(), Settings.autoRestartSleepTimer else {
            return
        }

        let now = Date.now
        if let sleepTimerFinishedDate = Settings.sleepTimerFinishedDate,
           now.timeIntervalSince(sleepTimerFinishedDate) <= restartSleepTimerIfPlayingAgainWithin,
           let setting = Settings.sleepTimerLastSetting {
            if let duration = setting.duration {
                PlaybackManager.shared.setSleepTimerInterval(duration)
                Analytics.shared.track(.playerSleepTimerRestarted, properties: ["time": duration])
                FileLog.shared.addMessage("Sleep Timer: restarting it automatically (\(now.description) - \(sleepTimerFinishedDate.description) <= 5 minutes")
            } else if setting.sleepOnEpisodeEnd == true {
                observePlaybackEndAndReactivateTime()
            }
        }
    }

    func restartSleepTimer() {
        if let setting = Settings.sleepTimerLastSetting {
            if let duration = setting.duration {
                PlaybackManager.shared.setSleepTimerInterval(duration)
                Analytics.shared.track(.playerSleepTimerRestarted, properties: ["time": duration, "reason": "device_shake"])
                FileLog.shared.addMessage("Sleep Timer: restarting it after device shake")
            }
        }
    }

    func performFadeOut(player: PlaybackProtocol) {
        fadeOutManager.player = player
        fadeOutManager.fadeOut(duration: sleepTimerFadeDuration)
    }

    private func observePlaybackEndAndReactivateTime() {
        NotificationCenter.default.addObserver(self, selector: #selector(episodeDurationChanged), name: Constants.Notifications.episodeDurationChanged, object: nil)
    }

    @objc private func episodeDurationChanged() {
        let numberOfEpisodes = Settings.sleepTimerNumberOfEpisodes
        FileLog.shared.addMessage("Sleep Timer: restarting it automatically to the end of the episode")
        Analytics.shared.track(.playerSleepTimerRestarted, properties: ["time": "end_of_episode", "number_of_episodes": numberOfEpisodes])
        PlaybackManager.shared.numberOfEpisodesToSleepAfter = numberOfEpisodes
        NotificationCenter.default.removeObserver(self, name: Constants.Notifications.episodeDurationChanged, object: nil)
    }

    private func restartSleepTimerAndPlayTone() {
        guard PlaybackManager.shared.sleepTimerActive() && Settings.shakeToRestartSleepTimer else {
            backgroundShakeObserver.stopObserving()
            return
        }

        restartSleepTimer()
        playTone()
    }

    func playTone() {
        guard let tonePlayer else { return }

        tonePlayer.play()
    }

    struct SleepTimerSetting: JSONEncodable, JSONDecodable {
        let duration: TimeInterval?
        let sleepOnEpisodeEnd: Bool?
    }
}

class BackgroundShakeObserver {
    private let manager = CMMotionManager()
    private let motionUpdateInterval: Double = 0.05
    private var debounceTimer: Timer?
    var whenShook: (() -> Void)?

    init() {
        #if !os(watchOS)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sleepTimerChanged), name: Constants.Notifications.sleepTimerChanged, object: nil)
        #endif
    }

    @objc private func appMovedToBackground() {
        if PlaybackManager.shared.sleepTimerActive() && Settings.shakeToRestartSleepTimer {
            startObserving()
        }
    }

    @objc private func appMovedToForeground() {
        stopObserving()
    }

    @objc private func sleepTimerChanged() {
        if !PlaybackManager.shared.sleepTimerActive() {
            stopObserving()
        }
    }

    func startObserving() {
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = motionUpdateInterval

            manager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
                guard let data else {
                    return
                }

                if (abs(data.userAcceleration.y) > 0.8
                    || abs(data.userAcceleration.x) > 0.8)
                    && abs(data.userAcceleration.z) < 0.2 {
                    self?.debounceTimer?.invalidate()
                    self?.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                        self?.whenShook?()
                    }
                }

            }
        }
    }

    func stopObserving() {
        manager.stopDeviceMotionUpdates()
    }
}

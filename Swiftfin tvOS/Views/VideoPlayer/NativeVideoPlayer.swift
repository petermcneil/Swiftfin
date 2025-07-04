//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVKit
import Combine
import Defaults
import JellyfinAPI
import SwiftUI

struct NativeVideoPlayer: View {

    @Environment(\.scenePhase)
    var scenePhase

    @Router
    private var router

    @ObservedObject
    private var videoPlayerManager: VideoPlayerManager

    init(manager: VideoPlayerManager) {
        self.videoPlayerManager = manager
    }

    @ViewBuilder
    private var playerView: some View {
        NativeVideoPlayerView(videoPlayerManager: videoPlayerManager)
    }

    var body: some View {
        Group {
            if let _ = videoPlayerManager.currentViewModel {
                playerView
            } else {
                VideoPlayer.LoadingView()
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea()
    }
}

struct NativeVideoPlayerView: UIViewControllerRepresentable {

    let videoPlayerManager: VideoPlayerManager

    func makeUIViewController(context: Context) -> UINativeVideoPlayerViewController {
        UINativeVideoPlayerViewController(manager: videoPlayerManager)
    }

    func updateUIViewController(_ uiViewController: UINativeVideoPlayerViewController, context: Context) {}
}

class UINativeVideoPlayerViewController: UIViewController {

    let videoPlayerManager: VideoPlayerManager
    private let playerViewController = AVPlayerViewController()

    private var rateObserver: NSKeyValueObservation!
    private var timeObserverToken: Any!

    init(manager: VideoPlayerManager) {
        self.videoPlayerManager = manager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Add AVPlayerViewController as child
        addChild(playerViewController)
        view.addSubview(playerViewController.view)
        playerViewController.view.frame = view.bounds
        playerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerViewController.didMove(toParent: self)

        // Set up player
        setupPlayer()
    }

    private func setupPlayer() {
        let asset = AVAsset(url: videoPlayerManager.currentViewModel.playbackURL)

        // Load metadata and playable status asynchronously
        asset.loadValuesAsynchronously(forKeys: ["playable", "metadata"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Create player with properly loaded asset
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.externalMetadata = self.createMetadata()

                let newPlayer = AVPlayer(playerItem: playerItem)
                newPlayer.allowsExternalPlayback = true
                newPlayer.appliesMediaSelectionCriteriaAutomatically = false

                // Finish configuring player
                self.configurePlayer(newPlayer)
            }
        }
    }

    private func configurePlayer(_ newPlayer: AVPlayer) {
        rateObserver = newPlayer.observe(\.rate, options: .new) { [weak self] _, change in
            guard let self = self, let newValue = change.newValue else { return }

            if newValue == 0 {
                self.videoPlayerManager.onStateUpdated(newState: .paused)
            } else {
                self.videoPlayerManager.onStateUpdated(newState: .playing)
            }
        }

        let time = CMTime(seconds: 0.1, preferredTimescale: 1000)

        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
            guard let self = self else { return }

            if time.seconds >= 0 {
                let newSeconds = Int(time.seconds)
                let progress = CGFloat(newSeconds) / CGFloat(self.videoPlayerManager.currentViewModel.item.runTimeSeconds)

                self.videoPlayerManager.currentProgressHandler.progress = progress
                self.videoPlayerManager.currentProgressHandler.scrubbedProgress = progress
                self.videoPlayerManager.currentProgressHandler.seconds = newSeconds
                self.videoPlayerManager.currentProgressHandler.scrubbedSeconds = newSeconds
            }
        }

        playerViewController.player = newPlayer
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stop()
        if let timeObserverToken = timeObserverToken {
            playerViewController.player?.removeTimeObserver(timeObserverToken)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        playerViewController.player?.seek(
            to: CMTimeMake(
                value: Int64(videoPlayerManager.currentViewModel.item.startTimeSeconds - Defaults[.VideoPlayer.resumeOffset]),
                timescale: 1
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
            completionHandler: { _ in
                // Small delay to let subtitles synchronize on tvOS
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.play()
                }
            }
        )
    }

    private func createMetadata() -> [AVMetadataItem] {
        let allMetadata: [AVMetadataIdentifier: Any?] = [
            .commonIdentifierTitle: videoPlayerManager.currentViewModel.item.displayTitle,
            .iTunesMetadataTrackSubTitle: videoPlayerManager.currentViewModel.item.subtitle,
        ]

        return allMetadata.compactMap { createMetadataItem(for: $0, value: $1) }
    }

    private func createMetadataItem(
        for identifier: AVMetadataIdentifier,
        value: Any?
    ) -> AVMetadataItem? {
        guard let value else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        // Specify "und" to indicate an undefined language.
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem
    }

    func play() {
        playerViewController.player?.play()
        videoPlayerManager.sendStartReport()
    }

    func stop() {
        playerViewController.player?.pause()
        videoPlayerManager.sendStopReport()
    }
}

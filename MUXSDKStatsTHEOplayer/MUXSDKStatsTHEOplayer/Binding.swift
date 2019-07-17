//
//  Binding.swift
//  TestbedObjc
//
//  Created by Ruslan Sokolov on 7/12/19.
//  Copyright © 2019 Ruslan Sokolov. All rights reserved.
//

import Foundation
import MuxCore
import THEOplayerSDK

internal class Binding: NSObject {
    let name: String
    let software: String
    fileprivate(set) var player: THEOplayer?

    fileprivate var playListener: EventListener?
    fileprivate var playingListener: EventListener?
    fileprivate var pauseListener: EventListener?
    fileprivate var timeListener: EventListener?
    fileprivate var seekListener: EventListener?
    fileprivate var seekedListener: EventListener?
    fileprivate var errorListener: EventListener?
    fileprivate var completeListener: EventListener?
    fileprivate var adBreakBeginListener: EventListener?
    fileprivate var adBreakEndListener: EventListener?
    fileprivate var adBeginListener: EventListener?
    fileprivate var adEndListener: EventListener?
    fileprivate var adErrorListener: EventListener?

    var size: CGSize = .zero
    var duration: Double = 0
    var isLive = false

    fileprivate var adProgress: AdProgress = .started
    var ad: Ad? {
        didSet {
            adProgress = .started
        }
    }

    init(name: String, software: String) {
        self.name = name
        self.software = software
    }

    func attachPlayer(_ player: THEOplayer) {
        if let _ = self.player {
            self.detachPlayer()
        }
        self.player = player
        addEventListeners()
    }

    func detachPlayer() {
        removeEventListeners()
        self.player = nil
    }

    func resetVideoData() {
        size = .zero
        duration = 0
        isLive = false
    }

    func dispatchEvent<Event: MUXSDKPlaybackEvent>(
        _ type: Event.Type,
        checkVideoData: Bool = false,
        includeAdData: Bool = false,
        error: String? = nil) {
        if checkVideoData {
            self.checkVideoData()
        }

        let event = Event()
        if (includeAdData) {
            event.viewData = self.ad?.viewData
        }
        let name = self.name

        playerData { (data) in
            event.playerData = data
            if let error = error {
                event.playerData.playerErrorMessage = error
            }
            MUXSDKCore.dispatchEvent(event, forPlayer: name)
        }
    }
}

fileprivate extension Binding {
    func playerData(completion: @escaping (_ data: MUXSDKPlayerData) -> ()) {
        let data = MUXSDKPlayerData()
        guard let player = self.player else { return }

        data.playerMuxPluginName = Constants.pluginName
        data.playerMuxPluginVersion = Constants.pluginVersion
        data.playerSoftwareName = self.software
        data.playerLanguageCode = NSLocale.preferredLanguages.first
        data.playerWidth = player.frame.size.width * UIScreen.main.nativeScale as NSNumber
        data.playerHeight = player.frame.size.height * UIScreen.main.nativeScale as NSNumber
        data.playerIsFullscreen = player.frame.equalTo(UIScreen.main.bounds) ? "true" : "false"
        data.playerIsPaused = NSNumber(booleanLiteral: player.paused)
        player.requestCurrentTime { (time, _) in
            data.playerPlayheadTime = NSNumber(value: (Int64)((time ?? 0) * 1000))
            completion(data)
        }
    }

    func checkVideoData() {
        guard let player = player else { return }
        var updated = false

        player.requestVideoWidth { (width, _) in
            player.requestVideoHeight { (height, _) in
                let size = CGSize(width: width ?? 0, height: height ?? 0)
                if !self.size.equalTo(size) {
                    self.size = size
                    updated = true
                }
                let duration = player.duration ?? 0
                if !self.duration.isEqual(to: duration) {
                    self.duration = duration
                    updated = true
                }
                if !self.duration.isFinite && player.readyState != .HAVE_NOTHING && !self.isLive {
                    self.isLive = true
                    updated = true
                }
                if updated {
                    let data = MUXSDKVideoData()
                    if !size.equalTo(.zero) {
                        data.videoSourceWidth = NSNumber(value: Double(size.width))
                        data.videoSourceHeight = NSNumber(value: Double(size.height))
                    }
                    if self.duration > 0 {
                        data.videoSourceDuration = NSNumber(value: Double(self.duration))
                    }
                    if self.isLive {
                        data.videoSourceIsLive = self.isLive ? "true" : "false"
                    }
                    let event = MUXSDKDataEvent()
                    event.videoData = data
                    MUXSDKCore.dispatchEvent(event, forPlayer: self.name)
                }
            }
        }
    }

    func addEventListeners() {
        guard let player = player else { return }

        playListener = player.addEventListener(type: PlayerEventTypes.LOAD_START) { (_: LoadStartEvent) in
            self.dispatchEvent(MUXSDKPlayEvent.self, checkVideoData: true)
        }
        playingListener = player.addEventListener(type: PlayerEventTypes.PLAYING) { (_: PlayingEvent) in
            self.isAdActive {
                if !$0 {
                    self.dispatchEvent(MUXSDKPlayingEvent.self, checkVideoData: true)
                }
            }
        }
        pauseListener = player.addEventListener(type: PlayerEventTypes.PAUSE) { (_: PauseEvent) in
            self.isAdActive {
                if $0 {
                    self.dispatchEvent(MUXSDKAdPauseEvent.self, checkVideoData: true, includeAdData: true)
                } else {
                    player.requestCurrentTime(completionHandler: { (time, _) in
                        if let time = time, let duration = player.duration, time < duration {
                            self.dispatchEvent(MUXSDKPauseEvent.self, checkVideoData: true)
                        }
                    })
                }
            }
        }
        timeListener = player.addEventListener(type: PlayerEventTypes.TIME_UPDATE) { (_: TimeUpdateEvent) in
            self.isAdActive { adActive in
                player.requestCurrentTime { (time, _) in
                    if let time = time, let duration = player.duration {
                        if adActive {
                            if time >= duration * 0.25 {
                                if self.adProgress < .firstQuartile {
                                    self.dispatchEvent(MUXSDKAdFirstQuartileEvent.self, includeAdData: true)
                                    self.adProgress = .firstQuartile
                                }
                            }
                            if time >= duration * 0.5 {
                                if self.adProgress < .midpoint {
                                    self.dispatchEvent(MUXSDKAdMidpointEvent.self, includeAdData: true)
                                    self.adProgress = .midpoint
                                }
                            }
                            if time >= duration * 0.75 {
                                if self.adProgress < .thirdQuartile {
                                    self.dispatchEvent(MUXSDKAdThirdQuartileEvent.self, includeAdData: true)
                                    self.adProgress = .thirdQuartile
                                }
                            }
                        } else {
                            if time > 0, time < duration {
                                self.dispatchEvent(MUXSDKTimeUpdateEvent.self, checkVideoData: true)
                            }
                        }
                    }
                }
            }
        }
        seekListener = player.addEventListener(type: PlayerEventTypes.SEEKING) { (_: SeekingEvent) in
            self.dispatchEvent(MUXSDKInternalSeekingEvent.self)
        }
        seekedListener = player.addEventListener(type: PlayerEventTypes.SEEKED) { (_: SeekedEvent) in
            self.dispatchEvent(MUXSDKSeekedEvent.self)
        }
        errorListener = player.addEventListener(type: PlayerEventTypes.ERROR) { (event: ErrorEvent) in
            self.dispatchEvent(MUXSDKErrorEvent.self, checkVideoData: true, error: event.error)
        }
        completeListener = player.addEventListener(type: PlayerEventTypes.ENDED) { (_: EndedEvent) in
            self.dispatchEvent(MUXSDKViewEndEvent.self, checkVideoData: true)
        }
        adBreakBeginListener = player.ads.addEventListener(type: AdsEventTypes.AD_BREAK_BEGIN) { (_: AdBreakBeginEvent) in
            self.dispatchEvent(MUXSDKAdBreakStartEvent.self, includeAdData: true)
        }
        adBreakEndListener = player.ads.addEventListener(type: AdsEventTypes.AD_BREAK_END) { (_: AdBreakEndEvent) in
            self.dispatchEvent(MUXSDKAdBreakEndEvent.self, includeAdData: true)
            self.ad = nil
        }
        adBeginListener = player.ads.addEventListener(type: AdsEventTypes.AD_BEGIN) { (event: AdBeginEvent) in
            self.ad = event.ad
            self.dispatchEvent(MUXSDKAdPlayingEvent.self, includeAdData: true)
        }
        adEndListener = player.ads.addEventListener(type: AdsEventTypes.AD_END) { (_: AdEndEvent) in
            self.dispatchEvent(MUXSDKAdEndedEvent.self, includeAdData: true)
            self.ad = nil
        }
        adErrorListener = player.ads.addEventListener(type: AdsEventTypes.AD_ERROR) { (event: AdErrorEvent) in
            self.dispatchEvent(MUXSDKAdErrorEvent.self, error: event.error)
            self.ad = nil
        }
    }

    func removeEventListeners() {
        if let playListener = playListener {
            player?.removeEventListener(type: PlayerEventTypes.PLAY, listener: playListener)
            self.playListener = nil
        }
        if let playingListener = playingListener {
            player?.removeEventListener(type: PlayerEventTypes.PLAYING, listener: playingListener)
            self.playingListener = nil
        }
        if let pauseListener = pauseListener {
            player?.removeEventListener(type: PlayerEventTypes.PAUSE, listener: pauseListener)
            self.pauseListener = nil
        }
        if let timeListener = timeListener {
            player?.removeEventListener(type: PlayerEventTypes.TIME_UPDATE, listener: timeListener)
            self.timeListener = nil
        }
        if let seekListener = seekListener {
            player?.removeEventListener(type: PlayerEventTypes.SEEKING, listener: seekListener)
            self.seekListener = nil
        }
        if let seekedListener = seekedListener {
            player?.removeEventListener(type: PlayerEventTypes.SEEKED, listener: seekedListener)
            self.seekedListener = nil
        }
        if let errorListener = errorListener {
            player?.removeEventListener(type: PlayerEventTypes.ERROR, listener: errorListener)
            self.errorListener = nil
        }
        if let completeListener = completeListener {
            player?.removeEventListener(type: PlayerEventTypes.ENDED, listener: completeListener)
            self.completeListener = nil
        }
        if let adBreakBeginListener = adBreakBeginListener {
            player?.removeEventListener(type: AdsEventTypes.AD_BREAK_BEGIN, listener: adBreakBeginListener)
            self.adBreakBeginListener = nil
        }
        if let adBreakEndListener = adBreakEndListener {
            player?.removeEventListener(type: AdsEventTypes.AD_BREAK_END, listener: adBreakEndListener)
            self.adBreakEndListener = nil
        }
        if let adBeginListener = adBeginListener {
            player?.removeEventListener(type: AdsEventTypes.AD_BEGIN, listener: adBeginListener)
            self.adBeginListener = nil
        }
        if let adEndListener = adEndListener {
            player?.removeEventListener(type: AdsEventTypes.AD_END, listener: adEndListener)
            self.adEndListener = nil
        }
        if let adErrorListener = adErrorListener {
            player?.removeEventListener(type: AdsEventTypes.AD_ERROR, listener: adErrorListener)
            self.adErrorListener = nil
        }
    }

    func isAdActive(completion: @escaping (_ isActive: Bool) -> ()) {
        player?.ads.requestCurrentAdBreak { (ads, _) in completion(ads != nil) }
    }
}

fileprivate enum AdProgress: Int, Comparable {
    case started, firstQuartile, midpoint, thirdQuartile

    public static func < (a: AdProgress, b: AdProgress) -> Bool {
        return a.rawValue < b.rawValue
    }
}

fileprivate extension Ad {
    var viewData: MUXSDKViewData {
        let view = MUXSDKViewData()
        view.viewPrerollAdId = id
        return view
    }
}
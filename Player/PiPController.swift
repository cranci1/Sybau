//
//  PiPController.swift
//  Sybau
//

import AVKit
import AVFoundation

public protocol PiPControllerDelegate: AnyObject {
    func pipControllerWillStart(_ controller: PiPController)
    func pipControllerDidStart(_ controller: PiPController)
    func pipControllerDidFailToStart(_ controller: PiPController)
    func pipControllerWillStop(_ controller: PiPController)
    func pipControllerDidStop(_ controller: PiPController)
    func pipController(_ controller: PiPController, restoreUserInterfaceForStop completionHandler: @escaping (Bool) -> Void)
    func pipControllerPlay(_ controller: PiPController)
    func pipControllerPause(_ controller: PiPController)
    func pipController(_ controller: PiPController, skipByInterval interval: CMTime, completion: @escaping () -> Void)
    func pipControllerIsPlaying(_ controller: PiPController) -> Bool
    func pipControllerDuration(_ controller: PiPController) -> Double
    func pipControllerCurrentTime(_ controller: PiPController) -> Double
}

public final class PiPController: NSObject {
    private var pipController: AVPictureInPictureController?
    private weak var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var isStartInProgress = false
    
    // MARK: - Public interface
    
    weak var delegate: PiPControllerDelegate?
    
    var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }
    
    var isPictureInPictureActive: Bool {
        pipController?.isPictureInPictureActive ?? false
    }
    
    var isPictureInPicturePossible: Bool {
        pipController?.isPictureInPicturePossible ?? false
    }
    
    // MARK: - Init
    
    init(sampleBufferDisplayLayer: AVSampleBufferDisplayLayer) {
        self.sampleBufferDisplayLayer = sampleBufferDisplayLayer
        super.init()
        setupPictureInPicture()
    }
    
    // MARK: - Setup
    
    private func setupPictureInPicture() {
        guard isPictureInPictureSupported, let displayLayer = sampleBufferDisplayLayer else { return }
        
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.requiresLinearPlayback = false
#if !os(tvOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
#endif
        pipController = controller
    }
    
    // MARK: - Start / stop
    
    func startPictureInPicture() {
        guard isPictureInPictureSupported else {
            Logger.shared.log("PiP not supported on this device", type: "mpv")
            delegate?.pipControllerDidFailToStart(self)
            return
        }
        
        if pipController == nil { setupPictureInPicture() }
        guard let pip = pipController else {
            delegate?.pipControllerDidFailToStart(self)
            return
        }
        guard !isStartInProgress, !pip.isPictureInPictureActive else { return }
        
        guard pip.isPictureInPicturePossible else {
            Logger.shared.log("PiP start failed: not possible right now", type: "mpv")
            delegate?.pipControllerDidFailToStart(self)
            return
        }
        
        isStartInProgress = true
        pip.startPictureInPicture()
    }
    
    func stopPictureInPicture() {
        cancelPendingStart()
        pipController?.stopPictureInPicture()
    }
    
    func invalidatePlaybackState() {
        pipController?.invalidatePlaybackState()
    }
    
    func cancelPendingStart() {
        isStartInProgress = false
    }
}

// MARK: - AVPictureInPictureControllerDelegate
extension PiPController: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        delegate?.pipControllerWillStart(self)
    }
    
    public func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        cancelPendingStart()
        delegate?.pipControllerDidStart(self)
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        cancelPendingStart()
        Logger.shared.log("Failed to start PiP: \(error)", type: "mpv")
        delegate?.pipControllerDidFailToStart(self)
    }
    
    public func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        delegate?.pipControllerWillStop(self)
    }
    
    public func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        cancelPendingStart()
        delegate?.pipControllerDidStop(self)
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        delegate?.pipController(self, restoreUserInterfaceForStop: completionHandler)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        if playing {
            delegate?.pipControllerPlay(self)
        } else {
            delegate?.pipControllerPause(self)
        }
        DispatchQueue.main.async { [weak self] in
            self?.pipController?.invalidatePlaybackState()
        }
    }
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}
    
    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        delegate?.pipController(self, skipByInterval: skipInterval) { [weak self] in
            DispatchQueue.main.async { self?.pipController?.invalidatePlaybackState() }
            completionHandler()
        }
    }
    
    public func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        let duration = delegate?.pipControllerDuration(self) ?? 0
        guard duration > 0 else {
            return CMTimeRange(start: .zero, duration: .positiveInfinity)
        }
        return CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 1000)
        )
    }
    
    public func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        !(delegate?.pipControllerIsPlaying(self) ?? false)
    }
}

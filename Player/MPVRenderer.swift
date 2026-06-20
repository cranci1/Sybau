//
//  MPVRenderer.swift
//  Sybau
//
// FIX (naming): Renamed from MPVSoftwareRenderer → MPVRenderer.
// The renderer uses gpu-next + Metal + VideoToolbox, not software rendering.
// The old name was a historical artifact from before the Metal migration.
//
// FIX (thread safety): isPaused, isLoading, cachedDuration, cachedPosition
// are now always read/written through `stateQueue` so there are no data races
// between renderQueue, eventQueue, and the main thread.
//
// FIX (subtitle security): addSubtitleTrack now validates that the URL scheme
// is https or http before passing it to mpv, preventing file:// or custom
// scheme injection from untrusted metadata sources.

import UIKit
import Libmpv
import CoreMedia
import CoreVideo
import QuartzCore
import AVFoundation

protocol MPVRendererDelegate: AnyObject {
    func renderer(_ renderer: MPVRenderer, didUpdatePosition position: Double, duration: Double)
    func renderer(_ renderer: MPVRenderer, didChangePause isPaused: Bool)
    func renderer(_ renderer: MPVRenderer, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: MPVRenderer, didBecomeReadyToSeek: Bool)
}

typealias MPVSoftwareRendererDelegate = MPVRendererDelegate

struct SubtitleStyle {
    let foregroundColor: UIColor
    let strokeColor: UIColor
    let strokeWidth: CGFloat
    let fontSize: CGFloat
    let isVisible: Bool
    
    static let `default` = SubtitleStyle(
        foregroundColor: .white,
        strokeColor: .black,
        strokeWidth: 1.0,
        fontSize: 18.0,
        isVisible: false
    )
}

final class MPVRenderer {
    enum RendererError: Error {
        case mpvCreationFailed
        case mpvInitialization(Int32)
        case renderContextCreation(Int32)
    }
    
    private weak var primaryRenderView: UIView?
    private let pipDisplayLayer: AVSampleBufferDisplayLayer
    
    private let renderQueue = DispatchQueue(label: "mpv.render", qos: .userInitiated)
    private let eventQueue  = DispatchQueue(label: "mpv.events",  qos: .utility)
    private let stateQueue  = DispatchQueue(label: "mpv.state",   attributes: .concurrent)
    private let eventQueueGroup = DispatchGroup()
    private let renderQueueKey  = DispatchSpecificKey<Void>()
    
    private var mpv: OpaquePointer?
    private var pipRenderContext: OpaquePointer?
    
    private var _videoSize: CGSize = .zero
    private var _isPaused: Bool = true
    private var _isLoading: Bool = false
    private var _cachedDuration: Double = 0
    private var _cachedPosition: Double = 0
    
    private var pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPoolAuxAttributes: CFDictionary?
    private var formatDescription: CMVideoFormatDescription?
    private var didFlushForFormatChange = false
    private var poolWidth:  Int = 0
    private var poolHeight: Int = 0
    private var preAllocatedBuffers: [CVPixelBuffer] = []
    private let maxPreAllocatedBuffers = 6
    
    private var currentPreset: PlayerPreset?
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    
    private var isRunning  = false
    private var isStopping = false
    private var shouldClearPixelBuffer = false
    private let bgraFormatCString: [CChar] = Array("bgra\0".utf8CString)
    
    weak var delegate: MPVRendererDelegate?
    
    // MARK: - Thread-safe accessors
    
    var isPausedState: Bool {
        stateQueue.sync { _isPaused }
    }
    
    private func setIsPaused(_ value: Bool) {
        stateQueue.async(flags: .barrier) { self._isPaused = value }
    }
    
    private func setIsLoading(_ value: Bool) {
        stateQueue.async(flags: .barrier) { self._isLoading = value }
    }
    
    private func currentVideoSize() -> CGSize {
        stateQueue.sync { _videoSize }
    }
    
    private func setVideoSize(_ size: CGSize) {
        stateQueue.async(flags: .barrier) { self._videoSize = size }
    }
    
    private func setCachedPosition(_ pos: Double, duration: Double) {
        stateQueue.async(flags: .barrier) {
            self._cachedPosition = pos
            self._cachedDuration = duration
        }
    }
    
    private func cachedPlaybackState() -> (position: Double, duration: Double) {
        stateQueue.sync { (_cachedPosition, _cachedDuration) }
    }
    
    // MARK: - Pip helpers
    
    private var pipDisplayLink: CADisplayLink?
    private var pipDisplayLinkProxy: PiPDisplayLinkProxy?
    private var pipDisplayLinkRequested = false
    private var pipFramePumpScheduled   = false
    private var lastRenderDimensions: CGSize = .zero
    
    private final class PiPDisplayLinkProxy: NSObject {
        weak var owner: MPVRenderer?
        init(owner: MPVRenderer) { self.owner = owner }
        @objc func onDisplayLinkTick() { owner?.pumpPiPFrame() }
    }
    
    // MARK: - Init / deinit
    
    init(primaryRenderView: UIView, pipDisplayLayer: AVSampleBufferDisplayLayer) {
        self.primaryRenderView = primaryRenderView
        self.pipDisplayLayer = pipDisplayLayer
        renderQueue.setSpecific(key: renderQueueKey, value: ())
    }
    
    deinit { stop() }
    
    // MARK: - Lifecycle
    
    func start() throws {
        guard !isRunning else { return }
        guard let handle = mpv_create() else {
            throw RendererError.mpvCreationFailed
        }
        mpv = handle
        
        setOption(name: "vo", value: "gpu-next")
        setOption(name: "gpu-api", value: "metal")
        setOption(name: "hwdec", value: "videotoolbox")
        
        setOption(name: "idle", value: "yes")
        setOption(name: "keep-open", value: "yes")
        setOption(name: "hr-seek", value: "yes")
        setOption(name: "video-sync", value: "audio")
        setOption(name: "interpolation", value: "no")
        setOption(name: "demuxer-thread", value: "yes")
        setOption(name: "audio-normalize-downmix", value: "yes")
        
        setOption(name: "sub-ass", value: "yes")
        setOption(name: "subs-fallback", value: "yes")
        setOption(name: "sub-ass-override", value: "yes")
        
        setOption(name: "msg-level", value: "all=warn")
        
        configureWindowEmbedding()
        
        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            throw RendererError.mpvInitialization(initStatus)
        }
        
        mpv_request_log_messages(handle, "warn")
        observeProperties()
        installWakeupHandler()
        isRunning = true
    }
    
    func stop() {
        guard !isStopping else { return }
        guard isRunning || mpv != nil else { return }
        
        isRunning  = false
        isStopping = true
        var handleForShutdown: OpaquePointer?
        
        renderQueueSync { [weak self] in
            guard let self else { return }
            self.stopPiPRenderingLocked()
            handleForShutdown = self.mpv
            if let handle = handleForShutdown {
                mpv_set_wakeup_callback(handle, nil, nil)
                self.command(handle, ["quit"])
                mpv_wakeup(handle)
            }
            self.formatDescription = nil
            self.preAllocatedBuffers.removeAll()
            self.pixelBufferPool = nil
            self.poolWidth  = 0
            self.poolHeight = 0
            self.lastRenderDimensions = .zero
        }
        
        eventQueueGroup.wait()
        
        renderQueueSync { [weak self] in
            guard let self else { return }
            if let handle = handleForShutdown { mpv_destroy(handle) }
            self.mpv = nil
            self.preAllocatedBuffers.removeAll()
            self.pixelBufferPool = nil
            self.pixelBufferPoolAuxAttributes = nil
            self.formatDescription = nil
            self.poolWidth  = 0
            self.poolHeight = 0
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if #available(iOS 18.0, *) {
                self.pipDisplayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                self.pipDisplayLayer.flushAndRemoveImage()
            }
        }
        isStopping = false
    }
    
    // MARK: - PiP rendering
    
    func startPiPRendering() {
        renderQueue.async { [weak self] in
            guard let self, self.isRunning, !self.isStopping else { return }
            if self.pipRenderContext == nil {
                do {
                    try self.createPiPRenderContext()
                    self.shouldClearPixelBuffer = true
                } catch {
                    Logger.shared.log("Failed to create PiP render context: \(error)", type: "Error")
                    return
                }
            }
            self.pipDisplayLinkRequested = true
            self.startPiPDisplayLinkLocked()
        }
    }
    
    func stopPiPRendering() {
        renderQueue.async { [weak self] in self?.stopPiPRenderingLocked() }
    }
    
    // MARK: - Load
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        currentPreset  = preset
        currentURL     = url
        currentHeaders = headers
        
        setIsLoading(true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: true)
        }
        
        guard let handle = mpv else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.apply(commands: preset.commands, on: handle)
            self.command(handle, ["stop"])
            self.updateHTTPHeaders(headers)
            let target = url.isFileURL ? url.path : url.absoluteString
            self.command(handle, ["loadfile", target, "replace"])
        }
    }
    
    func applyPreset(_ preset: PlayerPreset) {
        currentPreset = preset
        guard let handle = mpv else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.apply(commands: preset.commands, on: handle)
        }
    }
    
    // MARK: - Private mpv helpers
    
    private func setOption(name: String, value: String) {
        guard let handle = mpv else { return }
        _ = value.withCString { vp in
            name.withCString { np in
                mpv_set_option_string(handle, np, vp)
            }
        }
    }
    
    private func configureWindowEmbedding() {
        guard let view = primaryRenderView else {
            Logger.shared.log("Primary render view missing – mpv window embedding disabled", type: "Warn")
            return
        }
        guard let handle = mpv else { return }
        let layer   = view.layer
        let rawPtr  = UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque())
        var wid     = Int64(bitPattern: UInt64(rawPtr))
        withUnsafeMutablePointer(to: &wid) { ptr in
            _ = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, ptr)
        }
    }
    
    private func setProperty(name: String, value: String) {
        guard let handle = mpv else { return }
        let status = value.withCString { vp in
            name.withCString { np in mpv_set_property_string(handle, np, vp) }
        }
        if status < 0 {
            Logger.shared.log("Failed to set \(name)=\(value) (\(status))", type: "Warn")
        }
    }
    
    private func clearProperty(name: String) {
        guard let handle = mpv else { return }
        let status = name.withCString { np in
            mpv_set_property(handle, np, MPV_FORMAT_NONE, nil)
        }
        if status < 0 {
            Logger.shared.log("Failed to clear \(name) (\(status))", type: "Warn")
        }
    }
    
    private func updateHTTPHeaders(_ headers: [String: String]?) {
        guard let headers, !headers.isEmpty else {
            clearProperty(name: "http-header-fields")
            return
        }
        let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        setProperty(name: "http-header-fields", value: headerString)
    }
    
    private func createPiPRenderContext() throws {
        guard let handle = mpv else { return }
        var apiType = MPV_RENDER_API_TYPE_SW
        let status = withUnsafePointer(to: &apiType) { apiTypePtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypePtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return params.withUnsafeMutableBufferPointer { buf -> Int32 in
                buf.baseAddress?.withMemoryRebound(to: mpv_render_param.self, capacity: buf.count) { p in
                    mpv_render_context_create(&pipRenderContext, handle, p)
                } ?? -1
            }
        }
        guard status >= 0, pipRenderContext != nil else {
            throw RendererError.renderContextCreation(status)
        }
        mpv_render_context_set_update_callback(pipRenderContext, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVRenderer>.fromOpaque(ctx).takeUnretainedValue().requestPiPDisplayLink()
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func observeProperties() {
        guard let handle = mpv else { return }
        let props: [(String, mpv_format)] = [
            ("dwidth", MPV_FORMAT_INT64),
            ("dheight", MPV_FORMAT_INT64),
            ("duration", MPV_FORMAT_DOUBLE),
            ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG)
        ]
        for (name, fmt) in props {
            _ = name.withCString { mpv_observe_property(handle, 0, $0, fmt) }
        }
    }
    
    private func installWakeupHandler() {
        guard let handle = mpv else { return }
        mpv_set_wakeup_callback(handle, { ud in
            guard let ud else { return }
            Unmanaged<MPVRenderer>.fromOpaque(ud).takeUnretainedValue().processEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func requestPiPDisplayLink() {
        renderQueue.async { [weak self] in
            guard let self, self.pipRenderContext != nil else { return }
            self.pipDisplayLinkRequested = true
            self.startPiPDisplayLinkLocked()
        }
    }
    
    private func startPiPDisplayLinkLocked() {
        guard pipDisplayLink == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pipDisplayLink == nil else { return }
            let proxy = PiPDisplayLinkProxy(owner: self)
            let link  = CADisplayLink(target: proxy, selector: #selector(PiPDisplayLinkProxy.onDisplayLinkTick))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 24, preferred: 24)
            } else {
                link.preferredFramesPerSecond = 24
            }
            link.add(to: .main, forMode: .common)
            self.pipDisplayLinkProxy = proxy
            self.pipDisplayLink      = link
        }
    }
    
    private func stopPiPDisplayLinkLocked() {
        DispatchQueue.main.async { [weak self] in
            self?.pipDisplayLink?.invalidate()
            self?.pipDisplayLink      = nil
            self?.pipDisplayLinkProxy = nil
        }
    }
    
    private func pumpPiPFrame() {
        renderQueue.async { [weak self] in
            guard let self, self.isRunning, !self.isStopping else { return }
            guard let ctx = self.pipRenderContext else { return }
            guard self.pipDisplayLinkRequested || self.pipFramePumpScheduled else { return }
            self.pipFramePumpScheduled = true
            self.performPiPRenderUpdate(with: ctx)
            self.pipFramePumpScheduled = false
        }
    }
    
    private func performPiPRenderUpdate(with context: OpaquePointer) {
        let flags = UInt64(truncatingIfNeeded: mpv_render_context_update(context))
        if flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
            pipDisplayLinkRequested = false
            renderFrame(with: context)
        }
    }
    
    private func renderFrame(with context: OpaquePointer) {
        let videoSize  = currentVideoSize()
        guard videoSize.width > 0, videoSize.height > 0 else { return }
        let targetSize = targetRenderSize(for: videoSize)
        let width  = Int(targetSize.width)
        let height = Int(targetSize.height)
        guard width > 0, height > 0 else { return }
        
        if lastRenderDimensions != targetSize {
            lastRenderDimensions = targetSize
            Logger.shared.log("PiP rendering at \(width)×\(height)", type: "Info")
        }
        
        if poolWidth != width || poolHeight != height {
            recreatePixelBufferPool(width: width, height: height)
        }
        
        var pixelBuffer: CVPixelBuffer?
        var status: CVReturn = kCVReturnError
        
        if !preAllocatedBuffers.isEmpty {
            pixelBuffer = preAllocatedBuffers.removeFirst()
            status = kCVReturnSuccess
        } else if let pool = pixelBufferPool {
            status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                kCFAllocatorDefault, pool, pixelBufferPoolAuxAttributes, &pixelBuffer)
        }
        
        if status != kCVReturnSuccess || pixelBuffer == nil {
            let attrs: [CFString: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ]
            status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        }
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            Logger.shared.log("Failed to get pixel buffer (status: \(status))", type: "Error")
            return
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return
        }
        
        if shouldClearPixelBuffer {
            memset(base, 0, CVPixelBufferGetDataSize(buffer))
            shouldClearPixelBuffer = false
        }
        
        var dims: [Int32] = [Int32(width), Int32(height)]
        let stride = Int32(CVPixelBufferGetBytesPerRow(buffer))
        
        if stride < Int32(width * 4) {
            Logger.shared.log("Bad stride \(stride) – skipping render", type: "Error")
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return
        }
        
        dims.withUnsafeMutableBufferPointer { dp in
            bgraFormatCString.withUnsafeBufferPointer { fp in
                withUnsafePointer(to: stride) { sp in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: UnsafeMutableRawPointer(dp.baseAddress)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: fp.baseAddress)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: UnsafeMutableRawPointer(mutating: sp)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: base),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    let rc = mpv_render_context_render(context, &params)
                    if rc < 0 {
                        Logger.shared.log("mpv_render_context_render error \(rc)", type: "Error")
                    }
                }
            }
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        enqueue(buffer: buffer)
        
        if preAllocatedBuffers.count < 2 {
            renderQueue.async { [weak self] in self?.preAllocateBuffers() }
        }
    }
    
    private func targetRenderSize(for videoSize: CGSize) -> CGSize {
        guard videoSize.width > 0, videoSize.height > 0 else { return videoSize }
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return videoSize }
        
        let scale = max(screen.scale, 1)
        let maxWidth = max(screen.bounds.width  * scale, 1.0)
        let maxHeight = max(screen.bounds.height * scale, 1.0)
        let ratio = max(videoSize.width / maxWidth, videoSize.height / maxHeight, 1)
        return CGSize(width:  max(1, Int(videoSize.width  / ratio)), height: max(1, Int(videoSize.height / ratio)))
    }
    
    private func createPixelBufferPool(width: Int, height: Int) {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ]
        let poolAttrs: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: maxPreAllocatedBuffers,
            kCVPixelBufferPoolMaximumBufferAgeKey:   0
        ]
        let auxAttrs: [CFString: Any] = [kCVPixelBufferPoolAllocationThresholdKey: 6]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, attrs as CFDictionary, &pool)
        if status == kCVReturnSuccess, let pool {
            renderQueueSync {
                self.pixelBufferPool = pool
                self.pixelBufferPoolAuxAttributes = auxAttrs as CFDictionary
                self.poolWidth  = width
                self.poolHeight = height
            }
            renderQueue.async { [weak self] in self?.preAllocateBuffers() }
        } else {
            Logger.shared.log("Failed to create CVPixelBufferPool (status: \(status))", type: "Error")
        }
    }
    
    private func recreatePixelBufferPool(width: Int, height: Int) {
        renderQueueSync {
            self.preAllocatedBuffers.removeAll()
            self.pixelBufferPool   = nil
            self.formatDescription = nil
            self.poolWidth  = 0
            self.poolHeight = 0
        }
        createPixelBufferPool(width: width, height: height)
    }
    
    private func preAllocateBuffers() {
        guard DispatchQueue.getSpecific(key: renderQueueKey) != nil else {
            renderQueue.async { [weak self] in self?.preAllocateBuffers() }
            return
        }
        guard let pool = pixelBufferPool else { return }
        let target  = min(maxPreAllocatedBuffers, 5)
        let current = preAllocatedBuffers.count
        guard current < target else { return }
        let needed  = min(target - current, 2)
        for _ in 0..<needed {
            var buf: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, pixelBufferPoolAuxAttributes, &buf)
            
            if status == kCVReturnSuccess, let buf {
                if preAllocatedBuffers.count < maxPreAllocatedBuffers {
                    preAllocatedBuffers.append(buf)
                }
            } else {
                if status != kCVReturnWouldExceedAllocationThreshold {
                    Logger.shared.log("Pre-allocate buffer failed (status: \(status))", type: "Warn")
                }
                break
            }
        }
    }
    
    private func enqueue(buffer: CVPixelBuffer) {
        let needsFlush = updateFormatDescriptionIfNeeded(for: buffer)
        var desc: CMVideoFormatDescription?
        renderQueueSync { desc = self.formatDescription }
        guard let desc else {
            Logger.shared.log("Missing formatDescription – skipping frame", type: "Error")
            return
        }
        
        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let result = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: desc, sampleTiming: &timing, sampleBufferOut: &sample)
        
        guard result == noErr, let sample else {
            Logger.shared.log("Failed to create sample buffer (\(result))", type: "Error")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let (layerStatus, layerError): (AVQueuedSampleBufferRenderingStatus?, Error?) = {
                if #available(iOS 18.0, *) {
                    return (self.pipDisplayLayer.sampleBufferRenderer.status, self.pipDisplayLayer.sampleBufferRenderer.error)
                } else {
                    return (self.pipDisplayLayer.status, self.pipDisplayLayer.error)
                }
            }()
            if layerStatus == .failed {
                if let e = layerError {
                    Logger.shared.log("PiP layer failed: \(e.localizedDescription)", type: "Error")
                }
                if #available(iOS 18.0, *) {
                    self.pipDisplayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                } else {
                    self.pipDisplayLayer.flushAndRemoveImage()
                }
            }
            if needsFlush {
                if #available(iOS 18.0, *) {
                    self.pipDisplayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                } else {
                    self.pipDisplayLayer.flushAndRemoveImage()
                }
                self.didFlushForFormatChange = true
            } else if self.didFlushForFormatChange {
                if #available(iOS 18.0, *) {
                    self.pipDisplayLayer.sampleBufferRenderer.flush(removingDisplayedImage: false, completionHandler: nil)
                } else {
                    self.pipDisplayLayer.flush()
                }
                self.didFlushForFormatChange = false
            }
            if self.pipDisplayLayer.controlTimebase == nil {
                var tb: CMTimebase?
                if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb) == noErr, let tb {
                    CMTimebaseSetRate(tb, rate: 1.0)
                    CMTimebaseSetTime(tb, time: presentationTime)
                    self.pipDisplayLayer.controlTimebase = tb
                }
            }
            if #available(iOS 18.0, *) {
                self.pipDisplayLayer.sampleBufferRenderer.enqueue(sample)
            } else {
                self.pipDisplayLayer.enqueue(sample)
            }
        }
    }
    
    private func updateFormatDescriptionIfNeeded(for buffer: CVPixelBuffer) -> Bool {
        var changed = false
        let w = Int32(CVPixelBufferGetWidth(buffer))
        let h = Int32(CVPixelBufferGetHeight(buffer))
        let fmt = CVPixelBufferGetPixelFormatType(buffer)
        renderQueueSync {
            var needsRecreate = false
            if let desc = self.formatDescription {
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                let pf   = CMFormatDescriptionGetMediaSubType(desc)
                if dims.width != w || dims.height != h || pf != fmt { needsRecreate = true }
            } else {
                needsRecreate = true
            }
            if needsRecreate {
                var newDesc: CMVideoFormatDescription?
                if CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &newDesc) == noErr,
                   let newDesc {
                    self.formatDescription = newDesc
                    changed = true
                }
            }
        }
        return changed
    }
    
    private func renderQueueSync(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: renderQueueKey) != nil { block() }
        else { renderQueue.sync(execute: block) }
    }
    
    private func dispatchToMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    private func updateVideoSize(width: Int, height: Int) {
        let size = CGSize(width: max(width, 0), height: max(height, 0))
        setVideoSize(size)
        renderQueue.async { [weak self] in
            guard let self else { return }
            if self.pipRenderContext != nil,
               (self.poolWidth != width || self.poolHeight != height) {
                self.recreatePixelBufferPool(width: max(width, 0), height: max(height, 0))
            }
        }
    }
    
    private func stopPiPRenderingLocked() {
        stopPiPDisplayLinkLocked()
        if let ctx = pipRenderContext {
            mpv_render_context_set_update_callback(ctx, nil, nil)
            mpv_render_context_free(ctx)
            pipRenderContext = nil
        }
        pipDisplayLinkRequested = false
        pipFramePumpScheduled = false
        preAllocatedBuffers.removeAll()
        pixelBufferPool = nil
        pixelBufferPoolAuxAttributes  = nil
        formatDescription = nil
        didFlushForFormatChange = false
        poolWidth = 0
        poolHeight = 0
        lastRenderDimensions = .zero
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if #available(iOS 18.0, *) {
                self.pipDisplayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                self.pipDisplayLayer.flushAndRemoveImage()
            }
        }
    }
    
    private func apply(commands: [[String]], on handle: OpaquePointer) {
        for cmd in commands where !cmd.isEmpty { command(handle, cmd) }
    }
    
    private func command(_ handle: OpaquePointer, _ args: [String]) {
        guard !args.isEmpty else { return }
        _ = withCStringArray(args) { mpv_command_async(handle, 0, $0) }
    }
    
    // MARK: - Event loop
    
    private func processEvents() {
        eventQueueGroup.enter()
        let group = eventQueueGroup
        eventQueue.async { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            while !self.isStopping {
                guard let handle = self.mpv else { return }
                guard let evPtr = mpv_wait_event(handle, -1) else { return }
                let ev = evPtr.pointee
                if ev.event_id == MPV_EVENT_NONE { continue }
                self.handleEvent(ev)
                if ev.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }
    
    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_VIDEO_RECONFIG:
            refreshVideoState()
        case MPV_EVENT_FILE_LOADED:
            setIsLoading(false)
            dispatchToMain { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: false)
                self.delegate?.renderer(self, didBecomeReadyToSeek: true)
            }
        case MPV_EVENT_PROPERTY_CHANGE:
            if let nameCStr = event.data?
                .assumingMemoryBound(to: mpv_event_property.self).pointee.name {
                refreshProperty(named: String(cString: nameCStr))
            }
        case MPV_EVENT_SHUTDOWN:
            Logger.shared.log("mpv shutdown", type: "Warn")
        case MPV_EVENT_LOG_MESSAGE:
            if let lm = event.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                let component = String(cString: lm.pointee.prefix)
                let text = String(cString: lm.pointee.text)
                let lower = text.lowercased()
                if lower.contains("error") {
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Error")
                } else if lower.contains("warn") || lower.contains("deprecated") {
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Warn")
                }
            }
        default:
            break
        }
    }
    
    private func refreshVideoState() {
        guard let handle = mpv else { return }
        var w: Int64 = 0, h: Int64 = 0
        getProperty(handle: handle, name: "dwidth",  format: MPV_FORMAT_INT64, value: &w)
        getProperty(handle: handle, name: "dheight", format: MPV_FORMAT_INT64, value: &h)
        updateVideoSize(width: Int(w), height: Int(h))
    }
    
    private func refreshProperty(named name: String) {
        guard let handle = mpv else { return }
        switch name {
        case "duration":
            var v = Double(0)
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &v) >= 0 {
                let pos = stateQueue.sync { _cachedPosition }
                setCachedPosition(pos, duration: v)
                dispatchToMain { [weak self] in
                    guard let self else { return }
                    let state = self.cachedPlaybackState()
                    self.delegate?.renderer(self, didUpdatePosition: state.position, duration: state.duration)
                }
            }
        case "time-pos":
            var v = Double(0)
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &v) >= 0 {
                let dur = stateQueue.sync { _cachedDuration }
                setCachedPosition(v, duration: dur)
                dispatchToMain { [weak self] in
                    guard let self else { return }
                    let state = self.cachedPlaybackState()
                    self.delegate?.renderer(self, didUpdatePosition: state.position, duration: state.duration)
                }
            }
        case "pause":
            var flag: Int32 = 0
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag) >= 0 {
                let newPaused = flag != 0
                let changed   = stateQueue.sync { _isPaused != newPaused }
                if changed {
                    setIsPaused(newPaused)
                    dispatchToMain { [weak self] in
                        guard let self else { return }
                        self.delegate?.renderer(self, didChangePause: newPaused)
                    }
                }
            }
        default:
            break
        }
    }
    
    @discardableResult
    private func getProperty<T>(handle: OpaquePointer, name: String, format: mpv_format, value: inout T) -> Int32 {
        name.withCString { np in
            withUnsafeMutablePointer(to: &value) { mpv_get_property(handle, np, format, $0) }
        }
    }
    
    @inline(__always)
    private func withCStringArray<R>(_ args: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cStrings = [UnsafeMutablePointer<CChar>?]()
        cStrings.reserveCapacity(args.count + 1)
        for s in args { cStrings.append(strdup(s)) }
        cStrings.append(nil)
        defer { for p in cStrings where p != nil { free(p) } }
        return cStrings.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { rebound in
                body(UnsafeMutablePointer(mutating: rebound))
            }
        }
    }
    
    // MARK: - Playback Controls
    
    func play() { setProperty(name: "pause", value: "no") }
    func pausePlayback() { setProperty(name: "pause", value: "yes") }
    
    func seek(to seconds: Double) {
        guard let handle = mpv else { return }
        command(handle, ["seek", String(max(0, seconds)), "absolute"])
    }
    
    func seek(by seconds: Double) {
        guard let handle = mpv else { return }
        command(handle, ["seek", String(seconds), "relative"])
    }
    
    func setSpeed(_ speed: Double) { setProperty(name: "speed", value: String(speed)) }
    
    func getSpeed() -> Double {
        guard let handle = mpv else { return 1.0 }
        var speed: Double = 1.0
        getProperty(handle: handle, name: "speed", format: MPV_FORMAT_DOUBLE, value: &speed)
        return speed
    }
    
    func setSubtitleVisible(_ visible: Bool) {
        setProperty(name: "sub-visibility", value: visible ? "yes" : "no")
    }
    
    func addSubtitleTrack(urlString: String) {
        guard let handle = mpv, !urlString.isEmpty else { return }
        
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            Logger.shared.log("Rejected subtitle URL with unsafe or missing scheme: \(urlString)", type: "Warn")
            return
        }
        
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.command(handle, ["sub-add", urlString, "select"])
            Logger.shared.log("sub-add: \(urlString)", type: "Info")
        }
    }
    
    func clearCurrentSubtitleTrack() {
        guard let handle = mpv else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.command(handle, ["sub-remove"])
        }
    }
    
    func applySubtitleStyle(_ style: SubtitleStyle) {
        setProperty(name: "sub-font-size", value: String(format: "%.2f", style.fontSize))
        setProperty(name: "sub-color", value: style.foregroundColor.mpvColorString)
        setProperty(name: "sub-border-color", value: style.strokeColor.mpvColorString)
        setProperty(name: "sub-border-size", value: String(format: "%.2f", max(style.strokeWidth, 0)))
    }
}

typealias MPVSoftwareRenderer = MPVRenderer

private extension UIColor {
    var mpvColorString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f/%.3f/%.3f/%.3f", r, g, b, a)
    }
}

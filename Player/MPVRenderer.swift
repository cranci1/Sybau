//
//  MPVRenderer.swift
//  Sybau
//

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

private final class DisplayLayerSink {
    let layer: AVSampleBufferDisplayLayer
    var formatDescription: CMVideoFormatDescription?
    var didFlushForFormatChange = false
    
    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }
    
    var status: AVQueuedSampleBufferRenderingStatus {
        if #available(iOS 18.0, *) { return layer.sampleBufferRenderer.status }
        return layer.status
    }
    
    var error: Error? {
        if #available(iOS 18.0, *) { return layer.sampleBufferRenderer.error }
        return layer.error
    }
    
    func flush(removingDisplayedImage: Bool) {
        if #available(iOS 18.0, *) {
            layer.sampleBufferRenderer.flush(removingDisplayedImage: removingDisplayedImage, completionHandler: nil)
        } else if removingDisplayedImage {
            layer.flushAndRemoveImage()
        } else {
            layer.flush()
        }
    }
    
    func enqueue(_ sample: CMSampleBuffer) {
        if #available(iOS 18.0, *) {
            layer.sampleBufferRenderer.enqueue(sample)
        } else {
            layer.enqueue(sample)
        }
    }
    
    func reset() {
        formatDescription = nil
        didFlushForFormatChange = false
    }
}

final class MPVRenderer {
    enum RendererError: Error {
        case mpvCreationFailed
        case mpvInitialization(Int32)
        case renderContextCreation(Int32)
    }
    
    private let renderQueue = DispatchQueue(label: "mpv.render", qos: .userInitiated)
    private let eventQueue  = DispatchQueue(label: "mpv.events", qos: .utility)
    private let stateQueue  = DispatchQueue(label: "mpv.state", attributes: .concurrent)
    private let eventQueueGroup = DispatchGroup()
    private let renderQueueKey = DispatchSpecificKey<Void>()
    
    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    
    private var _videoSize: CGSize = .zero
    private var _isPaused: Bool = true
    private var _isLoading: Bool = false
    private var _cachedDuration: Double = 0
    private var _cachedPosition: Double = 0
    
    private var pixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPoolAuxAttributes: CFDictionary?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0
    
    private let primarySink: DisplayLayerSink
    
    private var currentPreset: PlayerPreset?
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    
    private var isRunning = false
    private var isStopping = false
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
    
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var frameUpdateRequested = false
    private var framePumpScheduled = false
    private var lastRenderDimensions: CGSize = .zero
    
    private final class DisplayLinkProxy: NSObject {
        weak var owner: MPVRenderer?
        init(owner: MPVRenderer) { self.owner = owner }
        @objc func onDisplayLinkTick() { owner?.pumpFrame() }
    }
    
    // MARK: - Init / deinit
    
    init(primaryDisplayLayer: AVSampleBufferDisplayLayer) {
        self.primarySink = DisplayLayerSink(layer: primaryDisplayLayer)
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
        
        setOption(name: "vo", value: "libmpv")
        setOption(name: "hwdec", value: "videotoolbox")
        
        setOption(name: "idle", value: "yes")
        setOption(name: "hr-seek", value: "yes")
        setOption(name: "demuxer", value: "hls")
        setOption(name: "keep-open", value: "yes")
        setOption(name: "video-sync", value: "audio")
        setOption(name: "interpolation", value: "no")
        setOption(name: "demuxer-thread", value: "yes")
        setOption(name: "audio-normalize-downmix", value: "yes")
        
        setOption(name: "sub-ass", value: "yes")
        setOption(name: "subs-fallback", value: "yes")
        setOption(name: "sub-ass-override", value: "yes")
        
        setOption(name: "vd-lavc-dr", value: "yes")
        setOption(name: "vd-lavc-threads", value: "auto")
        
        setOption(name: "cache", value: "yes")
        setOption(name: "cache-secs", value: "60")
        setOption(name: "cache-initial", value: "100")
        setOption(name: "demuxer-max-bytes", value: "64M")
        setOption(name: "demuxer-readahead-secs", value: "10")
        setOption(name: "network-timeout", value: "20")
        
        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            throw RendererError.mpvInitialization(initStatus)
        }
        
        try createRenderContext()
        
        observeProperties()
        installWakeupHandler()
        isRunning = true
        startDisplayLinkLocked()
    }
    
    func stop() {
        guard !isStopping else { return }
        guard isRunning || mpv != nil else { return }
        
        isRunning = false
        isStopping = true
        var handleForShutdown: OpaquePointer?
        
        renderQueueSync { [weak self] in
            guard let self else { return }
            self.stopDisplayLinkLocked()
            if let ctx = self.renderContext {
                mpv_render_context_set_update_callback(ctx, nil, nil)
                mpv_render_context_free(ctx)
                self.renderContext = nil
            }
            handleForShutdown = self.mpv
            if let handle = handleForShutdown {
                mpv_set_wakeup_callback(handle, nil, nil)
                self.command(handle, ["quit"])
                mpv_wakeup(handle)
            }
            self.primarySink.reset()
            self.pixelBufferPool = nil
            self.poolWidth = 0
            self.poolHeight = 0
            self.lastRenderDimensions = .zero
        }
        
        eventQueueGroup.wait()
        
        renderQueueSync { [weak self] in
            guard let self else { return }
            if let handle = handleForShutdown { mpv_destroy(handle) }
            self.mpv = nil
            self.pixelBufferPool = nil
            self.pixelBufferPoolAuxAttributes = nil
            self.poolWidth = 0
            self.poolHeight = 0
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.primarySink.flush(removingDisplayedImage: true)
        }
        isStopping = false
    }
    
    // MARK: - Load
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        currentPreset = preset
        currentURL = url
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
    
    @discardableResult
    private func setProperty(name: String, value: String) -> Int32 {
        guard let handle = mpv else { return -1 }
        let status = value.withCString { vp in
            name.withCString { np in mpv_set_property_string(handle, np, vp) }
        }
        if status < 0 {
            Logger.shared.log("Failed to set \(name)=\(value) (\(status))", type: "Warn")
        }
        return status
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
    
    private func createRenderContext() throws {
        guard let handle = mpv else { return }
        var apiType = MPV_RENDER_API_TYPE_SW
        let status = withUnsafePointer(to: &apiType) { apiTypePtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: apiTypePtr)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return params.withUnsafeMutableBufferPointer { buf -> Int32 in
                buf.baseAddress?.withMemoryRebound(to: mpv_render_param.self, capacity: buf.count) { p in
                    mpv_render_context_create(&renderContext, handle, p)
                } ?? -1
            }
        }
        guard status >= 0, renderContext != nil else {
            throw RendererError.renderContextCreation(status)
        }
        mpv_render_context_set_update_callback(renderContext, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVRenderer>.fromOpaque(ctx).takeUnretainedValue().requestDisplayLink()
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
    
    private func requestDisplayLink() {
        renderQueue.async { [weak self] in
            guard let self, self.renderContext != nil else { return }
            self.frameUpdateRequested = true
            self.startDisplayLinkLocked()
        }
    }
    
    private func startDisplayLinkLocked() {
        guard displayLink == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.displayLink == nil else { return }
            let proxy = DisplayLinkProxy(owner: self)
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onDisplayLinkTick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.displayLinkProxy = proxy
            self.displayLink = link
        }
    }
    
    private func stopDisplayLinkLocked() {
        DispatchQueue.main.async { [weak self] in
            self?.displayLink?.invalidate()
            self?.displayLink = nil
            self?.displayLinkProxy = nil
        }
    }
    
    private func pumpFrame() {
        renderQueue.async { [weak self] in
            guard let self, self.isRunning, !self.isStopping else { return }
            guard let ctx = self.renderContext else { return }
            guard self.frameUpdateRequested || self.framePumpScheduled else { return }
            self.framePumpScheduled = true
            self.performRenderUpdate(with: ctx)
            self.framePumpScheduled = false
        }
    }
    
    private func performRenderUpdate(with context: OpaquePointer) {
        let flags = UInt64(truncatingIfNeeded: mpv_render_context_update(context))
        if flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
            frameUpdateRequested = false
            renderFrame(with: context)
        }
    }
    
    private func renderFrame(with context: OpaquePointer) {
        let videoSize = currentVideoSize()
        guard videoSize.width > 0, videoSize.height > 0 else { return }
        let targetSize = targetRenderSize(for: videoSize)
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        guard width > 0, height > 0 else { return }
        
        if lastRenderDimensions != targetSize {
            lastRenderDimensions = targetSize
            Logger.shared.log("Rendering at \(width)×\(height)", type: "Info")
        }
        
        if poolWidth != width || poolHeight != height {
            recreatePixelBufferPool(width: width, height: height)
        }
        
        var pixelBuffer: CVPixelBuffer?
        var status: CVReturn = kCVReturnError
        
        if let pool = pixelBufferPool {
            status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, pixelBufferPoolAuxAttributes, &pixelBuffer)
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
    }
    
    private func targetRenderSize(for videoSize: CGSize) -> CGSize {
        guard videoSize.width > 0, videoSize.height > 0 else { return videoSize }
        guard let screen = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first else { return videoSize }
        
        let scale = max(screen.scale, 1)
        let maxWidth = max(screen.bounds.width  * scale, 1.0)
        let maxHeight = max(screen.bounds.height * scale, 1.0)
        let ratio = max(videoSize.width / maxWidth, videoSize.height / maxHeight, 1)
        return CGSize(width: max(1, Int(videoSize.width / ratio)), height: max(1, Int(videoSize.height / ratio)))
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
        let poolAttrs: [CFString: Any] = [kCVPixelBufferPoolMaximumBufferAgeKey: 0]
        let auxAttrs: [CFString: Any] = [:]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, attrs as CFDictionary, &pool)
        
        if status == kCVReturnSuccess, let pool {
            renderQueueSync {
                self.pixelBufferPool = pool
                self.pixelBufferPoolAuxAttributes = auxAttrs as CFDictionary
                self.poolWidth = width
                self.poolHeight = height
            }
        } else {
            Logger.shared.log("Failed to create CVPixelBufferPool (status: \(status))", type: "Error")
        }
    }
    
    private func recreatePixelBufferPool(width: Int, height: Int) {
        renderQueueSync {
            self.pixelBufferPool = nil
            self.poolWidth = 0
            self.poolHeight = 0
        }
        createPixelBufferPool(width: width, height: height)
        renderQueue.async { [weak self] in
            self?.primarySink.formatDescription = nil
        }
    }
    
    private func enqueue(buffer: CVPixelBuffer) {
        let sink = primarySink
        
        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        
        let needsFlush = updateFormatDescription(for: buffer, in: sink)
        guard let desc = sink.formatDescription else {
            Logger.shared.log("Missing formatDescription – skipping frame", type: "Error")
            return
        }
        
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
            guard self != nil else { return }
            if sink.status == .failed {
                if let e = sink.error {
                    Logger.shared.log("Display layer failed: \(e.localizedDescription)", type: "Error")
                }
                sink.flush(removingDisplayedImage: true)
            }
            if needsFlush {
                sink.flush(removingDisplayedImage: true)
                sink.didFlushForFormatChange = true
            } else if sink.didFlushForFormatChange {
                sink.flush(removingDisplayedImage: false)
                sink.didFlushForFormatChange = false
            }
            if sink.layer.controlTimebase == nil {
                var tb: CMTimebase?
                if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb) == noErr, let tb {
                    CMTimebaseSetRate(tb, rate: 1.0)
                    CMTimebaseSetTime(tb, time: presentationTime)
                    sink.layer.controlTimebase = tb
                }
            }
            sink.enqueue(sample)
        }
    }
    
    private func updateFormatDescription(for buffer: CVPixelBuffer, in sink: DisplayLayerSink) -> Bool {
        var changed = false
        let w = Int32(CVPixelBufferGetWidth(buffer))
        let h = Int32(CVPixelBufferGetHeight(buffer))
        let fmt = CVPixelBufferGetPixelFormatType(buffer)
        
        var needsRecreate = false
        if let desc = sink.formatDescription {
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let pf = CMFormatDescriptionGetMediaSubType(desc)
            if dims.width != w || dims.height != h || pf != fmt { needsRecreate = true }
        } else {
            needsRecreate = true
        }
        if needsRecreate {
            var newDesc: CMVideoFormatDescription?
            if CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &newDesc) == noErr,
               let newDesc {
                sink.formatDescription = newDesc
                changed = true
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
            if self.renderContext != nil, (self.poolWidth != width || self.poolHeight != height) {
                self.recreatePixelBufferPool(width: max(width, 0), height: max(height, 0))
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
        case MPV_EVENT_END_FILE:
            if let ef = event.data?.assumingMemoryBound(to: mpv_event_end_file.self) {
                handleEndFile(reason: ef.pointee.reason, error: ef.pointee.error)
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
    
    private func handleEndFile(reason: mpv_end_file_reason, error: Int32) {
        switch reason {
        case MPV_END_FILE_REASON_ERROR:
            let wasLoading = stateQueue.sync { _isLoading }
            let errString = String(cString: mpv_error_string(error))
            Logger.shared.log("Playback failed to load: \(errString)", type: "Error")
            if wasLoading {
                setIsLoading(false)
                dispatchToMain { [weak self] in
                    guard let self else { return }
                    self.delegate?.renderer(self, didChangeLoading: false)
                }
            }
        case MPV_END_FILE_REASON_REDIRECT:
            break
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
                let changed = stateQueue.sync { _isPaused != newPaused }
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
    
    // MARK: - Volume Control
    func setVolume(_ volume: Float) {
        let value = Int(volume * 100)
        setProperty(name: "volume", value: String(value))
    }
}

private extension UIColor {
    var mpvColorString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.3f/%.3f/%.3f/%.3f", r, g, b, a)
    }
}

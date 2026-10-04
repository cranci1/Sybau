//
//  MPVRenderer.swift
//  Sybau
//

import UIKit
import Libmpv
import CoreMedia
import QuartzCore
import AVFoundation

protocol MPVRendererDelegate: AnyObject {
    func renderer(_ renderer: MPVRenderer, didUpdatePosition position: Double, duration: Double)
    func renderer(_ renderer: MPVRenderer, didChangePause isPaused: Bool)
    func renderer(_ renderer: MPVRenderer, didChangeLoading isLoading: Bool)
    func renderer(_ renderer: MPVRenderer, didBecomeReadyToSeek: Bool)
    func renderer(_ renderer: MPVRenderer, didUpdateSubtitleTracks tracks: [SubtitleTrackInfo])
    func renderer(_ renderer: MPVRenderer, didUpdateAudioTracks tracks: [AudioTrackInfo])
}

struct SubtitleTrackInfo: Equatable {
    let id: Int
    let title: String?
    let lang: String?
    let codec: String?
    let isExternal: Bool
    let isSelected: Bool
    
    var displayName: String {
        if let title, !title.isEmpty { return title }
        if let lang, !lang.isEmpty { return lang.uppercased() }
        return "Track \(id)"
    }
}

struct AudioTrackInfo: Equatable {
    let id: Int
    let title: String?
    let lang: String?
    let codec: String?
    let isExternal: Bool
    let isSelected: Bool
    
    var displayName: String {
        if let title, !title.isEmpty { return title }
        if let lang, !lang.isEmpty { return lang.uppercased() }
        return "Track \(id)"
    }
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

final class MPVRenderer {
    enum RendererError: Error {
        case mpvCreationFailed
        case mpvInitialization(Int32)
    }
    
    private let renderQueue = DispatchQueue(label: "mpv.render", qos: .userInitiated)
    private let eventQueue  = DispatchQueue(label: "mpv.events", qos: .utility)
    private let stateQueue  = DispatchQueue(label: "mpv.state", attributes: .concurrent)
    private let eventQueueGroup = DispatchGroup()
    private let renderQueueKey = DispatchSpecificKey<Void>()
    
    private var mpv: OpaquePointer?
    
    private var _videoSize: CGSize = .zero
    private var _isPaused: Bool = true
    private var _isLoading: Bool = false
    private var _cachedDuration: Double = 0
    private var _cachedPosition: Double = 0
    
    
    private var currentPreset: PlayerPreset?
    private var currentURL: URL?
    private var currentHeaders: [String: String]?
    
    private var isRunning = false
    private var isStopping = false
    private var eventLoopRunning = false
    
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
    
    private func setCachedPosition(_ position: Double, duration: Double? = nil) {
        stateQueue.async(flags: .barrier) {
            self._cachedPosition = max(0, position)
            if let duration {
                self._cachedDuration = max(0, duration)
            }
        }
    }
    
    private func cachedPlaybackState() -> (position: Double, duration: Double) {
        stateQueue.sync {
            (_cachedPosition, _cachedDuration)
        }
    }
    
    
    // MARK: - Init / deinit
    
    private weak var metalLayer: CAMetalLayer?
    private var refit: DispatchWorkItem?
    private var size = false
    private var lastReportedPosition: Double = -1
    
    init(primaryDisplayLayer: CAMetalLayer) {
        self.metalLayer = primaryDisplayLayer
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
        
        setOption(name: "profile", value: "fast")
        setOption(name: "hwdec", value: "videotoolbox,videotoolbox-copy")
        
        setOption(name: "idle", value: "yes")
        setOption(name: "hr-seek", value: "yes")
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
        
        try configureGPUVideoOutput()
        
        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            throw RendererError.mpvInitialization(initStatus)
        }
        
        observeProperties()
        installWakeupHandler()
        (metalLayer as? MetalLayer)?.onResize = { [weak self] in
            DispatchQueue.main.async { self?.layerResize() }
        }
        isRunning = true
    }
    
    func stop() {
        guard !isStopping else { return }
        guard isRunning || mpv != nil else { return }
        
        isRunning = false
        isStopping = true
        refit?.cancel()
        (metalLayer as? MetalLayer)?.onResize = nil
        var handleForShutdown: OpaquePointer?
        
        renderQueueSync { [weak self] in
            guard let self else { return }
            handleForShutdown = self.mpv
            if let handle = handleForShutdown {
                mpv_set_wakeup_callback(handle, nil, nil)
                self.command(handle, ["quit"])
                mpv_wakeup(handle)
            }
        }
        
        let waitResult = eventQueueGroup.wait(timeout: .now() + 3)
        if waitResult == .timedOut {
            Logger.shared.log("mpv event loop did not shut down within timeout", type: "Error")
            isStopping = false
            return
        }
        
        renderQueueSync { [weak self] in
            guard let self else { return }
            if let handle = handleForShutdown { mpv_destroy(handle) }
            self.mpv = nil
            self.eventLoopRunning = false
        }
        
        isStopping = false
    }
    
    // MARK: - Load
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        currentPreset = preset
        currentURL = url
        currentHeaders = headers
        size = false
        resetPositionThrottle()
        
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
    
    private func observeProperties() {
        guard let handle = mpv else { return }
        
        let properties: [(String, mpv_format)] = [
            ("dwidth", MPV_FORMAT_INT64),
            ("dheight", MPV_FORMAT_INT64),
            ("duration", MPV_FORMAT_DOUBLE),
            ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG),
            ("track-list", MPV_FORMAT_NODE)
        ]
        
        for (name, format) in properties {
            _ = name.withCString { namePtr in
                mpv_observe_property(handle, 0, namePtr, format)
            }
        }
    }
    
    private func installWakeupHandler() {
        guard let handle = mpv else { return }
        
        mpv_set_wakeup_callback(
            handle,
            { userdata in
                guard let userdata else { return }
                let renderer = Unmanaged<MPVRenderer>
                    .fromOpaque(userdata)
                    .takeUnretainedValue()
                renderer.processEvents()
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
    
    private func configureGPUVideoOutput() throws {
        guard let handle = mpv, let metalLayer else {
            throw RendererError.mpvInitialization(-1)
        }
        
        var layer = metalLayer
        let widStatus: Int32 = withUnsafeMutablePointer(to: &layer) { ptr in
            mpv_set_option(handle, "wid", MPV_FORMAT_INT64, ptr)
        }
        guard widStatus >= 0 else {
            throw RendererError.mpvInitialization(widStatus)
        }
        
        let voStatus = setOptionResult(name: "vo", value: "gpu-next")
        guard voStatus >= 0 else { throw RendererError.mpvInitialization(voStatus) }
        guard setOptionResult(name: "gpu-api", value: "vulkan") >= 0 else {
            throw RendererError.mpvInitialization(-1)
        }
        guard setOptionResult(name: "gpu-context", value: "moltenvk") >= 0 else {
            throw RendererError.mpvInitialization(-1)
        }
    }
    
    @discardableResult
    private func setOptionResult(name: String, value: String) -> Int32 {
        guard let handle = mpv else { return -1 }
        return value.withCString { vp in
            name.withCString { np in mpv_set_option_string(handle, np, vp) }
        }
    }
    
    private func renderQueueSync(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: renderQueueKey) != nil { block() }
        else { renderQueue.sync(execute: block) }
    }
    
    private func dispatchToMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
    
    private func updateVideoSize(width: Int, height: Int) {
        _videoSize = CGSize(width: max(width, 0), height: max(height, 0))
    }
    
    private func layerResize() {
        refit?.cancel()
        let videoR = DispatchWorkItem { [weak self] in self?.placeOutput() }
        refit = videoR
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: videoR)
    }
    
    private func placeOutput() {
        guard !isStopping, let handle = mpv, let layer = metalLayer else { return }
        var w: Int64 = 0, h: Int64 = 0, aspect: Double = 0
        guard getProperty(handle: handle, name: "osd-dimensions/w", format: MPV_FORMAT_INT64, value: &w) >= 0,
              getProperty(handle: handle, name: "osd-dimensions/h", format: MPV_FORMAT_INT64, value: &h) >= 0,
              getProperty(handle: handle, name: "video-params/aspect", format: MPV_FORMAT_DOUBLE, value: &aspect) >= 0,
              w > 0, h > 0, aspect > 0 else { return }
        let target = layer.drawableSize
        guard abs(Double(w) - Double(target.width)) > 2 || abs(Double(h) - Double(target.height)) > 2 else { return }
        size.toggle()
        setProperty(name: "video-aspect-override", value: size ? String(aspect * (1 + 1e-6)) : "no")
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
        renderQueue.async { [weak self] in
            guard let self, !self.eventLoopRunning, !self.isStopping else { return }
            self.eventLoopRunning = true
            
            self.eventQueue.async(group: self.eventQueueGroup) { [weak self] in
                guard let self else { return }
                defer {
                    self.eventLoopRunning = false
                }
                
                while !self.isStopping {
                    guard let handle = self.mpv else { break }
                    guard let evPtr = mpv_wait_event(handle, -1) else { break }
                    let ev = evPtr.pointee
                    if ev.event_id == MPV_EVENT_NONE { continue }
                    self.handleEvent(ev)
                    if ev.event_id == MPV_EVENT_SHUTDOWN { break }
                }
            }
        }
    }
    
    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_VIDEO_RECONFIG:
            refreshVideoState()
        case MPV_EVENT_FILE_LOADED:
            setIsLoading(false)
            let (subs, audio) = fetchTracks()
            dispatchToMain { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: false)
                self.delegate?.renderer(self, didUpdateSubtitleTracks: subs)
                self.delegate?.renderer(self, didUpdateAudioTracks: audio)
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
                let last = stateQueue.sync { lastReportedPosition }
                let nearEnd = dur > 0 && dur - v < 1
                guard Int(v.rounded(.down)) != Int(last.rounded(.down)) || nearEnd else { return }
                stateQueue.async(flags: .barrier) { self.lastReportedPosition = v }
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
        case "track-list":
            let (subs, audio) = fetchTracks()
            dispatchToMain { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didUpdateSubtitleTracks: subs)
                self.delegate?.renderer(self, didUpdateAudioTracks: audio)
            }
        default:
            break
        }
    }
    
    private func fetchTracks() -> (subs: [SubtitleTrackInfo], audio: [AudioTrackInfo]) {
        guard let handle = mpv else { return ([], []) }
        var node = mpv_node()
        let status = "track-list".withCString { namePtr in
            mpv_get_property(handle, namePtr, MPV_FORMAT_NODE, &node)
        }
        guard status >= 0 else { return ([], []) }
        defer { mpv_free_node_contents(&node) }
        
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list else { return ([], []) }
        
        var subs: [SubtitleTrackInfo] = []
        var audio: [AudioTrackInfo] = []
        let count = Int(list.pointee.num)
        for i in 0..<count {
            let entry = nodeMapToDict(list.pointee.values[i])
            guard let rawID = entry["id"] as? Int64 else { continue }
            
            let id = Int(rawID)
            let title = entry["title"] as? String
            let lang = entry["lang"] as? String
            let codec = entry["codec"] as? String
            let isExternal = (entry["external"] as? Bool) ?? false
            let isSelected = (entry["selected"] as? Bool) ?? false
            
            switch entry["type"] as? String {
            case "sub":
                subs.append(SubtitleTrackInfo(id: id, title: title, lang: lang, codec: codec, isExternal: isExternal, isSelected: isSelected))
            case "audio":
                audio.append(AudioTrackInfo(id: id, title: title, lang: lang, codec: codec, isExternal: isExternal, isSelected: isSelected))
            default:
                break
            }
        }
        return (subs, audio)
    }
    
    private func nodeMapToDict(_ node: mpv_node) -> [String: Any] {
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list else { return [:] }
        var result: [String: Any] = [:]
        let count = Int(list.pointee.num)
        for i in 0..<count {
            guard let keyPtr = list.pointee.keys[i] else { continue }
            let key = String(cString: keyPtr)
            let value = list.pointee.values[i]
            switch value.format {
            case MPV_FORMAT_STRING:
                if let s = value.u.string { result[key] = String(cString: s) }
            case MPV_FORMAT_INT64:
                result[key] = value.u.int64
            case MPV_FORMAT_FLAG:
                result[key] = value.u.flag != 0
            case MPV_FORMAT_DOUBLE:
                result[key] = value.u.double_
            default:
                break
            }
        }
        return result
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
    
    func play() {
        setProperty(name: "pause", value: "no")
    }
    
    func pausePlayback() {
        setProperty(name: "pause", value: "yes")
    }
    
    private func resetPositionThrottle() {
        stateQueue.async(flags: .barrier) { self.lastReportedPosition = -1 }
    }
    
    func seek(to seconds: Double) {
        resetPositionThrottle()
        guard let handle = mpv else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.command(handle, ["seek", String(max(0, seconds)), "absolute"])
        }
    }
    
    func seek(by seconds: Double) {
        resetPositionThrottle()
        guard let handle = mpv else { return }
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.command(handle, ["seek", String(seconds), "relative"])
        }
    }
    
    func setSpeed(_ speed: Double) {
        let clamped = max(0.1, min(speed, 100.0))
        setProperty(name: "speed", value: String(clamped))
    }
    
    func getSpeed() -> Double {
        guard let handle = mpv else { return 1.0 }
        var speed: Double = 1.0
        getProperty(handle: handle, name: "speed", format: MPV_FORMAT_DOUBLE, value: &speed)
        return speed
    }
    
    func setSubtitleVisible(_ visible: Bool) {
        setProperty(name: "sub-visibility", value: visible ? "yes" : "no")
    }
    
    func selectSubtitleTrack(id: Int) {
        setProperty(name: "sid", value: String(id))
    }
    
    func disableSubtitleTrack() {
        setProperty(name: "sid", value: "no")
    }
    
    func selectAudioTrack(id: Int) {
        setProperty(name: "aid", value: String(id))
    }
    
    func disableAudioTrack() {
        setProperty(name: "aid", value: "no")
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

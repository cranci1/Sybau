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
    func renderer(_ renderer: MPVRenderer, didFailWith message: String)
}

extension MPVRendererDelegate {
    func renderer(_ renderer: MPVRenderer, didFailWith message: String) {}
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
    
    private let coreQueue = DispatchQueue(label: "mpv.core", qos: .userInitiated)
    private let eventQueue = DispatchQueue(label: "mpv.events", qos: .userInitiated)
    private let coreQueueKey = DispatchSpecificKey<Void>()
    private let eventQueueGroup = DispatchGroup()
    private let stateLock = NSLock()
    
    private var mpv: OpaquePointer?
    private weak var metalLayer: CAMetalLayer?
    private var refit: DispatchWorkItem?
    private var aspectToggle = false
    
    private var _isPaused = true
    private var _isLoading = false
    private var _isRunning = false
    private var _isStopping = false
    private var _cachedPosition: Double = 0
    private var _cachedDuration: Double = 0
    private var _cachedSpeed: Double = 1.0
    private var lastReportedPosition: Double = -1
    private var lastPositionReportTime: CFTimeInterval = 0
    
    weak var delegate: MPVRendererDelegate?
    
    // MARK: - Init / deinit
    
    init(primaryDisplayLayer: CAMetalLayer) {
        self.metalLayer = primaryDisplayLayer
        coreQueue.setSpecific(key: coreQueueKey, value: ())
    }
    
    deinit { stop() }
    
    var isPausedState: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isPaused
    }
    
    var isLoadingState: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isLoading
    }
    
    var isRunningState: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRunning
    }
    
    private func setIsPaused(_ value: Bool) {
        stateLock.lock()
        _isPaused = value
        stateLock.unlock()
    }
    
    private func setIsLoading(_ value: Bool) {
        stateLock.lock()
        _isLoading = value
        stateLock.unlock()
    }
    
    private func setCachedPosition(_ position: Double, duration: Double? = nil) {
        stateLock.lock()
        _cachedPosition = max(0, position)
        if let duration { _cachedDuration = max(0, duration) }
        stateLock.unlock()
    }
    
    private func setCachedSpeed(_ speed: Double) {
        stateLock.lock()
        _cachedSpeed = speed
        stateLock.unlock()
    }
    
    private func cachedPlaybackState() -> (position: Double, duration: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (_cachedPosition, _cachedDuration)
    }
    
    private func resetPositionThrottle() {
        stateLock.lock()
        lastReportedPosition = -1
        lastPositionReportTime = 0
        stateLock.unlock()
    }
    
    // MARK: - Lifecycle
    
    func start() throws {
        try performOnCore {
            guard !isRunningState else { return }
            guard metalLayer != nil else {
                throw RendererError.mpvInitialization(-1)
            }
            
            guard let handle = mpv_create() else {
                throw RendererError.mpvCreationFailed
            }
            mpv = handle
            
            configureOptions(handle)
            
            let initStatus = mpv_initialize(handle)
            guard initStatus >= 0 else {
                mpv_destroy(handle)
                mpv = nil
                throw RendererError.mpvInitialization(initStatus)
            }
            
            requestLogMessages(handle)
            observeProperties(handle)
            
            stateLock.lock()
            _isRunning = true
            _isStopping = false
            stateLock.unlock()
            
            (metalLayer as? MetalLayer)?.onResize = { [weak self] in
                DispatchQueue.main.async { self?.layerResize() }
            }
            
            startEventLoop(handle: handle)
        }
        
        DispatchQueue.main.async { [weak self] in self?.layerResize() }
    }
    
    func stop() {
        stateLock.lock()
        guard _isRunning, !_isStopping else {
            stateLock.unlock()
            return
        }
        _isRunning = false
        _isStopping = true
        stateLock.unlock()
        
        refit?.cancel()
        refit = nil
        (metalLayer as? MetalLayer)?.onResize = nil
        
        performOnCore {
            guard let handle = mpv else { return }
            commandSync(handle, ["quit"])
            mpv_wakeup(handle)
        }
        
        let waitResult = eventQueueGroup.wait(timeout: .now() + 1.5)
        
        performOnCore {
            guard let handle = mpv else { return }
            if waitResult == .success {
                mpv_destroy(handle)
            }
            mpv = nil
        }
        
        if waitResult == .timedOut {
            Logger.shared.log("mpv event loop did not shut down within timeout", type: "Error")
        }
        
        stateLock.lock()
        _isStopping = false
        _isPaused = true
        _isLoading = false
        stateLock.unlock()
    }
    
    private func startEventLoop(handle: OpaquePointer) {
        eventQueue.async(group: eventQueueGroup) { [weak self] in
            while true {
                var stopping = true
                if let self {
                    self.stateLock.lock()
                    stopping = self._isStopping
                    self.stateLock.unlock()
                } else {
                    break
                }
                if stopping { break }
                
                guard let eventPointer = mpv_wait_event(handle, -1) else { break }
                let event = eventPointer.pointee
                if event.event_id == MPV_EVENT_NONE { continue }
                
                guard let self else { break }
                self.handleEvent(event)
                if event.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }
    
    // MARK: - Load
    
    func load(url: URL, with preset: PlayerPreset, headers: [String: String]? = nil) {
        resetPositionThrottle()
        setIsLoading(true)
        notifyMain(didChangeLoading: true)
        
        performOnCoreAsync { [weak self] in
            guard let self, let handle = self.mpv else {
                self?.setIsLoading(false)
                self?.notifyMain(didChangeLoading: false)
                return
            }
            
            self.apply(commands: preset.commands, on: handle)
            self.updateHTTPHeaders(headers, on: handle)
            self.setPropertySync(handle, name: "pause", value: "no")
            
            let target = url.isFileURL ? url.path : url.absoluteString
            self.commandSync(handle, ["loadfile", target, "replace"])
        }
    }
    
    func applyPreset(_ preset: PlayerPreset) {
        performOnCoreAsync { [weak self] in
            guard let self, let handle = self.mpv else { return }
            self.apply(commands: preset.commands, on: handle)
        }
    }
    
    // MARK: - Options / properties
    
    private func configureOptions(_ handle: OpaquePointer) {
        setOption(handle, name: "profile", value: "fast")
        setOption(handle, name: "hwdec", value: "videotoolbox,videotoolbox-copy")
        
        setOption(handle, name: "idle", value: "yes")
        setOption(handle, name: "keep-open", value: "yes")
        setOption(handle, name: "hr-seek", value: "yes")
        setOption(handle, name: "video-sync", value: "audio")
        setOption(handle, name: "interpolation", value: "no")
        setOption(handle, name: "demuxer-thread", value: "yes")
        setOption(handle, name: "audio-normalize-downmix", value: "yes")
        setOption(handle, name: "audio-client-name", value: "Sybau")
        
        setOption(handle, name: "sub-ass", value: "yes")
        setOption(handle, name: "subs-fallback", value: "yes")
        setOption(handle, name: "sub-ass-override", value: "yes")
        
        setOption(handle, name: "vd-lavc-dr", value: "yes")
        setOption(handle, name: "vd-lavc-threads", value: "auto")
        
        setOption(handle, name: "cache", value: "yes")
        setOption(handle, name: "cache-secs", value: "60")
        setOption(handle, name: "cache-initial", value: "100")
        setOption(handle, name: "demuxer-max-bytes", value: "64M")
        setOption(handle, name: "demuxer-readahead-secs", value: "10")
        setOption(handle, name: "network-timeout", value: "20")
        
        setOption(handle, name: "terminal", value: "no")
        setOption(handle, name: "osc", value: "no")
        setOption(handle, name: "input-default-bindings", value: "no")
        setOption(handle, name: "input-vo-keyboard", value: "no")
        
        configureGPUVideoOutput(handle)
    }
    
    private func configureGPUVideoOutput(_ handle: OpaquePointer) {
        guard let metalLayer else { return }
        
        var layer = metalLayer
        let widStatus: Int32 = withUnsafeMutablePointer(to: &layer) { pointer in
            mpv_set_option(handle, "wid", MPV_FORMAT_INT64, pointer)
        }
        if widStatus < 0 {
            Logger.shared.log("Failed to set wid (\(widStatus))", type: "Error")
        }
        
        setOption(handle, name: "vo", value: "gpu-next")
        setOption(handle, name: "gpu-api", value: "vulkan")
        setOption(handle, name: "gpu-context", value: "moltenvk")
    }
    
    private func setOption(_ handle: OpaquePointer, name: String, value: String) {
        let status = value.withCString { valuePointer in
            name.withCString { namePointer in
                mpv_set_option_string(handle, namePointer, valuePointer)
            }
        }
        if status < 0 {
            Logger.shared.log("Failed to set option \(name)=\(value) (\(status))", type: "Warn")
        }
    }
    
    @discardableResult
    private func setPropertySync(_ handle: OpaquePointer, name: String, value: String) -> Int32 {
        let status = value.withCString { valuePointer in
            name.withCString { namePointer in
                mpv_set_property_string(handle, namePointer, valuePointer)
            }
        }
        if status < 0 {
            Logger.shared.log("Failed to set \(name)=\(value) (\(status))", type: "Warn")
        }
        return status
    }
    
    @discardableResult
    private func setProperty(name: String, value: String) -> Int32 {
        performOnCore {
            guard let handle = mpv else { return -1 }
            return setPropertySync(handle, name: name, value: value)
        }
    }
    
    private func clearProperty(name: String) {
        performOnCore {
            guard let handle = mpv else { return }
            let status = name.withCString { namePointer in
                mpv_set_property(handle, namePointer, MPV_FORMAT_NONE, nil)
            }
            if status < 0 {
                Logger.shared.log("Failed to clear \(name) (\(status))", type: "Warn")
            }
        }
    }
    
    private func updateHTTPHeaders(_ headers: [String: String]?, on handle: OpaquePointer) {
        guard let headers, !headers.isEmpty else {
            let status = "http-header-fields".withCString { namePointer in
                mpv_set_property(handle, namePointer, MPV_FORMAT_NONE, nil)
            }
            if status < 0 {
                Logger.shared.log("Failed to clear http-header-fields (\(status))", type: "Warn")
            }
            return
        }
        let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        setPropertySync(handle, name: "http-header-fields", value: headerString)
    }
    
    private func requestLogMessages(_ handle: OpaquePointer) {
        _ = "warn".withCString { level in
            mpv_request_log_messages(handle, level)
        }
    }
    
    private func observeProperties(_ handle: OpaquePointer) {
        let properties: [(String, mpv_format)] = [
            ("duration", MPV_FORMAT_DOUBLE),
            ("time-pos", MPV_FORMAT_DOUBLE),
            ("pause", MPV_FORMAT_FLAG),
            ("speed", MPV_FORMAT_DOUBLE),
            ("track-list", MPV_FORMAT_NODE)
        ]
        
        for (name, format) in properties {
            _ = name.withCString { namePointer in
                mpv_observe_property(handle, 0, namePointer, format)
            }
        }
    }
    
    // MARK: - Video placement
    
    private func layerResize() {
        refit?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.placeOutput() }
        refit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
    
    private func placeOutput() {
        guard let layer = metalLayer else { return }
        let target = layer.drawableSize
        guard target.width > 1, target.height > 1 else { return }
        
        performOnCore {
            guard let handle = mpv else { return }
            var width: Int64 = 0
            var height: Int64 = 0
            var aspect: Double = 0
            guard getProperty(handle: handle, name: "osd-dimensions/w", format: MPV_FORMAT_INT64, value: &width) >= 0,
                  getProperty(handle: handle, name: "osd-dimensions/h", format: MPV_FORMAT_INT64, value: &height) >= 0,
                  getProperty(handle: handle, name: "video-params/aspect", format: MPV_FORMAT_DOUBLE, value: &aspect) >= 0,
                  width > 0, height > 0, aspect > 0 else { return }
            
            guard abs(Double(width) - Double(target.width)) > 2 || abs(Double(height) - Double(target.height)) > 2 else { return }
            
            aspectToggle.toggle()
            setPropertySync(handle, name: "video-aspect-override", value: aspectToggle ? String(aspect * (1 + 1e-6)) : "no")
        }
    }
    
    // MARK: - Event handling
    
    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_VIDEO_RECONFIG:
            DispatchQueue.main.async { [weak self] in self?.layerResize() }
            
        case MPV_EVENT_FILE_LOADED:
            setIsLoading(false)
            resetPositionThrottle()
            let (subtitles, audio) = fetchTracks()
            notifyMain { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangeLoading: false)
                self.delegate?.renderer(self, didUpdateSubtitleTracks: subtitles)
                self.delegate?.renderer(self, didUpdateAudioTracks: audio)
                self.delegate?.renderer(self, didBecomeReadyToSeek: true)
            }
            
        case MPV_EVENT_END_FILE:
            if let endFile = event.data?.assumingMemoryBound(to: mpv_event_end_file.self) {
                handleEndFile(reason: endFile.pointee.reason, error: endFile.pointee.error)
            }
            
        case MPV_EVENT_PROPERTY_CHANGE:
            if let namePointer = event.data?
                .assumingMemoryBound(to: mpv_event_property.self).pointee.name {
                refreshProperty(named: String(cString: namePointer))
            }
            
        case MPV_EVENT_LOG_MESSAGE:
            if let logMessage = event.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                let component = String(cString: logMessage.pointee.prefix)
                let level = String(cString: logMessage.pointee.level)
                let text = String(cString: logMessage.pointee.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { break }
                
                switch level {
                case "error", "fatal":
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Error")
                case "warn":
                    Logger.shared.log("mpv[\(component)] \(text)", type: "Warn")
                default:
                    break
                }
            }
            
        case MPV_EVENT_SHUTDOWN:
            Logger.shared.log("mpv shutdown", type: "Warn")
            
        default:
            break
        }
    }
    
    private func handleEndFile(reason: mpv_end_file_reason, error: Int32) {
        guard reason == MPV_END_FILE_REASON_ERROR else { return }
        
        let errorString = String(cString: mpv_error_string(error))
        Logger.shared.log("Playback failed: \(errorString)", type: "Error")
        setIsLoading(false)
        notifyMain { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: false)
            self.delegate?.renderer(self, didFailWith: errorString)
        }
    }
    
    private func refreshProperty(named name: String) {
        guard let handle = mpv else { return }
        
        switch name {
        case "duration":
            var value = Double(0)
            guard getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0,
                  value.isFinite else { return }
            let position = cachedPlaybackState().position
            setCachedPosition(position, duration: value)
            notifyMain { [weak self] in
                guard let self else { return }
                let state = self.cachedPlaybackState()
                self.delegate?.renderer(self, didUpdatePosition: state.position, duration: state.duration)
            }
            
        case "time-pos":
            var value = Double(0)
            guard getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0,
                  value.isFinite else { return }
            
            let state = cachedPlaybackState()
            let now = CACurrentMediaTime()
            
            stateLock.lock()
            let shouldReport = lastReportedPosition < 0
            || abs(value - lastReportedPosition) >= 1.0
            || now - lastPositionReportTime >= 0.2
            if shouldReport {
                lastReportedPosition = value
                lastPositionReportTime = now
            }
            stateLock.unlock()
            
            guard shouldReport else { return }
            setCachedPosition(value, duration: state.duration)
            
            notifyMain { [weak self] in
                guard let self else { return }
                let current = self.cachedPlaybackState()
                self.delegate?.renderer(self, didUpdatePosition: current.position, duration: current.duration)
            }
            
        case "pause":
            var flag: Int32 = 0
            guard getProperty(handle: handle, name: name, format: MPV_FORMAT_FLAG, value: &flag) >= 0 else { return }
            let newPaused = flag != 0
            guard newPaused != isPausedState else { return }
            setIsPaused(newPaused)
            notifyMain { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didChangePause: newPaused)
            }
            
        case "speed":
            var value = Double(1)
            if getProperty(handle: handle, name: name, format: MPV_FORMAT_DOUBLE, value: &value) >= 0 {
                setCachedSpeed(value)
            }
            
        case "track-list":
            let (subtitles, audio) = fetchTracks()
            notifyMain { [weak self] in
                guard let self else { return }
                self.delegate?.renderer(self, didUpdateSubtitleTracks: subtitles)
                self.delegate?.renderer(self, didUpdateAudioTracks: audio)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Tracks
    
    private func fetchTracks() -> (subtitles: [SubtitleTrackInfo], audio: [AudioTrackInfo]) {
        guard let handle = mpv else { return ([], []) }
        var node = mpv_node()
        let status = "track-list".withCString { namePointer in
            mpv_get_property(handle, namePointer, MPV_FORMAT_NODE, &node)
        }
        guard status >= 0 else { return ([], []) }
        defer { mpv_free_node_contents(&node) }
        
        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list else { return ([], []) }
        
        var subtitles: [SubtitleTrackInfo] = []
        var audio: [AudioTrackInfo] = []
        let count = Int(list.pointee.num)
        for index in 0..<count {
            let entry = nodeMapToDict(list.pointee.values[index])
            guard let rawID = entry["id"] as? Int64 else { continue }
            if (entry["albumart"] as? Bool) == true { continue }
            
            let id = Int(rawID)
            let title = entry["title"] as? String
            let lang = entry["lang"] as? String
            let codec = entry["codec"] as? String
            let isExternal = (entry["external"] as? Bool) ?? false
            let isSelected = (entry["selected"] as? Bool) ?? false
            
            switch entry["type"] as? String {
            case "sub":
                subtitles.append(SubtitleTrackInfo(
                    id: id, title: title, lang: lang, codec: codec,
                    isExternal: isExternal, isSelected: isSelected
                ))
            case "audio":
                audio.append(AudioTrackInfo(
                    id: id, title: title, lang: lang, codec: codec,
                    isExternal: isExternal, isSelected: isSelected
                ))
            default:
                break
            }
        }
        return (subtitles, audio)
    }
    
    private func nodeMapToDict(_ node: mpv_node) -> [String: Any] {
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list else { return [:] }
        var result: [String: Any] = [:]
        let count = Int(list.pointee.num)
        for index in 0..<count {
            guard let keyPointer = list.pointee.keys[index] else { continue }
            let key = String(cString: keyPointer)
            let value = list.pointee.values[index]
            switch value.format {
            case MPV_FORMAT_STRING:
                if let string = value.u.string { result[key] = String(cString: string) }
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
        name.withCString { namePointer in
            withUnsafeMutablePointer(to: &value) {
                mpv_get_property(handle, namePointer, format, $0)
            }
        }
    }
    
    private func apply(commands: [[String]], on handle: OpaquePointer) {
        for command in commands where !command.isEmpty {
            commandSync(handle, command)
        }
    }
    
    private func commandSync(_ handle: OpaquePointer, _ args: [String]) {
        guard !args.isEmpty else { return }
        _ = withCStringArray(args) { mpv_command_async(handle, 0, $0) }
    }
    
    private func command(_ args: [String]) {
        guard !args.isEmpty else { return }
        performOnCoreAsync { [weak self] in
            guard let self, let handle = self.mpv else { return }
            self.commandSync(handle, args)
        }
    }
    
    @inline(__always)
    private func withCStringArray<R>(_ args: [String], body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var cStrings = [UnsafeMutablePointer<CChar>?]()
        cStrings.reserveCapacity(args.count + 1)
        for string in args { cStrings.append(strdup(string)) }
        cStrings.append(nil)
        defer { for pointer in cStrings where pointer != nil { free(pointer) } }
        return cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { rebound in
                body(UnsafeMutablePointer(mutating: rebound))
            }
        }
    }
    
    // MARK: - Queue helpers
    
    @discardableResult
    private func performOnCore<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: coreQueueKey) != nil {
            return try block()
        }
        return try coreQueue.sync(execute: block)
    }
    
    private func performOnCoreAsync(_ block: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: coreQueueKey) != nil {
            block()
        } else {
            coreQueue.async(execute: block)
        }
    }
    
    private func notifyMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    private func notifyMain(didChangeLoading isLoading: Bool) {
        notifyMain { [weak self] in
            guard let self else { return }
            self.delegate?.renderer(self, didChangeLoading: isLoading)
        }
    }
    
    // MARK: - Playback controls
    
    func play() {
        setProperty(name: "pause", value: "no")
    }
    
    func pausePlayback() {
        setProperty(name: "pause", value: "yes")
    }
    
    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        resetPositionThrottle()
        command(["seek", String(max(0, seconds)), "absolute"])
    }
    
    func seek(by seconds: Double) {
        guard seconds.isFinite else { return }
        resetPositionThrottle()
        command(["seek", String(seconds), "relative"])
    }
    
    func setSpeed(_ speed: Double) {
        let clamped = max(0.1, min(speed, 100.0))
        setCachedSpeed(clamped)
        setProperty(name: "speed", value: String(clamped))
    }
    
    func getSpeed() -> Double {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _cachedSpeed
    }
    
    // MARK: - Subtitles
    
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
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        
        let filePath: String
        switch url.scheme?.lowercased() {
        case "http", "https":
            filePath = url.absoluteString
        case "file":
            guard url.isFileURL else {
                Logger.shared.log("Rejected subtitle URL: \(urlString)", type: "Warn")
                return
            }
            filePath = url.path
        default:
            Logger.shared.log("Rejected subtitle URL with unsupported scheme: \(urlString)", type: "Warn")
            return
        }
        
        command(["sub-add", filePath, "select"])
    }
    
    func clearCurrentSubtitleTrack() {
        command(["sub-remove"])
    }
    
    func applySubtitleStyle(_ style: SubtitleStyle) {
        performOnCore {
            guard let handle = mpv else { return }
            setPropertySync(handle, name: "sub-font-size", value: String(format: "%.2f", style.fontSize))
            setPropertySync(handle, name: "sub-color", value: style.foregroundColor.mpvColorString)
            setPropertySync(handle, name: "sub-border-color", value: style.strokeColor.mpvColorString)
            setPropertySync(handle, name: "sub-border-size", value: String(format: "%.2f", max(style.strokeWidth, 0)))
        }
    }
    
    // MARK: - Volume
    
    func setVolume(_ volume: Float) {
        let clamped = max(0, min(volume, 1))
        setProperty(name: "volume", value: String(Int((clamped * 100).rounded())))
    }
}

private extension UIColor {
    var mpvColorString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%.3f/%.3f/%.3f/%.3f", red, green, blue, alpha)
    }
}

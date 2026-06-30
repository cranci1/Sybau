//
//  PlayerViewController.swift
//  Sybau
//

import UIKit
import SwiftUI
import AVFoundation
#if os(tvOS)
import TVUIKit
#endif

public final class PlayerViewController: UIViewController {
    // MARK: - Video surface
    
    private let videoContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .black
        v.clipsToBounds = true
        return v
    }()
    
    private let primaryRenderView: VideoDisplayView = {
        let v = VideoDisplayView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private let displayLayer = AVSampleBufferDisplayLayer()
    
    // MARK: - Controls
    
    private let centerPlayPauseButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        b.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.layer.cornerRadius = 36
        b.layer.cornerCurve = .continuous
        b.clipsToBounds = true
        return b
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .large)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.hidesWhenStopped = true
        v.color = .white
        v.alpha = 0.0
        return v
    }()
    
    private let controlsOverlayView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        v.alpha = 0.0
        v.isUserInteractionEnabled = false
        return v
    }()
    
    private lazy var errorBanner: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 0.95)
            : UIColor(red: 0.90, green: 0.17, blue: 0.17, alpha: 0.98)
        }
        container.layer.cornerRadius = 10
        container.clipsToBounds = true
        container.alpha = 0.0
        
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.numberOfLines = 2
        label.tag = 101
        
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("View Logs", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        btn.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        btn.layer.cornerRadius = 6
        
        if #available(iOS 15.0, tvOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            btn.configuration = config
        }
        btn.addTarget(self, action: #selector(viewLogsTapped), for: .touchUpInside)
        
        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(btn)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            
            btn.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            btn.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }()
    
    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let pipButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        b.setImage(UIImage(systemName: "pip.enter", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let skipBackwardButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        b.setImage(UIImage(systemName: "gobackward", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let skipForwardButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        b.setImage(UIImage(systemName: "goforward", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        return b
    }()
    
    private let speedIndicatorLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.textColor = .white
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textAlignment = .center
        l.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
        l.layer.cornerRadius = 20
        l.clipsToBounds = true
        l.alpha = 0.0
        return l
    }()
    
    private let subtitleButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        b.setImage(UIImage(systemName: "captions.bubble", withConfiguration: cfg), for: .normal)
        b.tintColor = .white
        b.alpha = 0.0
        b.isHidden = true
        b.showsMenuAsPrimaryAction = true
        return b
    }()
    
    private let skipSegmentButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setTitle("Skip", for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = UIColor(white: 0.2, alpha: 0.55)
        b.layer.cornerRadius = 18
        b.layer.cornerCurve = .continuous
        
        if #available(iOS 15.0, tvOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            b.configuration = config
        }
        b.alpha = 0.0
        b.isHidden = true
        return b
    }()
    
    private let progressContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()
    
    private var progressHostingController: UIHostingController<AnyView>?
    private var lastHostedDuration: Double = 0
    
    class ProgressModel: ObservableObject {
        @Published var position: Double = 0
        @Published var duration: Double = 1
        @Published var highlights: [ProgressHighlight] = []
    }
    private var progressModel = ProgressModel()
    
    // MARK: - Renderer & state
    
    private lazy var renderer: MPVRenderer = {
        let r = MPVRenderer(primaryDisplayLayer: primaryRenderView.displayLayer, pipDisplayLayer: displayLayer)
        r.delegate = self
        return r
    }()
    
    private var initialURL: URL?
    private var isSeeking = false
    public var mediaInfo: MediaInfo?
    private var cachedDuration: Double = 0
    private var cachedPosition: Double = 0
    private var initialSubtitles: [String]?
    private var initialPreset: PlayerPreset?
    private var pipController: PiPController?
    private var initialHeaders: [String: String]?
    
    private var subtitleURLs: [String] = []
    private var currentSubtitleIndex: Int = 0
    private var pendingSubtitleURLs: [String]?
    private var lastUIUpdateTime: TimeInterval = 0
    
    private var originalSpeed: Double = 1.0
    private var holdGesture: UILongPressGestureRecognizer?
    private var controlsHideWorkItem: DispatchWorkItem?
    private var controlsVisible = true
    private var pendingSeekTime: Double?
    private var introDBSegments: [IntroDBSegment] = []
    private var activeSkipSegmentID: String?
#if !os(tvOS)
    private let holdHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let skipHaptic = UIImpactFeedbackGenerator(style: .light)
#endif
    
    // MARK: - View lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
#if !os(tvOS)
        modalPresentationCapturesStatusBarAppearance = true
        holdHaptic.prepare()
        skipHaptic.prepare()
#endif
        setupLayout()
        setupActions()
        setupHoldGesture()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleLoggerNotification(_:)), name: NSNotification.Name("LoggerNotification"), object: nil)
        
        do {
            try renderer.start()
        } catch {
            Logger.shared.log("Failed to start MPV renderer: \(error)", type: "Error")
            presentStartupErrorAlert(message: "Failed to start renderer: \(error)")
        }
        
        pipController = PiPController(sampleBufferDisplayLayer: displayLayer)
        pipController?.delegate = self
        
        showControlsTemporarily()
        
        if let url = initialURL, let preset = initialPreset {
            load(url: url, preset: preset, headers: initialHeaders)
        }
        
        installProgressHostingControllerIfNeeded()
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        
        subscribeToSubtitleSettings()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.bringSubviewToFront(errorBanner)
    }
    
#if !os(tvOS)
    public override var prefersStatusBarHidden: Bool { true }
    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UserDefaults.standard.bool(forKey: "alwaysLandscape") ? .landscape : .all
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }
#endif
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryRenderView.frame = videoContainer.bounds
        primaryRenderView.layoutIfNeeded()
        
        if let grad = controlsOverlayView.layer.sublayers?
            .first(where: { $0.name == "gradientLayer" }) {
            grad.frame = controlsOverlayView.bounds
        }
        CATransaction.commit()
    }
    
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] context in
            guard let self else { return }
            let prev = self.primaryRenderView.transform
            self.primaryRenderView.transform = prev.scaledBy(x: 0.985, y: 0.985)
            UIView.animateKeyframes(
                withDuration: context.transitionDuration, delay: 0,
                options: [.beginFromCurrentState, .calculationModeCubic, .allowUserInteraction]
            ) {
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.75) {
                    self.videoContainer.layoutIfNeeded()
                    self.primaryRenderView.layoutIfNeeded()
                }
                UIView.addKeyframe(withRelativeStartTime: 0.2, relativeDuration: 0.8) {
                    self.primaryRenderView.transform = prev
                }
            }
        }, completion: { [weak self] _ in
            self?.primaryRenderView.transform = .identity
        })
    }
    
    deinit {
        renderer.stop()
        displayLayer.removeFromSuperlayer()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public init
    
    public convenience init(url: URL, preset: PlayerPreset, headers: [String: String]? = nil, subtitles: [String]? = nil) {
        self.init(nibName: nil, bundle: nil)
        self.initialURL = url
        self.initialPreset = preset
        self.initialHeaders = headers
        self.initialSubtitles = subtitles
    }
    
    // MARK: - Load
    
    func load(url: URL, preset: PlayerPreset, headers: [String: String]? = nil) {
        renderer.load(url: url, with: preset, headers: headers)
        if let info = mediaInfo {
            prepareSeekToLastPosition(for: info)
            fetchIntroDBSegments(for: info)
        }
        if let subs = initialSubtitles, !subs.isEmpty {
            pendingSubtitleURLs = subs
        }
    }
    
    private func prepareSeekToLastPosition(for info: MediaInfo) {
        let lastPlayedTime: Double
        switch info {
        case .movie(let id, let title):
            lastPlayedTime = ProgressManager.shared.getMovieCurrentTime(movieId: id, title: title)
        case .episode(let showId, _, let season, let episode):
            lastPlayedTime = ProgressManager.shared.getEpisodeCurrentTime(showId: showId, seasonNumber: season, episodeNumber: episode)
        }
        guard lastPlayedTime != 0 else { return }
        
        let progress: Double
        switch info {
        case .movie(let id, let title):
            progress = ProgressManager.shared.getMovieProgress(movieId: id, title: title)
        case .episode(let showId, _, let season, let episode):
            progress = ProgressManager.shared.getEpisodeProgress(showId: showId, seasonNumber: season, episodeNumber: episode)
        }
        
        if progress < 0.95 { pendingSeekTime = lastPlayedTime }
    }
    
    // MARK: - Layout
    
    private func setupLayout() {
        view.addSubview(videoContainer)
        videoContainer.addSubview(primaryRenderView)
        
        displayLayer.frame = videoContainer.bounds
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        videoContainer.layer.addSublayer(displayLayer)
        
        view.addSubview(errorBanner)
        videoContainer.addSubview(controlsOverlayView)
        videoContainer.addSubview(loadingIndicator)
        videoContainer.addSubview(centerPlayPauseButton)
        videoContainer.addSubview(progressContainer)
        videoContainer.addSubview(closeButton)
        videoContainer.addSubview(pipButton)
        videoContainer.addSubview(skipBackwardButton)
        videoContainer.addSubview(skipForwardButton)
        videoContainer.addSubview(speedIndicatorLabel)
        videoContainer.addSubview(subtitleButton)
        videoContainer.addSubview(skipSegmentButton)
        
        NSLayoutConstraint.activate([
            videoContainer.topAnchor.constraint(equalTo: view.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            primaryRenderView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            primaryRenderView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            primaryRenderView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            primaryRenderView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            
            progressContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            progressContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            progressContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            progressContainer.heightAnchor.constraint(equalToConstant: 28),
            
            controlsOverlayView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            controlsOverlayView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            controlsOverlayView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            controlsOverlayView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            
            errorBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            errorBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorBanner.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.92),
            errorBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            
            centerPlayPauseButton.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            centerPlayPauseButton.centerYAnchor.constraint(equalTo: videoContainer.centerYAnchor),
            centerPlayPauseButton.widthAnchor.constraint(equalToConstant: 70),
            centerPlayPauseButton.heightAnchor.constraint(equalToConstant: 70),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: centerPlayPauseButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerPlayPauseButton.centerYAnchor),
            
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor, constant: 4),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            
            pipButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            pipButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 16),
            pipButton.widthAnchor.constraint(equalToConstant: 36),
            pipButton.heightAnchor.constraint(equalToConstant: 36),
            
            skipBackwardButton.centerYAnchor.constraint(equalTo: centerPlayPauseButton.centerYAnchor),
            skipBackwardButton.trailingAnchor.constraint(equalTo: centerPlayPauseButton.leadingAnchor, constant: -48),
            skipBackwardButton.widthAnchor.constraint(equalToConstant: 50),
            skipBackwardButton.heightAnchor.constraint(equalToConstant: 50),
            
            skipForwardButton.centerYAnchor.constraint(equalTo: centerPlayPauseButton.centerYAnchor),
            skipForwardButton.leadingAnchor.constraint(equalTo: centerPlayPauseButton.trailingAnchor, constant: 48),
            skipForwardButton.widthAnchor.constraint(equalToConstant: 50),
            skipForwardButton.heightAnchor.constraint(equalToConstant: 50),
            
            speedIndicatorLabel.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 20),
            speedIndicatorLabel.centerXAnchor.constraint(equalTo: videoContainer.centerXAnchor),
            speedIndicatorLabel.widthAnchor.constraint(equalToConstant: 100),
            speedIndicatorLabel.heightAnchor.constraint(equalToConstant: 40),
            
            skipSegmentButton.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
            skipSegmentButton.bottomAnchor.constraint(equalTo: progressContainer.topAnchor, constant: -14),
            skipSegmentButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            
            subtitleButton.trailingAnchor.constraint(equalTo: skipSegmentButton.leadingAnchor, constant: -8),
            subtitleButton.centerYAnchor.constraint(equalTo: skipSegmentButton.centerYAnchor),
            subtitleButton.widthAnchor.constraint(equalToConstant: 32),
            subtitleButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }
    
    private func setupActions() {
        centerPlayPauseButton.addTarget(self, action: #selector(centerPlayPauseTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)
        skipBackwardButton.addTarget(self, action: #selector(skipBackwardTapped), for: .touchUpInside)
        skipForwardButton.addTarget(self, action: #selector(skipForwardTapped), for: .touchUpInside)
        skipSegmentButton.addTarget(self, action: #selector(skipSegmentTapped), for: .touchUpInside)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(containerTapped))
        videoContainer.addGestureRecognizer(tap)
    }
    
    private func setupHoldGesture() {
        holdGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleHoldGesture(_:)))
        holdGesture?.minimumPressDuration = 0.5
        if let g = holdGesture { videoContainer.addGestureRecognizer(g) }
    }
    
    // MARK: - tvOS Focus
    /// idk if ts works
    
#if os(tvOS)
    public override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard let next = context.nextFocusedView else { return }
        coordinator.addCoordinatedAnimations({
            next.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        }, completion: {})
        if let prev = context.previouslyFocusedView {
            coordinator.addCoordinatedAnimations({
                prev.transform = .identity
            }, completion: {})
        }
    }
    
    public override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [centerPlayPauseButton, skipBackwardButton, skipForwardButton,
         pipButton, closeButton, subtitleButton]
    }
#endif
    
    // MARK: - Hold gesture
    
    @objc private func handleHoldGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:   beginHoldSpeed()
        case .ended, .cancelled: endHoldSpeed()
        default: break
        }
    }
    
    private func beginHoldSpeed() {
        originalSpeed = renderer.getSpeed()
        let pref = UserDefaults.standard.float(forKey: "holdSpeedPlayer")
        let target = pref > 0 ? Double(pref) : 2.0
        renderer.setSpeed(target)
#if !os(tvOS)
        holdHaptic.impactOccurred()
#endif
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.speedIndicatorLabel.text = String(format: "%.1fx", target)
            UIView.animate(withDuration: 0.2) { self.speedIndicatorLabel.alpha = 1.0 }
        }
    }
    
    private func endHoldSpeed() {
        renderer.setSpeed(originalSpeed)
        DispatchQueue.main.async { [weak self] in
            UIView.animate(withDuration: 0.2) { self?.speedIndicatorLabel.alpha = 0.0 }
        }
    }
    
    // MARK: - Playback controls
    
    @objc private func playPauseTapped() {
        if renderer.isPausedState {
            renderer.play()
            updatePlayPauseButton(isPaused: false)
        } else {
            renderer.pausePlayback()
            updatePlayPauseButton(isPaused: true)
        }
    }
    
    @objc private func centerPlayPauseTapped() { playPauseTapped() }
    
    private var skipInterval: Double {
        let stored = UserDefaults.standard.double(forKey: "skipIntervalSeconds")
        return stored > 0 ? stored : 15.0
    }
    
    @objc private func skipBackwardTapped() {
        renderer.seek(by: -skipInterval)
        animateButtonTap(skipBackwardButton)
#if !os(tvOS)
        skipHaptic.impactOccurred()
#endif
        showControlsTemporarily()
    }
    
    @objc private func skipForwardTapped() {
        renderer.seek(by: skipInterval)
        animateButtonTap(skipForwardButton)
#if !os(tvOS)
        skipHaptic.impactOccurred()
#endif
        showControlsTemporarily()
    }
    
    private func subscribeToSubtitleSettings() {
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    @objc private func userDefaultsDidChange() {
        renderer.applySubtitleStyle(currentSubtitleStyle())
        renderer.setSubtitleVisible(subtitleIsVisible)
        updateSubtitleButtonAppearance()
        updateSubtitleMenu()
    }
    
    // MARK: - Subtitle menu
    
    private func updateSubtitleMenu() {
        let isVisible = subtitleIsVisible
        var actions: [UIAction] = []
        let disableAction = UIAction(
            title: "Disable Subtitles",
            image: UIImage(systemName: "xmark"),
            state: isVisible ? .off : .on
        ) { [weak self] _ in
            UserDefaults.standard.set(false, forKey: "subtitles_isVisible")
            self?.renderer.setSubtitleVisible(false)
            self?.updateSubtitleButtonAppearance()
            self?.updateSubtitleMenu()
        }
        actions.append(disableAction)
        
        for (i, _) in subtitleURLs.enumerated() {
            let selected = isVisible && currentSubtitleIndex == i
            actions.append(UIAction(
                title: "Subtitle \(i + 1)",
                image: UIImage(systemName: "captions.bubble"),
                state: selected ? .on : .off
            ) { [weak self] _ in
                self?.currentSubtitleIndex = i
                UserDefaults.standard.set(true, forKey: "subtitles_isVisible")
                self?.loadCurrentSubtitle()
                self?.renderer.setSubtitleVisible(true)
                self?.updateSubtitleButtonAppearance()
                self?.updateSubtitleMenu()
            })
        }
        
        let trackMenu = UIMenu(title: "Select Track", image: UIImage(systemName: "list.bullet"), children: actions)
        let appearanceMenu = createAppearanceMenu()
        subtitleButton.menu = UIMenu(title: "Subtitles", children: [trackMenu, appearanceMenu])
    }
    
    private func createAppearanceMenu() -> UIMenu {
        let d = UserDefaults.standard
        func colorAction(title: String, color: UIColor, current: UIColor, key: String) -> UIAction {
            UIAction(title: title, state: current.cgColor == color.cgColor ? .on : .off) { [weak self] _ in
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                    d.set(data, forKey: key)
                }
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        
        let fg = subtitleUIColor(forKey: "subtitles_foregroundColor", default: .white)
        let fgMenu = UIMenu(title: "Text Color", image: UIImage(systemName: "paintpalette"), children: [
            colorAction(title: "White", color: .white, current: fg, key: "subtitles_foregroundColor"),
            colorAction(title: "Yellow", color: .yellow, current: fg, key: "subtitles_foregroundColor"),
            colorAction(title: "Cyan", color: .cyan, current: fg, key: "subtitles_foregroundColor"),
            colorAction(title: "Green", color: .green, current: fg, key: "subtitles_foregroundColor"),
            colorAction(title: "Magenta", color: .magenta, current: fg, key: "subtitles_foregroundColor")
        ])
        
        let sc = subtitleUIColor(forKey: "subtitles_strokeColor", default: .black)
        let scMenu = UIMenu(title: "Stroke Color", image: UIImage(systemName: "pencil.tip"), children: [
            colorAction(title: "Black", color: .black, current: sc, key: "subtitles_strokeColor"),
            colorAction(title: "Dark Gray", color: .darkGray, current: sc, key: "subtitles_strokeColor"),
            colorAction(title: "White", color: .white, current: sc, key: "subtitles_strokeColor"),
            colorAction(title: "None", color: .clear, current: sc, key: "subtitles_strokeColor")
        ])
        
        let currentWidth = d.double(forKey: "subtitles_strokeWidth").nonZeroOr(1.0)
        func widthAction(_ name: String, _ w: Double) -> UIAction {
            UIAction(title: name, state: currentWidth == w ? .on : .off) { [weak self] _ in
                d.set(w, forKey: "subtitles_strokeWidth")
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        let swMenu = UIMenu(title: "Stroke Width", image: UIImage(systemName: "lineweight"), children: [
            widthAction("None", 0), widthAction("Thin", 0.5),
            widthAction("Normal", 1), widthAction("Medium", 1.5),
            widthAction("Thick", 2)
        ])
        
        let currentSize = d.double(forKey: "subtitles_fontSize").nonZeroOr(38.0)
        func sizeAction(_ name: String, _ s: Double) -> UIAction {
            UIAction(title: name, state: currentSize == s ? .on : .off) { [weak self] _ in
                d.set(s, forKey: "subtitles_fontSize")
                self?.updateCurrentSubtitleAppearance()
                self?.updateSubtitleMenu()
            }
        }
        let fsMenu = UIMenu(title: "Font Size", image: UIImage(systemName: "textformat.size"), children: [
            sizeAction("Small", 34), sizeAction("Medium", 38),
            sizeAction("Large", 42), sizeAction("Extra Large", 46),
            sizeAction("Huge", 56), sizeAction("Extra Huge", 66)
        ])
        
        return UIMenu(title: "Appearance", image: UIImage(systemName: "paintbrush"), children: [fgMenu, scMenu, swMenu, fsMenu])
    }
    
    private func updateCurrentSubtitleAppearance() {
        renderer.applySubtitleStyle(currentSubtitleStyle())
        renderer.setSubtitleVisible(subtitleIsVisible)
    }
    
    private func updateSubtitleButtonAppearance() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let name = subtitleIsVisible ? "captions.bubble.fill" : "captions.bubble"
        subtitleButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
    }
    
    private func loadSubtitles(_ urls: [String]) {
        subtitleURLs = urls
        guard !urls.isEmpty else { return }
        subtitleButton.isHidden = false
        currentSubtitleIndex = 0
        UserDefaults.standard.set(true, forKey: "subtitles_isVisible")
        renderer.applySubtitleStyle(currentSubtitleStyle())
        renderer.setSubtitleVisible(true)
        loadCurrentSubtitle()
        updateSubtitleButtonAppearance()
        updateSubtitleMenu()
    }
    
    private func loadCurrentSubtitle() {
        guard currentSubtitleIndex < subtitleURLs.count else { return }
        let urlString = subtitleURLs[currentSubtitleIndex]
        renderer.applySubtitleStyle(currentSubtitleStyle())
        renderer.clearCurrentSubtitleTrack()
        renderer.addSubtitleTrack(urlString: urlString)
        renderer.setSubtitleVisible(subtitleIsVisible)
        Logger.shared.log("Loading subtitle: \(urlString)", type: "Info")
    }
    
    private var subtitleIsVisible: Bool {
        UserDefaults.standard.bool(forKey: "subtitles_isVisible")
    }
    
    private func subtitleUIColor(forKey key: String, default fallback: UIColor) -> UIColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) else {
            return fallback
        }
        return color
    }
    
    private func currentSubtitleStyle() -> SubtitleStyle {
        let d = UserDefaults.standard
        let strokeWidth = d.double(forKey: "subtitles_strokeWidth").nonZeroOr(1.0)
        let fontSize = d.double(forKey: "subtitles_fontSize").nonZeroOr(38.0)
        return SubtitleStyle(
            foregroundColor: subtitleUIColor(forKey: "subtitles_foregroundColor", default: .white),
            strokeColor: subtitleUIColor(forKey: "subtitles_strokeColor", default: .black),
            strokeWidth: CGFloat(strokeWidth),
            fontSize: CGFloat(fontSize),
            isVisible: subtitleIsVisible
        )
    }
    
    // MARK: - Button animation
    
    private func animateButtonTap(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut) {
            button.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn) {
                button.transform = .identity
            }
        }
    }
    
    // MARK: - Progress slider
    
    private func installProgressHostingControllerIfNeeded() {
        guard progressHostingController == nil else { return }
        
        struct ProgressHostView: View {
            @ObservedObject var model: ProgressModel
            var onEditingChanged: (Bool) -> Void
            var body: some View {
                MusicProgressSlider(
                    value: Binding(get: { model.position }, set: { model.position = $0 }),
                    inRange: 0...max(model.duration, 1.0),
                    activeFillColor: .white, fillColor: .white,
                    textColor: .white.opacity(0.7),
                    height: 4, highlights: model.highlights,
                    onEditingChanged: onEditingChanged
                )
            }
        }
        
        let host = UIHostingController(rootView: AnyView(
            ProgressHostView(model: progressModel) { [weak self] editing in
                guard let self else { return }
                self.isSeeking = editing
                if editing {
                    self.controlsHideWorkItem?.cancel()
                    self.showControlsIfNeeded()
                } else {
                    self.renderer.seek(to: max(0, self.progressModel.position))
                    self.showControlsTemporarily()
                }
            }
        ))
        progressHostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        progressContainer.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
    
    // MARK: - Play/pause button
    
    private func updatePlayPauseButton(isPaused: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let cfg = UIImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
            let name = isPaused ? "play.fill" : "pause.fill"
            
            self.centerPlayPauseButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
            self.centerPlayPauseButton.isHidden = false
            
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                self.centerPlayPauseButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            } completion: { _ in
                UIView.animate(withDuration: 0.15) {
                    self.centerPlayPauseButton.transform = .identity
                }
            }
            self.showControlsTemporarily()
        }
    }
    
    // MARK: - Error display
    
    private func presentStartupErrorAlert(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let ac = UIAlertController(title: "Playback Error", message: message, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            ac.addAction(UIAlertAction(title: "View Logs", style: .default) { [weak self] _ in
                self?.viewLogsTapped()
            })
            if self.presentedViewController == nil {
                self.present(ac, animated: true)
            }
        }
    }
    
    private func showTransientErrorBanner(_ message: String, duration: TimeInterval = 4.0) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showErrorBanner(message)
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideErrorBanner), object: nil)
            self.perform(#selector(self.hideErrorBanner), with: nil, afterDelay: duration)
        }
    }
    
    @objc private func hideErrorBanner() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25) {
                self.errorBanner.alpha = 0.0
            } completion: { _ in
                self.errorBanner.transform = .identity
            }
        }
    }
    
    @objc private func handleLoggerNotification(_ note: Notification) {
        guard let info = note.userInfo,
              let message = info["message"] as? String,
              let type = info["type"] as? String else { return }
        
        let lower = type.lowercased()
        if lower == "error" || lower == "warn" || message.lowercased().contains("error") || message.lowercased().contains("warn") {
            showTransientErrorBanner(message)
        }
    }
    
    private func showErrorBanner(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let label = self.errorBanner.viewWithTag(101) as? UILabel else { return }
            label.text = message
            
            self.errorBanner.transform = .identity
            self.view.bringSubviewToFront(self.errorBanner)
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.6, options: .curveEaseOut) {
                self.errorBanner.alpha = 1.0
                self.errorBanner.transform = CGAffineTransform(translationX: 0, y: 4)
            }
        }
    }
    
    @objc private func viewLogsTapped() {
        Task { @MainActor in
            let logs = await Logger.shared.getLogsAsync()
            let vc = UIViewController()
            let tv = UITextView()
            tv.translatesAutoresizingMaskIntoConstraints = false
#if !os(tvOS)
            vc.view.backgroundColor = UIColor.systemBackground
            tv.isEditable = false
#endif
            tv.text = logs
            tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            vc.view.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor, constant: 12),
                tv.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 12),
                tv.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor, constant: -12),
                tv.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: -12),
            ])
            vc.navigationItem.title = "Logs"
            let nav = UINavigationController(rootViewController: vc)
#if !os(tvOS)
            nav.modalPresentationStyle = .pageSheet
#endif
            let close: UIBarButtonItem
#if compiler(>=6.0)
            if #available(iOS 26.0, tvOS 26.0, *) {
                close = UIBarButtonItem(title: "Close", style: .prominent, target: self, action: #selector(dismissLogs))
            } else {
                close = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(dismissLogs))
            }
#else
            close = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(dismissLogs))
#endif
            vc.navigationItem.rightBarButtonItem = close
            present(nav, animated: true)
        }
    }
    
    @objc private func dismissLogs() { dismiss(animated: true) }
    
    // MARK: - Controls visibility
    
    @objc private func containerTapped() {
        controlsVisible ? hideControls() : showControlsTemporarily()
    }
    
    private func showControlsIfNeeded() {
        guard !controlsVisible else { return }
        controlsVisible = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.setControlsAlpha(1.0)
            }
        }
    }
    
    private func showControlsTemporarily() {
        controlsHideWorkItem?.cancel()
        controlsVisible = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.setControlsAlpha(1.0)
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.hideControls() }
        controlsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }
    
    private func hideControls() {
        controlsHideWorkItem?.cancel()
        controlsVisible = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
                self.setControlsAlpha(0.0)
            }
        }
    }
    
    private func setControlsAlpha(_ alpha: CGFloat) {
        centerPlayPauseButton.alpha = alpha
        controlsOverlayView.alpha = alpha
        progressContainer.alpha = alpha
        closeButton.alpha = alpha
        pipButton.alpha = alpha
        skipBackwardButton.alpha = alpha
        skipForwardButton.alpha = alpha
        if !subtitleButton.isHidden { subtitleButton.alpha = alpha }
    }
    
    // MARK: - Close / PiP
    
    @objc private func closeTapped() {
        pipController?.delegate = nil
        if pipController?.isPictureInPictureActive == true { pipController?.stopPictureInPicture() }
        renderer.stop()
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            view.window?.rootViewController?.dismiss(animated: true)
        }
    }
    
    @objc private func pipTapped() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            renderer.startPiPRendering()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, let pip = self.pipController, !pip.isPictureInPictureActive else { return }
                pip.startPictureInPicture()
            }
        }
    }
    
    // MARK: - Skip segment
    
    @objc private func skipSegmentTapped() {
        guard let segment = currentActiveSegment(at: cachedPosition) else { return }
        guard let target = resolvedEnd(for: segment, duration: cachedDuration) else { return }
        renderer.seek(to: max(0, target))
        showControlsTemporarily()
    }
    
    // MARK: - Position update
    
    private func updatePosition(_ position: Double, duration: Double) {
        self.cachedDuration = duration
        self.cachedPosition = position
        
        let now = CACurrentMediaTime()
        guard now - lastUIUpdateTime > 0.1 else { return }
        lastUIUpdateTime = now
        
        if duration > 0 {
            self.installProgressHostingControllerIfNeeded()
            self.updateProgressHighlights(duration: duration)
        }
        self.progressModel.position = position
        self.progressModel.duration = max(duration, 1.0)
        self.updateActiveSkipSegment(at: position, duration: duration)
        
        if self.pipController?.isPictureInPictureActive == true {
            self.pipController?.invalidatePlaybackState()
        }
        
        guard duration.isFinite, duration > 0, position >= 0, let info = mediaInfo else { return }
        
        switch info {
        case .movie(let id, let title):
            ProgressManager.shared.updateMovieProgress(movieId: id, title: title, currentTime: position, totalDuration: duration)
        case .episode(let showId, let showTitle, let season, let episode):
            ProgressManager.shared.updateEpisodeProgress(showId: showId, showTitle: showTitle, seasonNumber: season, episodeNumber: episode, currentTime: position, totalDuration: duration)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(round(seconds))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - IntroDB
    
    private func fetchIntroDBSegments(for info: MediaInfo) {
        IntroDBService.shared.fetchSegments(for: info) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let segments):
                DispatchQueue.main.async {
                    self.introDBSegments = segments
                    self.updateProgressHighlights(duration: self.cachedDuration)
                    self.updateActiveSkipSegment(at: self.cachedPosition, duration: self.cachedDuration)
                }
                Logger.shared.log("Loaded \(segments.count) IntroDB segments", type: "Info")
            case .failure(let error):
                Logger.shared.log("IntroDB request failed: \(error.localizedDescription)", type: "Warn")
            }
        }
    }
    
    private func updateProgressHighlights(duration: Double) {
        let highlights = IntroDBService.shared.highlights(for: introDBSegments, duration: duration)
        progressModel.highlights = highlights.map {
            ProgressHighlight(start: $0.start, end: $0.end, color: Color($0.color), label: $0.label)
        }
    }
    
    private func currentActiveSegment(at position: Double, duration: Double? = nil) -> IntroDBSegment? {
        IntroDBService.shared.activeSegment(at: position, in: introDBSegments, duration: duration ?? cachedDuration)
    }
    
    private func updateActiveSkipSegment(at position: Double, duration: Double) {
        let active = currentActiveSegment(at: position, duration: duration)
        let newID = active?.id
        guard newID != activeSkipSegmentID else { return }
        activeSkipSegmentID = newID
        if let active { showSkipButton(for: active) } else { hideSkipButton() }
    }
    
    private func showSkipButton(for segment: IntroDBSegment) {
        skipSegmentButton.setTitle("Skip \(segment.db.title)", for: .normal)
        skipSegmentButton.backgroundColor = segment.db.uiColor.withAlphaComponent(0.55)
        guard skipSegmentButton.isHidden || skipSegmentButton.alpha < 1 else { return }
        skipSegmentButton.isHidden = false
        UIView.animate(withDuration: 0.2) { self.skipSegmentButton.alpha = 1.0 }
    }
    
    private func hideSkipButton() {
        guard !skipSegmentButton.isHidden else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.skipSegmentButton.alpha = 0.0
        }, completion: { _ in
            self.skipSegmentButton.isHidden = true
        })
    }
    
    private func resolvedEnd(for segment: IntroDBSegment, duration: Double) -> Double? {
        segment.resolvedEnd(duration: duration)
    }
}

// MARK: - MPVRendererDelegate
extension PlayerViewController: MPVRendererDelegate {
    func renderer(_ renderer: MPVRenderer, didUpdatePosition position: Double, duration: Double) {
        updatePosition(position, duration: duration)
    }
    func renderer(_ renderer: MPVRenderer, didChangePause isPaused: Bool) {
        updatePlayPauseButton(isPaused: isPaused)
        pipController?.invalidatePlaybackState()
    }
    func renderer(_ renderer: MPVRenderer, didChangeLoading isLoading: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isLoading {
                self.centerPlayPauseButton.isHidden = true
                self.loadingIndicator.alpha = 1.0
                self.loadingIndicator.startAnimating()
            } else {
                self.loadingIndicator.stopAnimating()
                self.loadingIndicator.alpha = 0.0
                self.updatePlayPauseButton(isPaused: self.renderer.isPausedState)
            }
        }
    }
    func renderer(_ renderer: MPVRenderer, didBecomeReadyToSeek: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let t = self.pendingSeekTime {
                self.renderer.seek(to: t)
                Logger.shared.log("Resumed from \(Int(t))s", type: "Progress")
                self.pendingSeekTime = nil
            }
            if let subs = self.pendingSubtitleURLs {
                self.pendingSubtitleURLs = nil
                self.loadSubtitles(subs)
            }
        }
    }
}

// MARK: - PiP Support
extension PlayerViewController: PiPControllerDelegate {
    public func pipControllerWillStart(_ c: PiPController) { }
    
    public func pipControllerDidStart(_ c: PiPController) { }
    
    public func pipControllerDidFailToStart(_ c: PiPController) {
        renderer.stopPiPRendering()
    }
    
    public func pipControllerWillStop(_ c: PiPController) {}
    
    public func pipControllerDidStop(_ c: PiPController) {
        renderer.stopPiPRendering()
    }
    
    public func pipController(_ c: PiPController, restoreUserInterfaceForStop handler: @escaping (Bool) -> Void) {
        if presentedViewController != nil {
            dismiss(animated: true) { handler(true) }
        } else {
            handler(true)
        }
    }
    
    public func pipControllerPlay(_ c: PiPController) {
        renderer.play()
    }
    
    public func pipControllerPause(_ c: PiPController) {
        renderer.pausePlayback()
    }
    
    public func pipController(_ c: PiPController, skipByInterval interval: CMTime, completion: @escaping () -> Void) {
        let target = max(0, cachedPosition + CMTimeGetSeconds(interval))
        renderer.seek(to: target)
        completion()
    }
    
    public func pipControllerIsPlaying(_ c: PiPController) -> Bool { !renderer.isPausedState }
    public func pipControllerDuration(_ c: PiPController) -> Double { cachedDuration }
    public func pipControllerCurrentTime(_ c: PiPController) -> Double { cachedPosition }
    
    @objc private func appWillResignActive() {
        guard let pip = pipController, !pip.isPictureInPictureActive else { return }
        renderer.startPiPRendering()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let pip = self.pipController, !pip.isPictureInPictureActive else { return }
            pip.startPictureInPicture()
        }
    }
}

// MARK: - Helpers

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double { self != 0 ? self : fallback }
}

//
//  VideoPlayerViewController.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import UIKit
import AVFoundation

// Since MPVKit might not be installed yet, I'll create a protocol-based approach
// This will make it easy to integrate MPVKit once it's added as a dependency

protocol VideoPlayerEngine: AnyObject {
    var delegate: VideoPlayerEngineDelegate? { get set }
    var view: UIView { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var playbackRate: Float { get set }
    
    func loadVideo(url: URL)
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
}

protocol VideoPlayerEngineDelegate: AnyObject {
    func playerDidUpdateTime(_ time: TimeInterval)
    func playerDidFinishPlaying()
    func playerDidFailWithError(_ error: Error)
    func playerDidChangePlaybackState(_ isPlaying: Bool)
}

class VideoPlayerViewController: UIViewController {
    
    // MARK: - Properties
    private var playerEngine: VideoPlayerEngine?
    private var mediaItem: MediaItem?
    
    // MARK: - UI Components
    private lazy var playerContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var controlsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 1.0
        return view
    }()
    
    private lazy var playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "play.fill"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var previousButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "backward.fill"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var progressSlider: UISlider = {
        let slider = UISlider()
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(progressSliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(progressSliderTouchBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(progressSliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
        return slider
    }()
    
    private lazy var currentTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "0:00"
        label.textColor = .white
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var durationLabel: UILabel = {
        let label = UILabel()
        label.text = "0:00"
        label.textColor = .white
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var volumeSlider: UISlider = {
        let slider = UISlider()
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.value = 1.0
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(volumeSliderChanged), for: .valueChanged)
        return slider
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        return label
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // MARK: - Private Properties
    private var isSliderBeingDragged = false
    private var controlsTimer: Timer?
    private var isControlsVisible = true
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        hideControlsAfterDelay()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playerEngine?.pause()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        // Add subviews
        view.addSubview(playerContainerView)
        view.addSubview(controlsContainerView)
        
        // Add controls to container
        controlsContainerView.addSubview(titleLabel)
        controlsContainerView.addSubview(closeButton)
        controlsContainerView.addSubview(playPauseButton)
        controlsContainerView.addSubview(previousButton)
        controlsContainerView.addSubview(nextButton)
        controlsContainerView.addSubview(progressSlider)
        controlsContainerView.addSubview(currentTimeLabel)
        controlsContainerView.addSubview(durationLabel)
        controlsContainerView.addSubview(volumeSlider)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Player container
            playerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Controls container
            controlsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlsContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controlsContainerView.heightAnchor.constraint(equalToConstant: 120),
            
            // Title and close button
            titleLabel.topAnchor.constraint(equalTo: controlsContainerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: controlsContainerView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16),
            
            closeButton.topAnchor.constraint(equalTo: controlsContainerView.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Progress slider and time labels
            currentTimeLabel.leadingAnchor.constraint(equalTo: controlsContainerView.leadingAnchor, constant: 20),
            currentTimeLabel.bottomAnchor.constraint(equalTo: playPauseButton.topAnchor, constant: -16),
            
            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 8),
            progressSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            progressSlider.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            
            durationLabel.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor, constant: -20),
            durationLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            durationLabel.widthAnchor.constraint(equalTo: currentTimeLabel.widthAnchor),
            
            // Playback controls
            playPauseButton.centerXAnchor.constraint(equalTo: controlsContainerView.centerXAnchor),
            playPauseButton.bottomAnchor.constraint(equalTo: controlsContainerView.bottomAnchor, constant: -20),
            playPauseButton.widthAnchor.constraint(equalToConstant: 50),
            playPauseButton.heightAnchor.constraint(equalToConstant: 50),
            
            previousButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -30),
            previousButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 40),
            previousButton.heightAnchor.constraint(equalToConstant: 40),
            
            nextButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 30),
            nextButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 40),
            nextButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Volume slider
            volumeSlider.trailingAnchor.constraint(equalTo: controlsContainerView.trailingAnchor, constant: -20),
            volumeSlider.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            volumeSlider.widthAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(playerViewTapped))
        playerContainerView.addGestureRecognizer(tapGesture)
        
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(playerViewDoubleTapped))
        doubleTapGesture.numberOfTapsRequired = 2
        playerContainerView.addGestureRecognizer(doubleTapGesture)
        
        tapGesture.require(toFail: doubleTapGesture)
    }
    
    // MARK: - Public Methods
    func loadMedia(_ mediaItem: MediaItem) {
        self.mediaItem = mediaItem
        titleLabel.text = mediaItem.displayTitle
        
        // Set duration if available
        if let duration = mediaItem.duration {
            durationLabel.text = formatTime(duration)
            progressSlider.maximumValue = Float(duration)
        }
        
        // Initialize player engine (placeholder for MPVKit integration)
        // playerEngine = MPVPlayerEngine()
        // playerEngine?.delegate = self
        // playerEngine?.loadVideo(url: mediaItem.url)
        
        // For now, we'll use a placeholder
        setupPlaceholderPlayer(with: mediaItem.url)
    }
    
    // MARK: - Private Methods
    private func setupPlaceholderPlayer(with url: URL) {
        // Initialize MPV player engine
        playerEngine = MPVPlayerEngine()
        playerEngine?.delegate = self
        
        // Add player view to container
        if let playerView = playerEngine?.view {
            playerView.translatesAutoresizingMaskIntoConstraints = false
            playerContainerView.addSubview(playerView)
            
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: playerContainerView.topAnchor),
                playerView.leadingAnchor.constraint(equalTo: playerContainerView.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: playerContainerView.trailingAnchor),
                playerView.bottomAnchor.constraint(equalTo: playerContainerView.bottomAnchor)
            ])
        }
        
        // Load the video
        playerEngine?.loadVideo(url: url)
    }
    
    private func hideControlsAfterDelay() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hideControls()
        }
    }
    
    private func showControls() {
        guard !isControlsVisible else { return }
        isControlsVisible = true
        
        UIView.animate(withDuration: 0.3) {
            self.controlsContainerView.alpha = 1.0
        }
        
        hideControlsAfterDelay()
    }
    
    private func hideControls() {
        guard isControlsVisible else { return }
        isControlsVisible = false
        
        UIView.animate(withDuration: 0.3) {
            self.controlsContainerView.alpha = 0.0
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Actions
    @objc private func playPauseButtonTapped() {
        if playerEngine?.isPlaying == true {
            playerEngine?.pause()
            playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            playerEngine?.play()
            playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
        hideControlsAfterDelay()
    }
    
    @objc private func previousButtonTapped() {
        playerEngine?.seek(to: max(0, (playerEngine?.currentTime ?? 0) - 10))
        hideControlsAfterDelay()
    }
    
    @objc private func nextButtonTapped() {
        let currentTime = playerEngine?.currentTime ?? 0
        let duration = playerEngine?.duration ?? 0
        playerEngine?.seek(to: min(duration, currentTime + 10))
        hideControlsAfterDelay()
    }
    
    @objc private func progressSliderTouchBegan() {
        isSliderBeingDragged = true
        controlsTimer?.invalidate()
    }
    
    @objc private func progressSliderChanged() {
        if isSliderBeingDragged {
            let time = TimeInterval(progressSlider.value)
            currentTimeLabel.text = formatTime(time)
        }
    }
    
    @objc private func progressSliderTouchEnded() {
        let time = TimeInterval(progressSlider.value)
        playerEngine?.seek(to: time)
        isSliderBeingDragged = false
        hideControlsAfterDelay()
    }
    
    @objc private func volumeSliderChanged() {
        playerEngine?.volume = volumeSlider.value
        hideControlsAfterDelay()
    }
    
    @objc private func closeButtonTapped() {
        playerEngine?.stop()
        dismiss(animated: true)
    }
    
    @objc private func playerViewTapped() {
        if isControlsVisible {
            hideControls()
        } else {
            showControls()
        }
    }
    
    @objc private func playerViewDoubleTapped() {
        playPauseButtonTapped()
    }
}

// MARK: - VideoPlayerEngineDelegate
extension VideoPlayerViewController: VideoPlayerEngineDelegate {
    func playerDidUpdateTime(_ time: TimeInterval) {
        DispatchQueue.main.async {
            if !self.isSliderBeingDragged {
                self.progressSlider.value = Float(time)
                self.currentTimeLabel.text = self.formatTime(time)
            }
        }
    }
    
    func playerDidFinishPlaying() {
        DispatchQueue.main.async {
            self.playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        }
    }
    
    func playerDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Playback Error", 
                                        message: error.localizedDescription, 
                                        preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
    
    func playerDidChangePlaybackState(_ isPlaying: Bool) {
        DispatchQueue.main.async {
            let imageName = isPlaying ? "pause.fill" : "play.fill"
            self.playPauseButton.setImage(UIImage(systemName: imageName), for: .normal)
        }
    }
}

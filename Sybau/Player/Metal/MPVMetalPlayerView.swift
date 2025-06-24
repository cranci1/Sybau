import Foundation
import SwiftUI

struct MPVMetalPlayerView: UIViewControllerRepresentable {
    @ObservedObject var coordinator: Coordinator
    
    func makeUIViewController(context: Context) -> some UIViewController {
        let mpv =  MPVMetalViewController()
        mpv.playDelegate = coordinator
        mpv.playUrl = coordinator.playUrl
        
        context.coordinator.player = mpv
        return mpv
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
    
    public func makeCoordinator() -> Coordinator {
        coordinator
    }
    
    func play(_ url: URL) -> Self {
        coordinator.playUrl = url
        return self
    }
    
    func onPropertyChange(_ handler: @escaping (MPVMetalViewController, String, Any?) -> Void) -> Self {
        coordinator.onPropertyChange = handler
        return self
    }
    
    @MainActor
    public final class Coordinator: MPVPlayerDelegate, ObservableObject {
        weak var player: MPVMetalViewController?
        
        var playUrl : URL?
        var onPropertyChange: ((MPVMetalViewController, String, Any?) -> Void)?
        
        @Published var currentTime: Double = 0
        @Published var duration: Double = 0
        @Published var isPlaying: Bool = true
        
        private var timeObserverTimer: Timer?
        
        func play(_ url: URL) {
            player?.loadFile(url)
            setupTimeObserver()
        }
        
        func play() {
            player?.play()
            isPlaying = true
        }
        
        func pause() {
            player?.pause()
            isPlaying = false
        }
        
        func seek(to time: Double) {
            player?.seek(to: time)
        }
        
        func seek(by offset: Double) {
            if let currentTime = player?.currentTime {
                seek(to: currentTime + offset)
            }
        }
        
        private func setupTimeObserver() {
            timeObserverTimer?.invalidate()
            timeObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.duration = player.duration
            }
        }
        
        func propertyChange(mpv: OpaquePointer, propertyName: String, data: Any?) {
            guard let player else { return }
            
            switch propertyName {
            case MPVProperty.pause:
                if let paused = data as? Bool {
                    isPlaying = !paused
                }
            default:
                self.onPropertyChange?(player, propertyName, data)
            }
        }
    }
}


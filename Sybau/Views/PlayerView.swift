import SwiftUI

struct PlayerView: View {
    @StateObject private var dataManager = DataManager.shared
    @ObservedObject var coordinator = MPVMetalPlayerView.Coordinator()
    @State private var showingControls = true
    @State private var isFullscreen = false
    @State private var loading = false
    @State private var showingPlaylist = false
    @State private var currentFile: MediaFile?
    @State private var controlsTimer: Timer?
    
    let mediaFile: MediaFile
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Player View
                MPVMetalPlayerView(coordinator: coordinator)
                    .play(mediaFile.url)
                    .onPropertyChange { player, propertyName, propertyData in
                        switch propertyName {
                        case MPVProperty.pausedForCache:
                            loading = propertyData as! Bool
                        default: break
                        }
                    }
                    .edgesIgnoringSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        toggleControls()
                    }
                
                // Loading indicator
                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(10)
                }
                
                // Controls overlay
                if showingControls {
                    VStack {
                        // Top controls
                        topControlsView
                        
                        Spacer()
                        
                        // Media controls
                        MediaControlsView(coordinator: coordinator)
                            .padding(.horizontal)
                            .padding(.bottom, geometry.safeAreaInsets.bottom)
                    }
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.7),
                                Color.clear,
                                Color.black.opacity(0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showingControls)
                }
                
                // Playlist sidebar
                if showingPlaylist {
                    HStack {
                        playlistSidebar
                            .frame(width: min(geometry.size.width * 0.4, 300))
                            .transition(.move(edge: .leading))
                        
                        Spacer()
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                setupPlayer()
                startControlsTimer()
            }
            .onDisappear {
                stopControlsTimer()
            }
            .statusBarHidden(isFullscreen)
        }
    }
    
    private var topControlsView: some View {
        HStack {
            Button(action: { 
                // Navigate back
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mediaFile.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let duration = mediaFile.duration {
                    Text("Duration: \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            Button(action: { showingPlaylist.toggle() }) {
                Image(systemName: "list.bullet")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Button(action: { toggleFavorite() }) {
                Image(systemName: dataManager.isFavorite(mediaFile) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(dataManager.isFavorite(mediaFile) ? .red : .white)
            }
            
            Button(action: { toggleFullscreen() }) {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var playlistSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingPlaylist = false }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(dataManager.recentlyPlayed) { file in
                        PlaylistItemRow(
                            file: file,
                            isCurrentFile: file.id == mediaFile.id
                        ) {
                            playFile(file)
                        }
                    }
                }
                .padding()
            }
            .background(Color.black.opacity(0.6))
        }
        .background(Color.black.opacity(0.8))
    }
    
    private func setupPlayer() {
        currentFile = mediaFile
        coordinator.play(mediaFile.url)
        dataManager.addToRecentlyPlayed(mediaFile)
    }
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingControls.toggle()
        }
        
        if showingControls {
            startControlsTimer()
        } else {
            stopControlsTimer()
        }
    }
    
    private func startControlsTimer() {
        stopControlsTimer()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls = false
            }
        }
    }
    
    private func stopControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = nil
    }
    
    private func toggleFavorite() {
        dataManager.toggleFavorite(mediaFile)
    }
    
    private func toggleFullscreen() {
        isFullscreen.toggle()
        if isFullscreen {
            // Enter fullscreen
            UIApplication.setOrientation(UIDeviceOrientation.landscapeRight, isPortrait: false)
        } else {
            // Exit fullscreen
            UIApplication.setOrientation(UIDeviceOrientation.portrait, isPortrait: true)
        }
    }
    
    private func playFile(_ file: MediaFile) {
        coordinator.play(file.url)
        dataManager.addToRecentlyPlayed(file)
        currentFile = file
    }
}

// MARK: - Playlist Item Row
struct PlaylistItemRow: View {
    let file: MediaFile
    let isCurrentFile: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            // Thumbnail
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 30)
                .cornerRadius(4)
                .overlay(
                    Image(systemName: file.type.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .foregroundColor(isCurrentFile ? .blue : .white)
                    .lineLimit(1)
                
                if let duration = file.duration {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isCurrentFile {
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isCurrentFile ? Color.blue.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Helper Functions
private func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = Int(duration) % 3600 / 60
    let seconds = Int(duration) % 60
    
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - UIApplication Extension
extension UIApplication {
    static func setOrientation(_ orientation: UIDeviceOrientation, isPortrait: Bool) {
        if isPortrait {
            UIDevice.current.setValue(UIDeviceOrientation.portrait.rawValue, forKey: "orientation")
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        }
    }
}

#Preview {
    PlayerView(mediaFile: MediaFile(
        name: "Sample Video",
        url: URL(string: "https://example.com/video.mp4")!,
        size: 1024000,
        duration: 3600,
        format: "mp4",
        dateAdded: Date(),
        thumbnailPath: nil,
        type: .video
    ))
}

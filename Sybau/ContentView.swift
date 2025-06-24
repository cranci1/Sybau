import SwiftUI

struct ContentView: View {
    @ObservedObject var coordinator = MPVMetalPlayerView.Coordinator()
    @State var loading = false
    @State private var showPlaylist = false
    @State private var isFullscreen = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MPVMetalPlayerView(coordinator: coordinator)
                    .play(URL(string: "https://github.com/mpvkit/video-test/raw/master/resources/HDR10_ToneMapping_Test_240_1000_nits.mp4")!)
                    .onPropertyChange { player, propertyName, propertyData in
                        switch propertyName {
                        case MPVProperty.pausedForCache:
                            loading = propertyData as! Bool
                        default: break
                        }
                    }
                    .edgesIgnoringSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                VStack {
                    HStack {
                        Button(action: { showPlaylist.toggle() }) {
                            Image(systemName: "list.bullet")
                                .foregroundColor(.white)
                                .font(.title2)
                                .padding()
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isFullscreen.toggle()
                            if isFullscreen {
                                OrientationLock.lock(to: .landscape)
                                UIApplication.setOrientation(.landscapeRight, isPortrait: false)
                            } else {
                                OrientationLock.lock(to: .portrait)
                                UIApplication.setOrientation(.portrait, isPortrait: true)
                            }
                        }) {
                            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .foregroundColor(.white)
                                .font(.title2)
                                .padding()
                        }
                    }
                    .background(LinearGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.7), .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    
                    Spacer()
                    MediaControlsView(coordinator: coordinator)
                        .onAppear {
                            NotificationCenter.default.addObserver(
                                forName: NSNotification.Name("VideoChanged"),
                                object: nil,
                                queue: .main) { _ in
                                    coordinator.objectWillChange.send()
                                }
                        }
                }
                
                if showPlaylist {
                    playlistView
                        .transition(.move(edge: .leading))
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                UIDevice.current.setValue(UIDeviceOrientation.unknown.rawValue, forKey: "orientation")
                
                NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
                    let orientation = UIDevice.current.orientation
                    if orientation.isLandscape {
                        isFullscreen = true
                    } else if orientation.isPortrait {
                        isFullscreen = false
                    }
                }
            }
            .statusBar(hidden: isFullscreen)
        }
    }
    
    private var playlistView: some View {
        VStack {
            ScrollView {
                VStack(spacing: 10) {
                    playlistButton(title: "H.264 Sample", url: "https://vjs.zencdn.net/v/oceans.mp4")
                    playlistButton(title: "H.265 Sample", url: "https://github.com/mpvkit/video-test/raw/master/resources/h265.mp4")
                    playlistButton(title: "Subtitled Video", url: "https://github.com/mpvkit/video-test/raw/master/resources/pgs_subtitle.mkv")
                    playlistButton(title: "HDR Sample", url: "https://github.com/mpvkit/video-test/raw/master/resources/hdr.mkv")
                    playlistButton(title: "Dolby Vision P5", url: "https://github.com/mpvkit/video-test/raw/master/resources/DolbyVision_P5.mp4")
                    playlistButton(title: "Dolby Vision P8", url: "https://github.com/mpvkit/video-test/raw/master/resources/DolbyVision_P8.mp4")
                }
                .padding()
            }
        }
        .frame(width: 250)
        .background(Color.black.opacity(0.8))
        .animation(.easeInOut, value: showPlaylist)
    }
    
    private func playlistButton(title: String, url: String) -> some View {
        Button {
            coordinator.play(URL(string: url)!)
            showPlaylist = false
        } label: {
            Text(title)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

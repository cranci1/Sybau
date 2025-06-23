//
//  ContentView.swift
//  Sybau
//
//  Created by Francesco on 22/06/25.
//

import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showFileImporter = false
    @State private var showURLInput = false
    @State private var streamURL = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var playbackRate: Float = 1.0
    @State private var showControls = true
    @State private var lastPlaybackPosition: Double = 0.0
    @State private var showThemeSheet = false
    @State private var isDarkMode = false
    @State private var showSubtitleImporter = false
    @State private var subtitleURL: URL?
    
    private let supportedFileExtensions = ["mp4", "mov", "m4v", "3gp", "m3u8"]
    private let supportedSubtitleExtensions = ["srt", "ass", "vtt"]
    
    private func isFormatSupported(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedFileExtensions.contains(fileExtension)
    }
    
    private func playMedia(from url: URL) {
        if isFormatSupported(url) {
            player = AVPlayer(url: url)
            if lastPlaybackPosition > 0 {
                let seekTime = CMTime(seconds: lastPlaybackPosition, preferredTimescale: 1)
                player?.seek(to: seekTime)
            }
            player?.rate = playbackRate
            player?.play()
            isPlaying = true
        } else {
            errorMessage = "This format is not supported. Supported formats: MP4, MOV, M4V, 3GP, HLS(M3U8)"
            showError = true
        }
    }
    
    private func loadSubtitle(from url: URL) {
        // To lazy to add it here for now
        subtitleURL = url
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(isDarkMode ? .black : .white).ignoresSafeArea()
                VStack {
                    if let player = player {
                        ZStack {
                            VideoPlayer(player: player)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture {
                                    withAnimation { showControls.toggle() }
                                }
                            if showControls {
                                VStack {
                                    Spacer()
                                    HStack(spacing: 20) {
                                        Button(action: { showFileImporter = true }) {
                                            Label("Open", systemImage: "folder")
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.blue)
                                                .cornerRadius(10)
                                        }
                                        Button(action: { showURLInput = true }) {
                                            Label("Stream", systemImage: "globe")
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.blue)
                                                .cornerRadius(10)
                                        }
                                        Button(action: {
                                            if isPlaying {
                                                player.pause()
                                            } else {
                                                player.play()
                                            }
                                            isPlaying.toggle()
                                        }) {
                                            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.blue)
                                                .cornerRadius(10)
                                        }
                                        Button(action: { showSubtitleImporter = true }) {
                                            Label("Subtitles", systemImage: "captions.bubble.fill")
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.purple)
                                                .cornerRadius(10)
                                        }
                                        Button(action: { showThemeSheet = true }) {
                                            Label("Theme", systemImage: "paintbrush")
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.gray)
                                                .cornerRadius(10)
                                        }
                                    }
                                    .padding(.bottom, 10)
                                    HStack {
                                        Text("Speed")
                                            .foregroundColor(.white)
                                        Slider(value: $playbackRate, in: 0.5...2.0, step: 0.1) {
                                            Text("Speed")
                                        } minimumValueLabel: {
                                            Text("0.5x").foregroundColor(.white)
                                        } maximumValueLabel: {
                                            Text("2x").foregroundColor(.white)
                                        }
                                        .frame(width: 150)
                                        Text(String(format: "%.1fx", playbackRate))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.bottom, 20)
                                }
                                .background(Color.black.opacity(0.5))
                            }
                        }
                        .onDisappear {
                            if let currentTime = player.currentItem?.currentTime().seconds {
                                lastPlaybackPosition = currentTime
                            }
                        }
                        .onChange(of: playbackRate) { newValue in
                            player.rate = isPlaying ? newValue : 0
                        }
                    } else {
                        VStack {
                            Image(systemName: "play.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .foregroundColor(.blue)
                            Text("Open a video file or stream to start playing")
                                .font(.headline)
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("Sybau Player")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video, .audiovisualContent],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        playMedia(from: url)
                    }
                case .failure(let error):
                    errorMessage = "Error selecting file: \(error.localizedDescription)"
                    showError = true
                }
            }
            .fileImporter(
                isPresented: $showSubtitleImporter,
                allowedContentTypes: [.init(filenameExtension: "srt")!, .init(filenameExtension: "ass")!, .init(filenameExtension: "vtt")!],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        loadSubtitle(from: url)
                    }
                case .failure(let error):
                    errorMessage = "Error loading subtitle: \(error.localizedDescription)"
                    showError = true
                }
            }
            .alert("Enter Stream URL", isPresented: $showURLInput) {
                TextField("https://example.com/stream.m3u8", text: $streamURL)
                Button("Cancel", role: .cancel) {
                    streamURL = ""
                }
                Button("Play") {
                    if let url = URL(string: streamURL) {
                        playMedia(from: url)
                    } else {
                        errorMessage = "Invalid URL format"
                        showError = true
                    }
                    streamURL = ""
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog("Theme", isPresented: $showThemeSheet) {
                Button("Light") { isDarkMode = false }
                Button("Dark") { isDarkMode = true }
                Button("System", role: .cancel) { isDarkMode = false }
            }
        }
    }
}

#Preview {
    ContentView()
}

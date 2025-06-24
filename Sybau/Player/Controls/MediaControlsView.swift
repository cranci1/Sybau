//
//  MediaControlsView.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import SwiftUI

struct MediaControlsView: View {
    @ObservedObject var coordinator: MPVMetalPlayerView.Coordinator
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 8) {
                Slider(value: Binding(
                    get: { currentTime },
                    set: { newValue in
                        currentTime = newValue
                        coordinator.seek(to: newValue)
                    }
                ), in: 0...max(duration, 1))
                .accentColor(.white)
                
                HStack {
                    Text(timeString(from: currentTime))
                        .foregroundColor(.white)
                    Spacer()
                    Text(timeString(from: duration))
                        .foregroundColor(.white)
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal)
            
            HStack(spacing: 30) {
                Button(action: {
                    coordinator.seek(by: -10)
                    resetControlsTimer()
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    if isPlaying {
                        coordinator.pause()
                    } else {
                        coordinator.play()
                    }
                    isPlaying.toggle()
                    resetControlsTimer()
                }) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                
                Button(action: {
                    coordinator.seek(by: 10)
                    resetControlsTimer()
                }) {
                    Image(systemName: "goforward.10")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 30)
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.6)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .onTapGesture {
            showControls.toggle()
            resetControlsTimer()
        }
        .onAppear {
            resetControlsTimer()
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("VideoChanged"),
                object: nil,
                queue: .main) { _ in
                    resetControlsTimer()
                }
        }
        .onReceive(coordinator.$currentTime) { newTime in
            currentTime = newTime
        }
        .onReceive(coordinator.$duration) { newDuration in
            duration = newDuration
            resetControlsTimer()
        }
        .onReceive(coordinator.$isPlaying) { playing in
            isPlaying = playing
        }
    }
    
    private func timeString(from seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func resetControlsTimer() {
        controlsTimer?.invalidate()
        showControls = true
        
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showControls = false
            }
        }
    }
}

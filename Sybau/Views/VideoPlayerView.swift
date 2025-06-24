//
//  VideoPlayerView.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import SwiftUI
import UIKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let mediaItem: MediaItem
    
    func makeUIViewController(context: Context) -> VideoPlayerViewController {
        let controller = VideoPlayerViewController()
        controller.loadMedia(mediaItem)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VideoPlayerViewController, context: Context) {
        // Update if needed
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(mediaItem: MediaItem(
            url: URL(string: "file:///path/to/video.mp4")!,
            title: "Sample Video",
            duration: 3600,
            thumbnail: nil,
            fileSize: 1024 * 1024 * 100,
            lastModified: Date()
        ))
    }
}

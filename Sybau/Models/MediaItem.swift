//
//  MediaItem.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import Foundation
import UIKit

struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let duration: TimeInterval?
    let thumbnail: UIImage?
    let fileSize: Int64?
    let lastModified: Date?
    
    var displayTitle: String {
        return title.isEmpty ? url.lastPathComponent : title
    }
    
    var isVideo: Bool {
        let videoExtensions = ["mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "ogv", "3gp"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }
    
    var isAudio: Bool {
        let audioExtensions = ["mp3", "aac", "wav", "flac", "ogg", "m4a", "wma", "opus"]
        return audioExtensions.contains(url.pathExtension.lowercased())
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "Unknown" }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedFileSize: String {
        guard let fileSize = fileSize else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

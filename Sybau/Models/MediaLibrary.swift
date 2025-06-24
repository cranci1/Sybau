//
//  MediaLibrary.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import Foundation
import UIKit
import AVFoundation

class MediaLibrary: ObservableObject {
    @Published var mediaItems: [MediaItem] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    
    private var fileManager = FileManager.default
    
    func scanForMedia() {
        isScanning = true
        scanProgress = 0.0
        
        Task {
            await scanDirectories()
        }
    }
    
    @MainActor
    private func scanDirectories() async {
        var foundItems: [MediaItem] = []
        
        // Scan common directories
        let searchPaths = [
            fileManager.urls(for: .moviesDirectory, in: .userDomainMask),
            fileManager.urls(for: .musicDirectory, in: .userDomainMask),
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask),
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask)
        ].flatMap { $0 }
        
        let supportedExtensions = [
            // Video formats
            "mp4", "mkv", "avi", "mov", "m4v", "wmv", "flv", "webm", "ogv", "3gp", "mts", "m2ts",
            // Audio formats
            "mp3", "aac", "wav", "flac", "ogg", "m4a", "wma", "opus"
        ]
        
        for (index, searchPath) in searchPaths.enumerated() {
            if let enumerator = fileManager.enumerator(at: searchPath, 
                                                     includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) {
                
                for case let fileURL as URL in enumerator {
                    let pathExtension = fileURL.pathExtension.lowercased()
                    if supportedExtensions.contains(pathExtension) {
                        let mediaItem = await createMediaItem(from: fileURL)
                        foundItems.append(mediaItem)
                    }
                }
            }
            
            scanProgress = Double(index + 1) / Double(searchPaths.count)
        }
        
        mediaItems = foundItems.sorted { $0.displayTitle < $1.displayTitle }
        isScanning = false
    }
    
    @MainActor
    func addMediaItem(from url: URL) {
        Task {
            let mediaItem = await createMediaItem(from: url)
            if !mediaItems.contains(where: { $0.url == url }) {
                mediaItems.append(mediaItem)
                mediaItems.sort { $0.displayTitle < $1.displayTitle }
            }
        }
    }
    
    private func createMediaItem(from url: URL) async -> MediaItem {
        var title = url.deletingPathExtension().lastPathComponent
        var duration: TimeInterval?
        var thumbnail: UIImage?
        var fileSize: Int64?
        var lastModified: Date?
        
        // Get file attributes
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            fileSize = attributes[.size] as? Int64
            lastModified = attributes[.modificationDate] as? Date
        } catch {
            print("Error getting file attributes: \(error)")
        }
        
        // Get media metadata
        let asset = AVAsset(url: url)
        do {
            let assetDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(assetDuration)
            
            // Get title from metadata
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                if let commonKey = item.commonKey,
                   commonKey == .commonKeyTitle,
                   let titleValue = try await item.load(.stringValue),
                   !titleValue.isEmpty {
                    title = titleValue
                    break
                }
            }
            
            // Generate thumbnail for video files
            if url.pathExtension.lowercased() != "mp3" && url.pathExtension.lowercased() != "m4a" {
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 300, height: 300)
                
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let cgImage = try? imageGenerator.copyCGImage(at: time, actualTime: nil) {
                    thumbnail = UIImage(cgImage: cgImage)
                }
            }
        } catch {
            print("Error loading asset metadata: \(error)")
        }
        
        return MediaItem(
            url: url,
            title: title,
            duration: duration,
            thumbnail: thumbnail,
            fileSize: fileSize,
            lastModified: lastModified
        )
    }
}

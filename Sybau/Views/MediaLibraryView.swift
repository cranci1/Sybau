//
//  MediaLibraryView.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct MediaLibraryView: View {
    @StateObject private var mediaLibrary = MediaLibrary()
    @State private var selectedMediaItem: MediaItem?
    @State private var showingVideoPicker = false
    @State private var showingVideoPlayer = false
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .title
    @State private var filterType: MediaFilter = .all
    
    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case dateAdded = "Date Added"
        case duration = "Duration"
        case fileSize = "File Size"
    }
    
    enum MediaFilter: String, CaseIterable {
        case all = "All"
        case videos = "Videos"
        case audio = "Audio"
    }
    
    var filteredAndSortedMedia: [MediaItem] {
        var filtered = mediaLibrary.mediaItems
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.displayTitle.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply media type filter
        switch filterType {
        case .all:
            break
        case .videos:
            filtered = filtered.filter { $0.isVideo }
        case .audio:
            filtered = filtered.filter { $0.isAudio }
        }
        
        // Apply sorting
        switch sortOrder {
        case .title:
            filtered.sort { $0.displayTitle < $1.displayTitle }
        case .dateAdded:
            filtered.sort { ($0.lastModified ?? Date.distantPast) > ($1.lastModified ?? Date.distantPast) }
        case .duration:
            filtered.sort { ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .fileSize:
            filtered.sort { ($0.fileSize ?? 0) > ($1.fileSize ?? 0) }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if mediaLibrary.isScanning {
                    VStack(spacing: 16) {
                        ProgressView(value: mediaLibrary.scanProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text("Scanning for media files...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("\(Int(mediaLibrary.scanProgress * 100))% complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if mediaLibrary.mediaItems.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "tv")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Media Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Tap 'Scan Library' to search for media files, or use 'Add Files' to manually add media.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            Button("Scan Library") {
                                mediaLibrary.scanForMedia()
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Add Files") {
                                showingVideoPicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredAndSortedMedia) { mediaItem in
                            MediaItemRow(mediaItem: mediaItem) {
                                selectedMediaItem = mediaItem
                                showingVideoPlayer = true
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search media...")
                }
                
                Spacer()
            }
            .navigationTitle("Media Library")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Section("Sort by") {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Button(order.rawValue) {
                                    sortOrder = order
                                }
                            }
                        }
                        
                        Section("Filter") {
                            ForEach(MediaFilter.allCases, id: \.self) { filter in
                                Button(filter.rawValue) {
                                    filterType = filter
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    Menu {
                        Button("Scan Library") {
                            mediaLibrary.scanForMedia()
                        }
                        
                        Button("Add Files") {
                            showingVideoPicker = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingVideoPicker,
            allowedContentTypes: [
                .movie, .audio, .mpeg4Movie, .quickTimeMovie,
                UTType(filenameExtension: "mkv") ?? .data,
                UTType(filenameExtension: "avi") ?? .data,
                UTType(filenameExtension: "wmv") ?? .data,
                UTType(filenameExtension: "flv") ?? .data,
                UTType(filenameExtension: "webm") ?? .data
            ],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        mediaLibrary.addMediaItem(from: url)
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            case .failure(let error):
                print("Error selecting files: \(error)")
            }
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let mediaItem = selectedMediaItem {
                VideoPlayerView(mediaItem: mediaItem)
            }
        }
        .onAppear {
            if mediaLibrary.mediaItems.isEmpty && !mediaLibrary.isScanning {
                mediaLibrary.scanForMedia()
            }
        }
    }
}

struct MediaItemRow: View {
    let mediaItem: MediaItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail or icon
                Group {
                    if let thumbnail = mediaItem.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: mediaItem.isVideo ? "tv" : "music.note")
                            .foregroundColor(.secondary)
                            .font(.system(size: 24))
                    }
                }
                .frame(width: 60, height: 60)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .clipped()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(mediaItem.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        if let duration = mediaItem.duration {
                            Label(mediaItem.formattedDuration, systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let fileSize = mediaItem.fileSize {
                            Label(mediaItem.formattedFileSize, systemImage: "doc")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(mediaItem.url.lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MediaLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        MediaLibraryView()
    }
}

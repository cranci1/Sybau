import SwiftUI
import UniformTypeIdentifiers
import UniformTypeIdentifiers
import PhotosUI

struct FilesView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: MediaFile.MediaType? = nil
    @State private var sortOption: DataManager.SortOption = .dateAdded
    @State private var isGridView = true
    @State private var selectedFiles: Set<MediaFile.ID> = []
    @State private var showingImportOptions = false
    @State private var showingBulkActions = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingURLInput = false
    
    private var filteredFiles: [MediaFile] {
        let filtered = dataManager.searchMediaFiles(query: searchText, category: selectedCategory)
        return dataManager.sortMediaFiles(filtered, by: sortOption)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                searchAndFilterBar
                
                // File Grid/List
                if filteredFiles.isEmpty {
                    emptyStateView
                } else {
                    fileContentView
                }
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.large)
            .compatibleNavigationBarItems(
                leading: !selectedFiles.isEmpty ? 
                    Button("Actions") {
                        showingBulkActions = true
                    } : nil,
                trailing: HStack {
                    Button(action: { isGridView.toggle() }) {
                        Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    }
                    
                    Button(action: { showingImportOptions = true }) {
                        Image(systemName: "plus")
                    }
                }
            )
            .actionSheet(isPresented: $showingImportOptions) {
                ActionSheet(
                    title: Text("Import Media"),
                    buttons: [
                        .default(Text("From Photos")) { importFromPhotos() },
                        .default(Text("From Files")) { importFromFiles() },
                        .default(Text("From URL")) { importFromURL() },
                        .cancel()
                    ]
                )
            }
            .actionSheet(isPresented: $showingBulkActions) {
                ActionSheet(
                    title: Text("Actions for \(selectedFiles.count) files"),
                    buttons: [
                        .default(Text("Add to Playlist")) { addSelectedToPlaylist() },
                        .default(Text("Add to Favorites")) { addSelectedToFavorites() },
                        .destructive(Text("Delete")) { deleteSelectedFiles() },
                        .cancel { selectedFiles.removeAll() }
                    ]
                )
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPickerView(onMediaPicked: { url in
                    if let url = url {
                        importMediaFile(from: url)
                    }
                })
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPickerView(onFilePicked: { urls in
                    urls.forEach { importMediaFile(from: $0) }
                })
            }
            .sheet(isPresented: $showingURLInput) {
                URLInputView(onStreamURL: { url in
                    importMediaFile(from: URL(string: url)!)
                })
            }
        }
    }
    
    private var searchAndFilterBar: some View {
        VStack {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            // Filter and Sort Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    // Category Filter
                    Button(action: { selectedCategory = nil }) {
                        Text("All")
                            .foregroundColor(selectedCategory == nil ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == nil ? Color.blue : Color.gray.opacity(0.2))
                            .cornerRadius(15)
                    }
                    
                    ForEach(MediaFile.MediaType.allCases, id: \.self) { category in
                        Button(action: { selectedCategory = category }) {
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.rawValue.capitalized)
                            }
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == category ? Color.blue : Color.gray.opacity(0.2))
                            .cornerRadius(15)
                        }
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Sort Options
                    Menu {
                        ForEach(DataManager.SortOption.allCases, id: \.self) { option in
                            Button(action: { sortOption = option }) {
                                HStack {
                                    Text(option.rawValue)
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOption.rawValue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(15)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var fileContentView: some View {
        ScrollView {
            if isGridView {
                gridView
            } else {
                listView
            }
        }
    }
    
    private var gridView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            ForEach(filteredFiles) { file in
                MediaFileGridItem(
                    file: file,
                    isSelected: selectedFiles.contains(file.id),
                    onTap: { playFile(file) },
                    onLongPress: { toggleSelection(file) }
                )
            }
        }
        .padding()
    }
    
    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredFiles) { file in
                MediaFileListItem(
                    file: file,
                    isSelected: selectedFiles.contains(file.id),
                    onTap: { playFile(file) },
                    onLongPress: { toggleSelection(file) }
                )
                .divider()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Files Found")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Import media files to get started")
                .foregroundColor(.secondary)
            
            Button("Import Files") {
                showingImportOptions = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    private func playFile(_ file: MediaFile) {
        dataManager.currentlyPlaying = file
        dataManager.shouldNavigateToPlayer = true
    }
    
    private func toggleSelection(_ file: MediaFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }
    
    private func importFromPhotos() {
        showingPhotoPicker = true
    }
    
    private func importFromFiles() {
        showingFilePicker = true
    }
    
    private func importFromURL() {
        showingURLInput = true
    }
    
    private func importMediaFile(from url: URL) {
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes?[.size] as? Int64 ?? 0
        
        // Determine media type from file extension
        let mediaType: MediaFile.MediaType
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm":
            mediaType = .video
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma":
            mediaType = .audio
        default:
            mediaType = .document
        }
        
        let mediaFile = MediaFile(
            name: url.lastPathComponent,
            url: url,
            size: fileSize,
            duration: nil, // TODO: Extract duration from media file
            format: pathExtension,
            dateAdded: Date(),
            thumbnailPath: nil,
            type: mediaType
        )
        
        dataManager.addMediaFile(mediaFile)
    }
    
    private func addSelectedToPlaylist() {
        // Implement playlist addition
        print("Add to playlist")
    }
    
    private func addSelectedToFavorites() {
        let filesToAdd = filteredFiles.filter { selectedFiles.contains($0.id) }
        filesToAdd.forEach { dataManager.toggleFavorite($0) }
        selectedFiles.removeAll()
    }
    
    private func deleteSelectedFiles() {
        let filesToDelete = filteredFiles.filter { selectedFiles.contains($0.id) }
        filesToDelete.forEach { dataManager.removeMediaFile($0) }
        selectedFiles.removeAll()
    }
}

// MARK: - Grid Item View
struct MediaFileGridItem: View {
    let file: MediaFile
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(8)
                
                if let thumbnailPath = file.thumbnailPath {
                    AsyncImage(url: URL(fileURLWithPath: thumbnailPath)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: file.type.icon)
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                    .cornerRadius(8)
                    .clipped()
                } else {
                    Image(systemName: file.type.icon)
                        .font(.title)
                        .foregroundColor(.secondary)
                }
                
                // Selection indicator
                if isSelected {
                    Rectangle()
                        .fill(Color.blue.opacity(0.3))
                        .cornerRadius(8)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .background(Color.white)
                                .clipShape(Circle())
                                .padding(4)
                        }
                        Spacer()
                    }
                }
                
                // Duration overlay
                if let duration = file.duration {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(duration))
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(4)
                        }
                    }
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack {
                    Text(formatFileSize(file.size))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(file.format.uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onTapGesture {
            if isSelected {
                onLongPress()
            } else {
                onTap()
            }
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}

// MARK: - List Item View
struct MediaFileListItem: View {
    let file: MediaFile
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        HStack {
            // Thumbnail
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 40)
                    .cornerRadius(6)
                
                if let thumbnailPath = file.thumbnailPath {
                    AsyncImage(url: URL(fileURLWithPath: thumbnailPath)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: file.type.icon)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 60, height: 40)
                    .cornerRadius(6)
                    .clipped()
                } else {
                    Image(systemName: file.type.icon)
                        .foregroundColor(.secondary)
                }
            }
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
                    Text(formatFileSize(file.size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(file.format.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let duration = file.duration {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .onTapGesture {
            if isSelected {
                onLongPress()
            } else {
                onTap()
            }
        }
        .onLongPressGesture {
            onLongPress()
        }
    }
}

// MARK: - Photo Picker View
struct PhotoPickerView: UIViewControllerRepresentable {
    let onMediaPicked: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0 // Allow multiple selection
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerView
        
        init(_ parent: PhotoPickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            for result in results {
                let provider = result.itemProvider
                
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                        DispatchQueue.main.async {
                            if let url = url {
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                                try? FileManager.default.copyItem(at: url, to: tempURL)
                                self.parent.onMediaPicked(tempURL)
                            }
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                        DispatchQueue.main.async {
                            if let url = url {
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                                try? FileManager.default.copyItem(at: url, to: tempURL)
                                self.parent.onMediaPicked(tempURL)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Document Picker View
struct DocumentPickerView: UIViewControllerRepresentable {
    let onFilePicked: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType.audiovisualContent, UTType.audio, UTType.movie, UTType.video]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onFilePicked(urls)
        }
    }
}

// MARK: - URL Input View
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

private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

// MARK: - View Extension
extension View {
    func divider() -> some View {
        VStack(spacing: 0) {
            self
            Divider()
                .padding(.leading, 76)
        }
    }
}

#Preview {
    FilesView()
}

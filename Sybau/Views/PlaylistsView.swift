import SwiftUI

struct PlaylistsView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var showingCreatePlaylist = false
    @State private var showingPlaylistDetail = false
    @State private var selectedPlaylist: Playlist?
    @State private var searchText = ""
    
    private var filteredPlaylists: [Playlist] {
        if searchText.isEmpty {
            return dataManager.playlists
        } else {
            return dataManager.playlists.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                if !dataManager.playlists.isEmpty {
                    searchBar
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Special Collections
                        specialCollectionsView
                        
                        // User Playlists
                        if !filteredPlaylists.isEmpty {
                            userPlaylistsView
                        }
                        
                        // Empty State
                        if dataManager.playlists.isEmpty {
                            emptyStateView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingCreatePlaylist = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreatePlaylist) {
                CreatePlaylistView()
            }
            .sheet(isPresented: $showingPlaylistDetail) {
                if let playlist = selectedPlaylist {
                    PlaylistDetailView(playlist: playlist)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search playlists...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var specialCollectionsView: some View {
        VStack(spacing: 16) {
            Text("Collections")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                SpecialPlaylistCard(
                    title: "Recently Played",
                    subtitle: "\(dataManager.recentlyPlayed.count) items",
                    icon: "clock",
                    color: .blue,
                    items: dataManager.recentlyPlayed
                ) {
                    // Show recently played
                }
                
                SpecialPlaylistCard(
                    title: "Favorites",
                    subtitle: "\(dataManager.favorites.count) items",
                    icon: "heart.fill",
                    color: .red,
                    items: dataManager.favorites
                ) {
                    // Show favorites
                }
                
                SpecialPlaylistCard(
                    title: "Most Played",
                    subtitle: "\(dataManager.mostPlayed.count) items",
                    icon: "chart.bar",
                    color: .green,
                    items: dataManager.mostPlayed
                ) {
                    // Show most played
                }
                
                SpecialPlaylistCard(
                    title: "Downloaded",
                    subtitle: "0 items",
                    icon: "arrow.down.circle",
                    color: .orange,
                    items: []
                ) {
                    // Show downloaded
                }
            }
        }
    }
    
    private var userPlaylistsView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("My Playlists")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Create") {
                    showingCreatePlaylist = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(filteredPlaylists) { playlist in
                    PlaylistRow(playlist: playlist) {
                        selectedPlaylist = playlist
                        showingPlaylistDetail = true
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Playlists Yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Create your first playlist to organize your media")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Create Playlist") {
                showingCreatePlaylist = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Special Playlist Card
struct SpecialPlaylistCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let items: [MediaFile]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Preview thumbnails
                HStack(spacing: 4) {
                    ForEach(items.prefix(3)) { item in
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 30, height: 20)
                            .cornerRadius(4)
                            .overlay(
                                Image(systemName: item.type.icon)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    if items.count > 3 {
                        Text("+\(items.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Playlist Row
struct PlaylistRow: View {
    let playlist: Playlist
    let action: () -> Void
    
    var body: some View {
        HStack {
            // Playlist thumbnail
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                
                if let firstItem = playlist.mediaFiles.first {
                    Image(systemName: firstItem.type.icon)
                        .font(.title2)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                // Smart playlist indicator
                if playlist.isSmartPlaylist {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "gear")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .background(Color.white)
                                .clipShape(Circle())
                                .padding(2)
                        }
                        Spacer()
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if let description = playlist.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Text("\(playlist.mediaFiles.count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Modified \(playlist.dateModified, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Create Playlist View
struct CreatePlaylistView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var dataManager = DataManager.shared
    @State private var name = ""
    @State private var description = ""
    @State private var isSmartPlaylist = false
    @State private var selectedMediaType: MediaFile.MediaType?
    @State private var minDuration: Double = 0
    @State private var maxDuration: Double = 3600
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Playlist Info")) {
                    TextField("Playlist Name", text: $name)
                    TextField("Description (Optional)", text: $description)
                }
                
                Section(header: Text("Playlist Type")) {
                    Toggle("Smart Playlist", isOn: $isSmartPlaylist)
                    
                    if isSmartPlaylist {
                        Text("Smart playlists automatically include files based on criteria")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if isSmartPlaylist {
                    Section(header: Text("Smart Criteria")) {
                        Picker("Media Type", selection: $selectedMediaType) {
                            Text("All Types").tag(MediaFile.MediaType?.none)
                            ForEach(MediaFile.MediaType.allCases, id: \.self) { type in
                                Text(type.rawValue.capitalized).tag(type as MediaFile.MediaType?)
                            }
                        }
                        
                        VStack {
                            Text("Duration Range")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack {
                                Text("Min: \(Int(minDuration/60))m")
                                Slider(value: $minDuration, in: 0...7200, step: 60)
                                Text("Max: \(Int(maxDuration/60))m")
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createPlaylist()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createPlaylist() {
        let smartCriteria = isSmartPlaylist ? Playlist.SmartCriteria(
            genre: nil,
            dateRange: nil,
            mediaType: selectedMediaType,
            minDuration: minDuration > 0 ? minDuration : nil,
            maxDuration: maxDuration < 3600 ? maxDuration : nil
        ) : nil
        
        let playlist = Playlist(
            name: name,
            description: description.isEmpty ? nil : description,
            mediaFiles: [],
            dateCreated: Date(),
            dateModified: Date(),
            isSmartPlaylist: isSmartPlaylist,
            smartCriteria: smartCriteria
        )
        
        dataManager.playlists.append(playlist)
        dataManager.saveData()
        
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Playlist Detail View
struct PlaylistDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var dataManager = DataManager.shared
    @State var playlist: Playlist
    @State private var isEditing = false
    @State private var showingAddFiles = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Playlist Header
                VStack(spacing: 16) {
                    // Playlist artwork
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .cornerRadius(16)
                        
                        if let firstItem = playlist.mediaFiles.first {
                            Image(systemName: firstItem.type.icon)
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                        }
                        
                        if playlist.isSmartPlaylist {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "gear")
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                        .background(Color.white)
                                        .clipShape(Circle())
                                        .padding(4)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    VStack(spacing: 8) {
                        Text(playlist.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        if let description = playlist.description {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        HStack {
                            Text("\(playlist.mediaFiles.count) items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Created \(playlist.dateCreated, style: .date)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: playAll) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play All")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(playlist.mediaFiles.isEmpty)
                        
                        Button(action: shufflePlay) {
                            HStack {
                                Image(systemName: "shuffle")
                                Text("Shuffle")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                        }
                        .disabled(playlist.mediaFiles.isEmpty)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                
                // Files List
                if playlist.mediaFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No files in this playlist")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button("Add Files") {
                            showingAddFiles = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(playlist.mediaFiles) { file in
                            PlaylistFileRow(file: file) {
                                playFile(file)
                            }
                        }
                        .onDelete(perform: deleteFiles)
                        .onMove(perform: moveFiles)
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Edit Playlist") {
                            isEditing = true
                        }
                        
                        Button("Add Files") {
                            showingAddFiles = true
                        }
                        
                        Button("Share Playlist") {
                            sharePlaylist()
                        }
                        
                        Button("Delete Playlist", role: .destructive) {
                            deletePlaylist()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .sheet(isPresented: $showingAddFiles) {
                AddFilesToPlaylistView(playlist: playlist)
            }
        }
    }
    
    private func playAll() {
        guard let firstFile = playlist.mediaFiles.first else { return }
        playFile(firstFile)
    }
    
    private func shufflePlay() {
        let shuffledFiles = playlist.mediaFiles.shuffled()
        guard let firstFile = shuffledFiles.first else { return }
        playFile(firstFile)
    }
    
    private func playFile(_ file: MediaFile) {
        dataManager.addToRecentlyPlayed(file)
        // Navigate to player
        print("Playing file: \(file.name)")
    }
    
    private func deleteFiles(at offsets: IndexSet) {
        playlist.mediaFiles.remove(atOffsets: offsets)
        updatePlaylist()
    }
    
    private func moveFiles(from source: IndexSet, to destination: Int) {
        playlist.mediaFiles.move(fromOffsets: source, toOffset: destination)
        updatePlaylist()
    }
    
    private func updatePlaylist() {
        playlist.dateModified = Date()
        if let index = dataManager.playlists.firstIndex(where: { $0.id == playlist.id }) {
            dataManager.playlists[index] = playlist
            dataManager.saveData()
        }
    }
    
    private func sharePlaylist() {
        // Implement playlist sharing
        print("Share playlist: \(playlist.name)")
    }
    
    private func deletePlaylist() {
        dataManager.deletePlaylist(playlist)
        presentationMode.wrappedValue.dismiss()
    }
}

// MARK: - Playlist File Row
struct PlaylistFileRow: View {
    let file: MediaFile
    let action: () -> Void
    
    var body: some View {
        HStack {
            // File thumbnail
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .cornerRadius(8)
                
                Image(systemName: file.type.icon)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack {
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
            
            Button(action: action) {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Files to Playlist View
struct AddFilesToPlaylistView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var dataManager = DataManager.shared
    let playlist: Playlist
    @State private var selectedFiles: Set<MediaFile.ID> = []
    
    private var availableFiles: [MediaFile] {
        dataManager.mediaFiles.filter { file in
            !playlist.mediaFiles.contains { $0.id == file.id }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if availableFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No files available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("All your files are already in this playlist")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(availableFiles) { file in
                        HStack {
                            Button(action: { toggleSelection(file) }) {
                                Image(systemName: selectedFiles.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedFiles.contains(file.id) ? .blue : .secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack {
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
                        }
                        .onTapGesture {
                            toggleSelection(file)
                        }
                    }
                }
            }
            .navigationTitle("Add Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedFiles.count))") {
                        addSelectedFiles()
                    }
                    .disabled(selectedFiles.isEmpty)
                }
            }
        }
    }
    
    private func toggleSelection(_ file: MediaFile) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
    }
    
    private func addSelectedFiles() {
        let filesToAdd = availableFiles.filter { selectedFiles.contains($0.id) }
        filesToAdd.forEach { file in
            dataManager.addToPlaylist(file, playlist: playlist)
        }
        presentationMode.wrappedValue.dismiss()
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

#Preview {
    PlaylistsView()
}

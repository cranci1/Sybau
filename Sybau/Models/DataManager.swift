import Foundation
import SwiftUI
import Combine

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    @Published var mediaFiles: [MediaFile] = []
    @Published var playlists: [Playlist] = []
    @Published var streamSources: [StreamSource] = []
    @Published var settings: AppSettings = AppSettings()
    @Published var recentlyPlayed: [MediaFile] = []
    @Published var favorites: [MediaFile] = []
    @Published var mostPlayed: [MediaFile] = []
    @Published var currentlyPlaying: MediaFile?
    @Published var shouldNavigateToPlayer = false
    
    private let userDefaults = UserDefaults.standard
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    private init() {
        loadData()
        createDefaultPlaylists()
    }
    
    // MARK: - Data Persistence
    func saveData() {
        saveMediaFiles()
        savePlaylists()
        saveStreamSources()
        saveSettings()
        saveRecentlyPlayed()
        saveFavorites()
        saveMostPlayed()
    }
    
    func loadData() {
        loadMediaFiles()
        loadPlaylists()
        loadStreamSources()
        loadSettings()
        loadRecentlyPlayed()
        loadFavorites()
        loadMostPlayed()
    }
    
    private func saveMediaFiles() {
        if let encoded = try? JSONEncoder().encode(mediaFiles) {
            userDefaults.set(encoded, forKey: "mediaFiles")
        }
    }
    
    private func loadMediaFiles() {
        if let data = userDefaults.data(forKey: "mediaFiles"),
           let decoded = try? JSONDecoder().decode([MediaFile].self, from: data) {
            mediaFiles = decoded
        }
    }
    
    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            userDefaults.set(encoded, forKey: "playlists")
        }
    }
    
    private func loadPlaylists() {
        if let data = userDefaults.data(forKey: "playlists"),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }
    
    private func saveStreamSources() {
        if let encoded = try? JSONEncoder().encode(streamSources) {
            userDefaults.set(encoded, forKey: "streamSources")
        }
    }
    
    private func loadStreamSources() {
        if let data = userDefaults.data(forKey: "streamSources"),
           let decoded = try? JSONDecoder().decode([StreamSource].self, from: data) {
            streamSources = decoded
        }
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: "settings")
        }
    }
    
    private func loadSettings() {
        if let data = userDefaults.data(forKey: "settings"),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }
    }
    
    private func saveRecentlyPlayed() {
        if let encoded = try? JSONEncoder().encode(recentlyPlayed) {
            userDefaults.set(encoded, forKey: "recentlyPlayed")
        }
    }
    
    private func loadRecentlyPlayed() {
        if let data = userDefaults.data(forKey: "recentlyPlayed"),
           let decoded = try? JSONDecoder().decode([MediaFile].self, from: data) {
            recentlyPlayed = decoded
        }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            userDefaults.set(encoded, forKey: "favorites")
        }
    }
    
    private func loadFavorites() {
        if let data = userDefaults.data(forKey: "favorites"),
           let decoded = try? JSONDecoder().decode([MediaFile].self, from: data) {
            favorites = decoded
        }
    }
    
    private func saveMostPlayed() {
        if let encoded = try? JSONEncoder().encode(mostPlayed) {
            userDefaults.set(encoded, forKey: "mostPlayed")
        }
    }
    
    private func loadMostPlayed() {
        if let data = userDefaults.data(forKey: "mostPlayed"),
           let decoded = try? JSONDecoder().decode([MediaFile].self, from: data) {
            mostPlayed = decoded
        }
    }
    
    // MARK: - Media File Management
    func addMediaFile(_ file: MediaFile) {
        mediaFiles.append(file)
        saveMediaFiles()
    }
    
    func removeMediaFile(_ file: MediaFile) {
        mediaFiles.removeAll { $0.id == file.id }
        saveMediaFiles()
    }
    
    func addToRecentlyPlayed(_ file: MediaFile) {
        recentlyPlayed.removeAll { $0.id == file.id }
        recentlyPlayed.insert(file, at: 0)
        if recentlyPlayed.count > 50 {
            recentlyPlayed.removeLast()
        }
        saveRecentlyPlayed()
    }
    
    func toggleFavorite(_ file: MediaFile) {
        if favorites.contains(where: { $0.id == file.id }) {
            favorites.removeAll { $0.id == file.id }
        } else {
            favorites.append(file)
        }
        saveFavorites()
    }
    
    func isFavorite(_ file: MediaFile) -> Bool {
        favorites.contains { $0.id == file.id }
    }
    
    // MARK: - Playlist Management
    func createPlaylist(name: String, description: String? = nil) {
        let playlist = Playlist(
            name: name,
            description: description,
            mediaFiles: [],
            dateCreated: Date(),
            dateModified: Date(),
            isSmartPlaylist: false,
            smartCriteria: nil
        )
        playlists.append(playlist)
        savePlaylists()
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }
    
    func addToPlaylist(_ file: MediaFile, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].mediaFiles.append(file)
        playlists[index].dateModified = Date()
        savePlaylists()
    }
    
    func removeFromPlaylist(_ file: MediaFile, playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].mediaFiles.removeAll { $0.id == file.id }
        playlists[index].dateModified = Date()
        savePlaylists()
    }
    
    // MARK: - Stream Source Management
    func addStreamSource(_ source: StreamSource) {
        streamSources.append(source)
        saveStreamSources()
    }
    
    func removeStreamSource(_ source: StreamSource) {
        streamSources.removeAll { $0.id == source.id }
        saveStreamSources()
    }
    
    // MARK: - Default Data
    private func createDefaultPlaylists() {
        if playlists.isEmpty {
            createPlaylist(name: "Recently Played", description: "Your recently played videos")
            createPlaylist(name: "Favorites", description: "Your favorite videos")
            createPlaylist(name: "Most Played", description: "Your most played videos")
        }
    }
    
    // MARK: - Search and Filter
    func searchMediaFiles(query: String, category: MediaFile.MediaType? = nil) -> [MediaFile] {
        var results = mediaFiles
        
        if let category = category {
            results = results.filter { $0.type == category }
        }
        
        if !query.isEmpty {
            results = results.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        
        return results
    }
    
    func sortMediaFiles(_ files: [MediaFile], by sortOption: SortOption) -> [MediaFile] {
        switch sortOption {
        case .name:
            return files.sorted { $0.name < $1.name }
        case .dateAdded:
            return files.sorted { $0.dateAdded > $1.dateAdded }
        case .size:
            return files.sorted { $0.size > $1.size }
        case .duration:
            return files.sorted { ($0.duration ?? 0) > ($1.duration ?? 0) }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateAdded = "Date Added"
        case size = "Size"
        case duration = "Duration"
    }
}

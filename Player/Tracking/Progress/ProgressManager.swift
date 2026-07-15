//
//  ProgressManager.swift
//  Sybau
//

import Foundation
import AVFoundation

// MARK: - Data Models

public struct ProgressData: Codable {
    var movieProgress: [MovieProgressEntry] = []
    var episodeProgress: [EpisodeProgressEntry] = []
    
    mutating func updateMovie(_ entry: MovieProgressEntry) {
        if let index = movieProgress.firstIndex(where: { $0.id == entry.id }) {
            movieProgress[index] = entry
        } else {
            movieProgress.append(entry)
        }
    }
    
    mutating func updateEpisode(_ entry: EpisodeProgressEntry) {
        if let index = episodeProgress.firstIndex(where: { $0.id == entry.id }) {
            episodeProgress[index] = entry
        } else {
            episodeProgress.append(entry)
        }
    }
    
    func findMovie(id: Int) -> MovieProgressEntry? {
        movieProgress.first { $0.id == id }
    }
    
    func findEpisode(showId: Int, season: Int, episode: Int) -> EpisodeProgressEntry? {
        episodeProgress.first {
            $0.showId == showId && $0.seasonNumber == season && $0.episodeNumber == episode
        }
    }
}

public struct MovieProgressEntry: Codable, Identifiable {
    public let id: Int
    public let title: String
    public var currentTime: Double = 0
    public var totalDuration: Double = 0
    public var isWatched: Bool = false
    public var lastUpdated: Date = Date()
    
    public var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(currentTime / totalDuration, 1.0)
    }
    
    public init(id: Int, title: String, currentTime: Double = 0, totalDuration: Double = 0, isWatched: Bool = false, lastUpdated: Date = Date()) {
        self.id = id
        self.title = title
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.isWatched = isWatched
        self.lastUpdated = lastUpdated
    }
}

public struct EpisodeProgressEntry: Codable, Identifiable {
    public let id: String
    public let showId: Int
    public var showTitle: String?
    public let seasonNumber: Int
    public let episodeNumber: Int
    public var currentTime: Double = 0
    public var totalDuration: Double = 0
    public var isWatched: Bool = false
    public var lastUpdated: Date = Date()
    
    public var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(currentTime / totalDuration, 1.0)
    }
    
    public init(showId: Int, seasonNumber: Int, episodeNumber: Int, showTitle: String? = nil, currentTime: Double = 0, totalDuration: Double = 0, isWatched: Bool = false, lastUpdated: Date = Date()) {
        self.id = "ep_\(showId)_s\(seasonNumber)_e\(episodeNumber)"
        self.showId = showId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.showTitle = showTitle
        self.currentTime = currentTime
        self.totalDuration = totalDuration
        self.isWatched = isWatched
        self.lastUpdated = lastUpdated
    }
}

// MARK: - ProgressManager

public final class ProgressManager {
    public static let shared = ProgressManager()
    
    private let fileManager = FileManager.default
    private var progressData: ProgressData = ProgressData()
    private let progressFileURL: URL
    private let saveThrottleInterval: TimeInterval = 5.0
    private var throttleTask: Task<Void, Never>?
    private var isThrottleScheduled = false
    private var hasPendingChanges = false
    
    private let accessQueue = DispatchQueue(label: "com.sybau.progress-manager", attributes: .concurrent)
    
    private static let documentsDirectory =
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    private init() {
        self.progressFileURL = Self.documentsDirectory
            .appendingPathComponent("ProgressData.json")
        loadProgressData()
    }
    
    // MARK: - Data Persistence
    
    private func loadProgressData() {
        guard fileManager.fileExists(atPath: progressFileURL.path) else {
            Logger.shared.log("Progress file not found, initializing new data", type: "Progress")
            return
        }
        
        do {
            let data = try Data(contentsOf: progressFileURL)
            let decoded = try JSONDecoder().decode(ProgressData.self, from: data)
            accessQueue.async(flags: .barrier) { [weak self] in
                self?.progressData = decoded
            }
            Logger.shared.log(
                "Progress data loaded (\(decoded.movieProgress.count) movies, \(decoded.episodeProgress.count) episodes)", type: "Progress")
        } catch {
            Logger.shared.log("Failed to load progress data: \(error.localizedDescription)", type: "Error")
        }
    }
    
    private func saveProgressData() {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let snapshot = self.progressData
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: self.progressFileURL, options: .atomic)
            } catch {
                Logger.shared.log("Failed to save progress data: \(error.localizedDescription)", type: "Error")
            }
        }
    }
    
    private func saveProgressDataSync() {
        accessQueue.sync(flags: .barrier) {
            let snapshot = self.progressData
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: self.progressFileURL, options: .atomic)
                Logger.shared.log("Progress data flushed successfully", type: "Progress")
            } catch {
                Logger.shared.log("Failed to flush progress data: \(error.localizedDescription)", type: "Error")
            }
        }
    }
    
    private func throttledSave() {
        hasPendingChanges = true
        guard !isThrottleScheduled else { return }
        isThrottleScheduled = true
        throttleTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.saveThrottleInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.isThrottleScheduled = false
            if self.hasPendingChanges {
                self.hasPendingChanges = false
                self.saveProgressData()
            }
        }
    }
    
    @discardableResult
    public func flushPendingSave() -> Bool {
        throttleTask?.cancel()
        throttleTask = nil
        isThrottleScheduled = false
        guard hasPendingChanges else { return false }
        hasPendingChanges = false
        saveProgressDataSync()
        return true
    }
    
    // MARK: - Movie Progress
    
    public func updateMovieProgress(movieId: Int, title: String, currentTime: Double, totalDuration: Double) {
        guard currentTime >= 0, totalDuration > 0, currentTime <= totalDuration else {
            Logger.shared.log("Invalid progress for movie \(title): currentTime=\(currentTime), totalDuration=\(totalDuration)", type: "Warning")
            return
        }
        
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            var entry = self.progressData.findMovie(id: movieId)
            ?? MovieProgressEntry(id: movieId, title: title)
            entry.currentTime = currentTime
            entry.totalDuration = totalDuration
            entry.lastUpdated = Date()
            if entry.progress >= 0.95 { entry.isWatched = true }
            self.progressData.updateMovie(entry)
        }
        throttledSave()
        
        let progress = min(currentTime / totalDuration, 1.0)
        Task { @MainActor in
            ProgressSyncManager.shared.pushMovieProgress(
                tmdbId: movieId, title: title, progress: progress)
        }
    }
    
    public func getMovieProgress(movieId: Int, title: String) -> Double {
        accessQueue.sync { progressData.findMovie(id: movieId)?.progress ?? 0.0 }
    }
    
    public func getMovieCurrentTime(movieId: Int, title: String) -> Double {
        accessQueue.sync { progressData.findMovie(id: movieId)?.currentTime ?? 0.0 }
    }
    
    public func isMovieWatched(movieId: Int, title: String) -> Bool {
        accessQueue.sync {
            guard let entry = progressData.findMovie(id: movieId) else { return false }
            return entry.isWatched || entry.progress >= 0.95
        }
    }
    
    public func markMovieAsWatched(movieId: Int, title: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if var entry = self.progressData.findMovie(id: movieId) {
                entry.isWatched = true
                entry.currentTime = entry.totalDuration
                entry.lastUpdated = Date()
                self.progressData.updateMovie(entry)
                Logger.shared.log("Marked movie as watched: \(title)", type: "Progress")
            }
        }
        saveProgressData()
    }
    
    public func resetMovieProgress(movieId: Int, title: String) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if var entry = self.progressData.findMovie(id: movieId) {
                entry.currentTime = 0
                entry.isWatched = false
                entry.lastUpdated = Date()
                self.progressData.updateMovie(entry)
                Logger.shared.log("Reset movie progress: \(title)", type: "Progress")
            }
        }
        saveProgressData()
    }
    
    // MARK: - Episode Progress
    
    public func updateEpisodeProgress(showId: Int, showTitle: String? = nil, seasonNumber: Int, episodeNumber: Int, currentTime: Double, totalDuration: Double) {
        guard currentTime >= 0, totalDuration > 0, currentTime <= totalDuration else {
            Logger.shared.log( "Invalid progress for S\(seasonNumber)E\(episodeNumber): currentTime=\(currentTime), totalDuration=\(totalDuration)", type: "Warning")
            return
        }
        
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)
            ?? EpisodeProgressEntry(showId: showId, seasonNumber: seasonNumber, episodeNumber: episodeNumber)
            if let showTitle, !showTitle.isEmpty { entry.showTitle = showTitle }
            entry.currentTime = currentTime
            entry.totalDuration = totalDuration
            entry.lastUpdated = Date()
            if entry.progress >= 0.95 { entry.isWatched = true }
            self.progressData.updateEpisode(entry)
        }
        throttledSave()
        
        let progress = min(currentTime / totalDuration, 1.0)
        Task { @MainActor in
            ProgressSyncManager.shared.pushEpisodeProgress(
                showId: showId, showTitle: showTitle,
                seasonNumber: seasonNumber, episodeNumber: episodeNumber,
                progress: progress)
        }
    }
    
    public func getEpisodeProgress(showId: Int, seasonNumber: Int, episodeNumber: Int) -> Double {
        accessQueue.sync {
            progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)?.progress ?? 0.0
        }
    }
    
    public func getEpisodeCurrentTime(showId: Int, seasonNumber: Int, episodeNumber: Int) -> Double {
        accessQueue.sync {
            progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber)?.currentTime ?? 0.0
        }
    }
    
    public func isEpisodeWatched(showId: Int, seasonNumber: Int, episodeNumber: Int) -> Bool {
        accessQueue.sync {
            guard let entry = progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber) else { return false }
            return entry.isWatched || entry.progress >= 0.95
        }
    }
    
    public func markEpisodeAsWatched(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber) {
                entry.isWatched = true
                entry.currentTime = entry.totalDuration
                entry.lastUpdated = Date()
                self.progressData.updateEpisode(entry)
                Logger.shared.log("Marked episode as watched: S\(seasonNumber)E\(episodeNumber)", type: "Progress")
            }
        }
        saveProgressData()
    }
    
    public func resetEpisodeProgress(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: episodeNumber) {
                entry.currentTime = 0
                entry.isWatched = false
                entry.lastUpdated = Date()
                self.progressData.updateEpisode(entry)
                Logger.shared.log("Reset episode progress: S\(seasonNumber)E\(episodeNumber)", type: "Progress")
            }
        }
        saveProgressData()
    }
    
    public func markPreviousEpisodesAsWatched(showId: Int, seasonNumber: Int, episodeNumber: Int) {
        guard episodeNumber > 1 else { return }
        accessQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            for e in 1..<episodeNumber {
                if var entry = self.progressData.findEpisode(showId: showId, season: seasonNumber, episode: e) {
                    entry.isWatched = true
                    entry.currentTime = entry.totalDuration
                    entry.lastUpdated = Date()
                    self.progressData.updateEpisode(entry)
                }
            }
            Logger.shared.log("Marked previous episodes as watched for S\(seasonNumber) up to E\(episodeNumber - 1)", type: "Progress"
            )
        }
        saveProgressData()
    }
    
    // MARK: - AVPlayer Extension
    
    public func addPeriodicTimeObserver(to player: AVPlayer, for mediaInfo: MediaInfo) -> Any? {
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        return player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let currentItem = player.currentItem,
                  currentItem.duration.seconds.isFinite,
                  currentItem.duration.seconds > 0 else { return }
            
            let currentTime = time.seconds
            let duration = currentItem.duration.seconds
            guard currentTime >= 0, currentTime <= duration else { return }
            
            switch mediaInfo {
            case .movie(let id, let title):
                self.updateMovieProgress(movieId: id, title: title, currentTime: currentTime, totalDuration: duration)
            case .episode(let showId, let showTitle, let seasonNumber, let episodeNumber):
                self.updateEpisodeProgress(showId: showId, showTitle: showTitle, seasonNumber: seasonNumber, episodeNumber: episodeNumber, currentTime: currentTime, totalDuration: duration)
            }
        }
    }
}

// MARK: - MediaInfo Enum

public enum MediaInfo {
    case movie(id: Int, title: String)
    case episode(showId: Int, showTitle: String?, seasonNumber: Int, episodeNumber: Int)
}

// MARK: - Continue Watching

public struct ContinueWatchingItem: Identifiable {
    public let id: String
    public let tmdbId: Int
    public let title: String
    public let isMovie: Bool
    public let progress: Double
    public let currentTime: Double
    public let totalDuration: Double
    public let lastUpdated: Date
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    
    public var remainingTime: String {
        let remaining = totalDuration - currentTime
        let minutes = Int(remaining) / 60
        if minutes < 60 {
            return "\(minutes)m left"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m left"
        }
    }
    
    public var formattedProgress: String { "\(Int(progress * 100))%" }
    
    public init(id: String, tmdbId: Int, title: String, isMovie: Bool, progress: Double, currentTime: Double, totalDuration: Double, lastUpdated: Date, seasonNumber: Int?, episodeNumber: Int?) {
        self.id = id; self.tmdbId = tmdbId; self.title = title; self.isMovie = isMovie
        self.progress = progress; self.currentTime = currentTime
        self.totalDuration = totalDuration; self.lastUpdated = lastUpdated
        self.seasonNumber = seasonNumber; self.episodeNumber = episodeNumber
    }
}

extension ProgressManager {
    public func getContinueWatchingItems(limit: Int = 10) -> [ContinueWatchingItem] {
        var items: [ContinueWatchingItem] = []
        accessQueue.sync {
            let movies = self.progressData.movieProgress
                .filter { !$0.isWatched && $0.progress > 0.02 && $0.progress < 0.95 }
                .map { movie in
                    ContinueWatchingItem(
                        id: "movie_\(movie.id)", tmdbId: movie.id, title: movie.title,
                        isMovie: true, progress: movie.progress,
                        currentTime: movie.currentTime, totalDuration: movie.totalDuration,
                        lastUpdated: movie.lastUpdated, seasonNumber: nil, episodeNumber: nil
                    )
                }
            let episodes = self.progressData.episodeProgress
                .filter { !$0.isWatched && $0.progress > 0.02 && $0.progress < 0.95 }
                .map { ep in
                    ContinueWatchingItem(
                        id: ep.id, tmdbId: ep.showId,
                        title: "S\(ep.seasonNumber)E\(ep.episodeNumber)",
                        isMovie: false, progress: ep.progress,
                        currentTime: ep.currentTime, totalDuration: ep.totalDuration,
                        lastUpdated: ep.lastUpdated,
                        seasonNumber: ep.seasonNumber, episodeNumber: ep.episodeNumber
                    )
                }
            items = (movies + episodes).sorted { $0.lastUpdated > $1.lastUpdated }
        }
        return Array(items.prefix(limit))
    }
}

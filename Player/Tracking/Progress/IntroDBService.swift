//
//  IntroDBService.swift
//  Sybau
//

import UIKit

public enum IntroDbSegment: String {
    case intro
    case recap
    case credits
    case preview
    
    public var title: String {
        switch self {
        case .intro:
            return "Intro"
        case .recap:
            return "Recap"
        case .credits:
            return "Credits"
        case .preview:
            return "Preview"
        }
    }
    
    public var priority: Int {
        switch self {
        case .recap:
            return 0
        case .intro:
            return 1
        case .preview:
            return 2
        case .credits:
            return 3
        }
    }
    
    public var uiColor: UIColor {
        switch self {
        case .intro:
            return UIColor.systemBlue
        case .recap:
            return UIColor.systemOrange
        case .credits:
            return UIColor.systemPurple
        case .preview:
            return UIColor.systemTeal
        }
    }
}

public struct IntroDBSegment {
    public let db: IntroDbSegment
    public let startSeconds: Double
    public let endSeconds: Double?
    public let confidence: Double
    public let submissionCount: Int
    
    public var id: String {
        let end = endSeconds.map { String(format: "%.3f", $0) } ?? "nil"
        return "\(db.rawValue)-\(String(format: "%.3f", startSeconds))-\(end)"
    }
    
    public func resolvedEnd(duration: Double) -> Double? {
        if let endSeconds {
            return endSeconds
        }
        guard duration > 0, duration.isFinite else {
            return nil
        }
        return duration
    }
    
    public init(db: IntroDbSegment, startSeconds: Double, endSeconds: Double?, confidence: Double, submissionCount: Int) {
        self.db = db
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.confidence = confidence
        self.submissionCount = submissionCount
    }
}

public struct IntroDBSegmentHighlight {
    public let start: Double
    public let end: Double
    public let color: UIColor
    public let label: String
    
    public init(start: Double, end: Double, color: UIColor, label: String) {
        self.start = start
        self.end = end
        self.color = color
        self.label = label
    }
}

public final class IntroDBService {
    public static let shared = IntroDBService()
    
    private init() {}
    
    public func fetchSegments(for mediaInfo: MediaInfo, completion: @escaping (Result<[IntroDBSegment], Error>) -> Void) {
        var components = URLComponents(string: "https://api.theintrodb.org/v2/media")
        var queryItems: [URLQueryItem] = []
        
        switch mediaInfo {
        case .movie(let id, _):
            queryItems.append(URLQueryItem(name: "tmdb_id", value: String(id)))
        case .episode(let showId, _, let seasonNumber, let episodeNumber):
            queryItems.append(URLQueryItem(name: "tmdb_id", value: String(showId)))
            queryItems.append(URLQueryItem(name: "season", value: String(seasonNumber)))
            queryItems.append(URLQueryItem(name: "episode", value: String(episodeNumber)))
        }
        
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "IntroDBService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to build IntroDB URL"])))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(.failure(NSError(domain: "IntroDBService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "IntroDB returned status \(http.statusCode)"])))
                return
            }
            
            guard let data else {
                completion(.failure(NSError(domain: "IntroDBService", code: -2, userInfo: [NSLocalizedDescriptionKey: "IntroDB response is empty"])))
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(IntroDBResponse.self, from: data)
                completion(.success(self.makeSegments(from: decoded)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    public func highlights(for segments: [IntroDBSegment], duration: Double) -> [IntroDBSegmentHighlight] {
        guard duration > 0, duration.isFinite else { return [] }
        
        return segments.compactMap { segment in
            guard segment.startSeconds.isFinite else { return nil }
            let end = segment.resolvedEnd(duration: duration) ?? duration
            let clampedStart = max(0, min(segment.startSeconds, duration))
            let clampedEnd = max(0, min(end, duration))
            guard clampedEnd > clampedStart else { return nil }
            
            return IntroDBSegmentHighlight(
                start: clampedStart,
                end: clampedEnd,
                color: segment.db.uiColor,
                label: segment.db.title
            )
        }
    }
    
    public func activeSegment(at position: Double, in segments: [IntroDBSegment], duration: Double?) -> IntroDBSegment? {
        let resolvedDuration = duration ?? 0
        
        return segments
            .sorted {
                if $0.db.priority == $1.db.priority {
                    return $0.confidence > $1.confidence
                }
                return $0.db.priority < $1.db.priority
            }
            .first { segment in
                let segmentEnd = segment.resolvedEnd(duration: resolvedDuration)
                let end = segmentEnd ?? .greatestFiniteMagnitude
                return position >= segment.startSeconds && position <= end
            }
    }
    
    private func makeSegments(from response: IntroDBResponse) -> [IntroDBSegment] {
        var result: [IntroDBSegment] = []
        
        func appendEntries(_ entries: [IntroDBResponse.RangeEntry]?, db: IntroDbSegment) {
            guard let entries else { return }
            for entry in entries {
                let start = max(0, Double(entry.startMS ?? 0) / 1000.0)
                let end = entry.endMS.map { max(0, Double($0) / 1000.0) }
                result.append(
                    IntroDBSegment(
                        db: db,
                        startSeconds: start,
                        endSeconds: end,
                        confidence: entry.confidence ?? 0,
                        submissionCount: entry.submissionCount ?? 0
                    )
                )
            }
        }
        
        appendEntries(response.recap, db: .recap)
        appendEntries(response.intro, db: .intro)
        appendEntries(response.preview, db: .preview)
        appendEntries(response.credits, db: .credits)
        
        return result.sorted { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds {
                return lhs.db.priority < rhs.db.priority
            }
            return lhs.startSeconds < rhs.startSeconds
        }
    }
}

private struct IntroDBResponse: Decodable {
    struct RangeEntry: Decodable {
        let startMS: Int?
        let endMS: Int?
        let confidence: Double?
        let submissionCount: Int?
        
        enum CodingKeys: String, CodingKey {
            case startMS = "start_ms"
            case endMS = "end_ms"
            case confidence
            case submissionCount = "submission_count"
        }
    }
    
    let tmdbId: Int
    let type: String?
    let intro: [RangeEntry]?
    let recap: [RangeEntry]?
    let credits: [RangeEntry]?
    let preview: [RangeEntry]?
    
    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case type
        case intro
        case recap
        case credits
        case preview
    }
}

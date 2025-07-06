import Foundation
import SwiftUI

// MARK: - Media File Model
struct MediaFile: Identifiable, Codable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    let duration: TimeInterval?
    let format: String
    let dateAdded: Date
    let thumbnailPath: String?
    let type: MediaType
    
    enum MediaType: String, CaseIterable, Codable {
        case video = "video"
        case audio = "audio"
        case document = "document"
        
        var icon: String {
            switch self {
            case .video: return "play.rectangle"
            case .audio: return "music.note"
            case .document: return "doc"
            }
        }
    }
}

// MARK: - Playlist Model
struct Playlist: Identifiable, Codable {
    let id = UUID()
    var name: String
    var description: String?
    var mediaFiles: [MediaFile]
    let dateCreated: Date
    var dateModified: Date
    var isSmartPlaylist: Bool
    var smartCriteria: SmartCriteria?
    
    struct SmartCriteria: Codable {
        let genre: String?
        let dateRange: DateInterval?
        let mediaType: MediaFile.MediaType?
        let minDuration: TimeInterval?
        let maxDuration: TimeInterval?
    }
}

// MARK: - Stream Source Model
struct StreamSource: Identifiable, Codable {
    let id = UUID()
    let name: String
    let url: URL
    let type: StreamType
    let isActive: Bool
    let lastConnected: Date?
    
    enum StreamType: String, CaseIterable, Codable {
        case url = "url"
        case network = "network"
        case cloud = "cloud"
        
        var icon: String {
            switch self {
            case .url: return "link"
            case .network: return "network"
            case .cloud: return "icloud"
            }
        }
    }
}

// MARK: - Settings Model
struct AppSettings: Codable {
    var autoPlay: Bool = true
    var resumePosition: Bool = true
    var videoQuality: VideoQuality = .auto
    var subtitleAppearance: SubtitleAppearance = SubtitleAppearance()
    var audioOutput: AudioOutput = .automatic
    var cacheSize: Int = 1024 // MB
    var networkTimeout: TimeInterval = 30
    var privacyMode: Bool = false
    
    enum VideoQuality: String, CaseIterable, Codable {
        case auto = "auto"
        case low = "480p"
        case medium = "720p"
        case high = "1080p"
        case ultra = "4K"
    }
    
    enum AudioOutput: String, CaseIterable, Codable {
        case automatic = "automatic"
        case speakers = "speakers"
        case headphones = "headphones"
        case airplay = "airplay"
    }
}

// MARK: - Subtitle Appearance Model
struct SubtitleAppearance: Codable {
    var fontSize: CGFloat = 16
    var fontColor: Color = .white
    var backgroundColor: Color = .black
    var backgroundOpacity: Double = 0.7
    var fontFamily: String = "System"
    var isBold: Bool = false
    var isItalic: Bool = false
    var position: Position = .bottom
    
    enum Position: String, CaseIterable, Codable {
        case top = "top"
        case center = "center"
        case bottom = "bottom"
    }
}

// MARK: - Extensions for Color Codable
extension Color: Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let alpha = try container.decode(Double.self, forKey: .alpha)
        
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        guard let components = UIColor(self).cgColor.components else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unable to encode color"))
        }
        
        try container.encode(components[0], forKey: .red)
        try container.encode(components[1], forKey: .green)
        try container.encode(components[2], forKey: .blue)
        try container.encode(components.count > 3 ? components[3] : 1.0, forKey: .alpha)
    }
}

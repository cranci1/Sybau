import Foundation

public struct PlayerPreset: Hashable {
    public struct Stream: Hashable {
        public let url: URL
        public let note: String
        
        public init(url: URL, note: String) {
            self.url = url
            self.note = note
        }
    }
    
    public let title: String
    public let summary: String
    public let stream: Stream?
    public let commands: [[String]]
    
    public init(title: String, summary: String, stream: Stream?, commands: [[String]]) {
        self.title = title
        self.summary = summary
        self.stream = stream
        self.commands = commands
    }
    
    public static var presets: [PlayerPreset] {
        let list: [PlayerPreset] = []
        return list
    }
}

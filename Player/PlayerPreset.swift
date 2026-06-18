import Foundation

public struct PlayerPreset: Hashable {
    struct Stream: Hashable {
        let url: URL
        let note: String
    }
    
    let title: String
    let summary: String
    let stream: Stream?
    let commands: [[String]]
    
    static var presets: [PlayerPreset] {
        let list: [PlayerPreset] = []
        return list
    }
}

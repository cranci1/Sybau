//
//  Logger.swift
//  Sybau
//

import Foundation

public class Logger: @unchecked Sendable {
    public static let shared = Logger()
    
    struct LogEntry {
        let message: String
        let type: String
        let timestamp: Date
    }
    
    private let queue = DispatchQueue(label: "me.cranci.mpv.logger", attributes: .concurrent)
    private var logs: [LogEntry] = []
    private let logFileURL: URL
    private let maxFileSize = 1024 * 512
    private let maxLogEntries = 1000
    
    private let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd-MM HH:mm:ss"
        return f
    }()
    
    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        logFileURL = supportDir.appendingPathComponent("sybau_player.log")
    }
    
    // MARK: - Public API
    
    public func log(_ message: String, type: String = "General") {
        let entry = LogEntry(message: message, type: type, timestamp: Date())
        
        queue.async(flags: .barrier) {
            self.logs.append(entry)
            if self.logs.count > self.maxLogEntries {
                self.logs.removeFirst(self.logs.count - self.maxLogEntries)
            }
            self.saveLogToFile(entry)
            self.debugLog(entry)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("LoggerNotification"),
                    object: nil,
                    userInfo: [
                        "message": message,
                        "type": type,
                        "timestamp": entry.timestamp
                    ]
                )
            }
        }
    }
    
    public func getLogs() -> String {
        var result = ""
        queue.sync {
            result = self.logs.map {
                "[\(self.logFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)"
            }.joined(separator: "\n----\n")
        }
        return result
    }
    
    public func getLogsAsync() async -> String {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.logs.map {
                    "[\(self.logFormatter.string(from: $0.timestamp))] [\($0.type)] \($0.message)"
                }.joined(separator: "\n----\n")
                continuation.resume(returning: result)
            }
        }
    }
    
    public func clearLogs() {
        queue.async(flags: .barrier) {
            self.logs.removeAll()
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
    }
    
    public func clearLogsAsync() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.logs.removeAll()
                try? FileManager.default.removeItem(at: self.logFileURL)
                continuation.resume()
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func saveLogToFile(_ log: LogEntry) {
        let logString = "[\(logFormatter.string(from: log.timestamp))] [\(log.type)] \(log.message)\n---\n"
        
        guard let data = logString.data(using: .utf8) else {
            print("Failed to encode log string to UTF-8")
            return
        }
        
        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
                let fileSize = attributes[.size] as? UInt64 ?? 0
                
                if fileSize + UInt64(data.count) > maxFileSize {
                    truncateLogFile()
                }
                
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try data.write(to: logFileURL)
            }
        } catch {
            print("Error managing log file: \(error)")
            try? data.write(to: logFileURL)
        }
    }
    
    private func truncateLogFile() {
        do {
            guard let content = try? String(contentsOf: logFileURL, encoding: .utf8),
                  !content.isEmpty else { return }
            
            let entries = content.components(separatedBy: "\n---\n")
            guard entries.count > 10 else { return }
            
            let keepCount = entries.count / 2
            let truncatedContent = Array(entries.suffix(keepCount)).joined(separator: "\n---\n")
            
            if let truncatedData = truncatedContent.data(using: .utf8) {
                try truncatedData.write(to: logFileURL)
            }
        } catch {
            print("Error truncating log file: \(error)")
            try? FileManager.default.removeItem(at: logFileURL)
        }
    }
    
    private func debugLog(_ entry: LogEntry) {
#if DEBUG
        print("[\(logFormatter.string(from: entry.timestamp))] [\(entry.type)] \(entry.message)")
#endif
    }
}

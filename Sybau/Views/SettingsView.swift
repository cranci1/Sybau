import SwiftUI

struct SettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        NavigationView {
            List {
                // Playback Settings
                Section(header: Text("Playback")) {
                    Toggle("Auto-play next video", isOn: $dataManager.settings.autoPlay)
                    Toggle("Resume playback position", isOn: $dataManager.settings.resumePosition)
                }
                
                // Network Settings
                Section(header: Text("Network")) {
                    HStack {
                        Text("Connection Timeout")
                        Spacer()
                        Text("\(Int(dataManager.settings.networkTimeout))s")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Privacy Settings
                Section(header: Text("Privacy")) {
                    Toggle("Privacy Mode", isOn: $dataManager.settings.privacyMode)
                }
                
                // App Settings
                Section(header: Text("App")) {
                    Button("Reset All Settings") {
                        resetSettings()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: dataManager.settings.autoPlay) { _ in
                dataManager.saveData()
            }
            .onChange(of: dataManager.settings.resumePosition) { _ in
                dataManager.saveData()
            }
            .onChange(of: dataManager.settings.privacyMode) { _ in
                dataManager.saveData()
            }
        }
    }
    
    private func resetSettings() {
        dataManager.settings = AppSettings()
        dataManager.saveData()
    }
}

// MARK: - Video Quality Settings View
struct VideoQualitySettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        List {
            ForEach(AppSettings.VideoQuality.allCases, id: \.self) { quality in
                HStack {
                    Text(quality.rawValue)
                    Spacer()
                    if dataManager.settings.videoQuality == quality {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .onTapGesture {
                    dataManager.settings.videoQuality = quality
                    dataManager.saveData()
                }
            }
        }
        .navigationTitle("Video Quality")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subtitle Settings View
struct SubtitleSettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        List {
            Section(header: Text("Appearance")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Font Size")
                    Slider(value: $dataManager.settings.subtitleAppearance.fontSize, in: 12...32, step: 1)
                    Text("\(Int(dataManager.settings.subtitleAppearance.fontSize))pt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                NavigationLink("Font Family") {
                    FontFamilySettingsView()
                }
                
                Toggle("Bold", isOn: $dataManager.settings.subtitleAppearance.isBold)
                Toggle("Italic", isOn: $dataManager.settings.subtitleAppearance.isItalic)
            }
            
            Section(header: Text("Colors")) {
                ColorRow(title: "Text Color", color: $dataManager.settings.subtitleAppearance.fontColor)
                ColorRow(title: "Background Color", color: $dataManager.settings.subtitleAppearance.backgroundColor)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Background Opacity")
                    Slider(value: $dataManager.settings.subtitleAppearance.backgroundOpacity, in: 0...1, step: 0.1)
                    Text("\(Int(dataManager.settings.subtitleAppearance.backgroundOpacity * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Position")) {
                ForEach(SubtitleAppearance.Position.allCases, id: \.self) { position in
                    HStack {
                        Text(position.rawValue.capitalized)
                        Spacer()
                        if dataManager.settings.subtitleAppearance.position == position {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .onTapGesture {
                        dataManager.settings.subtitleAppearance.position = position
                        dataManager.saveData()
                    }
                }
            }
            
            Section(header: Text("Preview")) {
                VStack(spacing: 16) {
                    Text("Sample subtitle text")
                        .font(.system(size: dataManager.settings.subtitleAppearance.fontSize, 
                                    weight: dataManager.settings.subtitleAppearance.isBold ? .bold : .regular))
                        .foregroundColor(dataManager.settings.subtitleAppearance.fontColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            dataManager.settings.subtitleAppearance.backgroundColor
                                .opacity(dataManager.settings.subtitleAppearance.backgroundOpacity)
                        )
                        .cornerRadius(4)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .cornerRadius(8)
            }
        }
        .navigationTitle("Subtitle Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: dataManager.settings.subtitleAppearance.fontSize) { _ in
            dataManager.saveData()
        }
        .onChange(of: dataManager.settings.subtitleAppearance.backgroundOpacity) { _ in
            dataManager.saveData()
        }
        .onChange(of: dataManager.settings.subtitleAppearance.isBold) { _ in
            dataManager.saveData()
        }
        .onChange(of: dataManager.settings.subtitleAppearance.isItalic) { _ in
            dataManager.saveData()
        }
    }
}

// MARK: - Audio Output Settings View
struct AudioOutputSettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        List {
            ForEach(AppSettings.AudioOutput.allCases, id: \.self) { output in
                HStack {
                    Text(output.rawValue.capitalized)
                    Spacer()
                    if dataManager.settings.audioOutput == output {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .onTapGesture {
                    dataManager.settings.audioOutput = output
                    dataManager.saveData()
                }
            }
        }
        .navigationTitle("Audio Output")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Network Settings View
struct NetworkSettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        List {
            Section(header: Text("Connection")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timeout Duration")
                    Slider(value: $dataManager.settings.networkTimeout, in: 10...120, step: 10)
                    Text("\(Int(dataManager.settings.networkTimeout)) seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Streaming")) {
                Toggle("Prefer WiFi for streaming", isOn: .constant(true))
                Toggle("Allow cellular data", isOn: .constant(false))
            }
            
            Section(header: Text("Network Diagnostics")) {
                Button("Test Connection") {
                    testNetworkConnection()
                }
                
                Button("Clear DNS Cache") {
                    clearDNSCache()
                }
            }
        }
        .navigationTitle("Network Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: dataManager.settings.networkTimeout) { _ in
            dataManager.saveData()
        }
    }
    
    private func testNetworkConnection() {
        // Implement network testing
        print("Testing network connection...")
    }
    
    private func clearDNSCache() {
        // Implement DNS cache clearing
        print("Clearing DNS cache...")
    }
}

// MARK: - Storage Management View
struct StorageManagementView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var cacheSize: Double = 0
    @State private var totalStorage: Double = 0
    @State private var usedStorage: Double = 0
    
    var body: some View {
        List {
            Section(header: Text("Storage Overview")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Total Storage")
                        Spacer()
                        Text(formatBytes(totalStorage))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Used Storage")
                        Spacer()
                        Text(formatBytes(usedStorage))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Available Storage")
                        Spacer()
                        Text(formatBytes(totalStorage - usedStorage))
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: usedStorage / totalStorage)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            
            Section(header: Text("Cache Management")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cache Size Limit")
                    Slider(value: Binding(
                        get: { Double(dataManager.settings.cacheSize) },
                        set: { dataManager.settings.cacheSize = Int($0) }
                    ), in: 256...4096, step: 256)
                    Text("\(dataManager.settings.cacheSize) MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Current Cache Size")
                    Spacer()
                    Text(formatBytes(cacheSize))
                        .foregroundColor(.secondary)
                }
                
                Button("Clear Cache") {
                    clearCache()
                }
                .foregroundColor(.red)
            }
            
            Section(header: Text("Media Files")) {
                HStack {
                    Text("Total Media Files")
                    Spacer()
                    Text("\(dataManager.mediaFiles.count)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Media Storage Used")
                    Spacer()
                    Text(formatBytes(Double(dataManager.mediaFiles.reduce(0) { $0 + $1.size })))
                        .foregroundColor(.secondary)
                }
                
                Button("Optimize Storage") {
                    optimizeStorage()
                }
            }
        }
        .navigationTitle("Storage Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStorageInfo()
        }
        .onChange(of: dataManager.settings.cacheSize) { _ in
            dataManager.saveData()
        }
    }
    
    private func loadStorageInfo() {
        // Load actual storage information
        totalStorage = 64_000_000_000 // 64 GB example
        usedStorage = 32_000_000_000 // 32 GB example
        cacheSize = 1_000_000_000 // 1 GB example
    }
    
    private func clearCache() {
        // Implement cache clearing
        cacheSize = 0
        print("Cache cleared")
    }
    
    private func optimizeStorage() {
        // Implement storage optimization
        print("Optimizing storage...")
    }
    
    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Privacy Settings View
struct PrivacySettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    var body: some View {
        List {
            Section(header: Text("Privacy Mode")) {
                Toggle("Enable Privacy Mode", isOn: $dataManager.settings.privacyMode)
                
                if dataManager.settings.privacyMode {
                    Text("Privacy mode hides recent activity and disables usage tracking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Data Collection")) {
                Toggle("Usage Analytics", isOn: .constant(false))
                Toggle("Crash Reporting", isOn: .constant(true))
                Toggle("Performance Metrics", isOn: .constant(false))
            }
            
            Section(header: Text("History")) {
                Button("Clear Recently Played") {
                    clearRecentlyPlayed()
                }
                .foregroundColor(.red)
                
                Button("Clear Search History") {
                    clearSearchHistory()
                }
                .foregroundColor(.red)
                
                Button("Clear All Data") {
                    clearAllData()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Privacy Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: dataManager.settings.privacyMode) { _ in
            dataManager.saveData()
        }
    }
    
    private func clearRecentlyPlayed() {
        dataManager.recentlyPlayed.removeAll()
        dataManager.saveData()
    }
    
    private func clearSearchHistory() {
        // Implement search history clearing
        print("Search history cleared")
    }
    
    private func clearAllData() {
        dataManager.recentlyPlayed.removeAll()
        dataManager.favorites.removeAll()
        dataManager.mostPlayed.removeAll()
        dataManager.saveData()
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)
                    
                    Text("Sybau")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Advanced Media Player")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            Section(header: Text("Information")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text("1")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Framework")
                    Spacer()
                    Text("MPV")
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Support")) {
                Button("Report a Bug") {
                    reportBug()
                }
                
                Button("Feature Request") {
                    requestFeature()
                }
                
                Button("Contact Support") {
                    contactSupport()
                }
            }
            
            Section(header: Text("Legal")) {
                Button("Privacy Policy") {
                    openPrivacyPolicy()
                }
                
                Button("Terms of Service") {
                    openTermsOfService()
                }
                
                Button("Open Source Licenses") {
                    openLicenses()
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func reportBug() {
        // Implement bug reporting
        print("Report bug")
    }
    
    private func requestFeature() {
        // Implement feature request
        print("Request feature")
    }
    
    private func contactSupport() {
        // Implement support contact
        print("Contact support")
    }
    
    private func openPrivacyPolicy() {
        // Open privacy policy
        print("Open privacy policy")
    }
    
    private func openTermsOfService() {
        // Open terms of service
        print("Open terms of service")
    }
    
    private func openLicenses() {
        // Open licenses
        print("Open licenses")
    }
}

// MARK: - Font Family Settings View
struct FontFamilySettingsView: View {
    @StateObject private var dataManager = DataManager.shared
    
    private let fontFamilies = [
        "System",
        "Arial",
        "Helvetica",
        "Times New Roman",
        "Courier New",
        "Georgia",
        "Verdana"
    ]
    
    var body: some View {
        List {
            ForEach(fontFamilies, id: \.self) { family in
                HStack {
                    Text(family)
                        .font(.custom(family, size: 16))
                    Spacer()
                    if dataManager.settings.subtitleAppearance.fontFamily == family {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .onTapGesture {
                    dataManager.settings.subtitleAppearance.fontFamily = family
                    dataManager.saveData()
                }
            }
        }
        .navigationTitle("Font Family")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Color Row
struct ColorRow: View {
    let title: String
    @Binding var color: Color
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.secondary, lineWidth: 1)
                )
        }
        .onTapGesture {
            // In a real app, this would open a color picker
            print("Open color picker for \(title)")
        }
    }
}

#Preview {
    SettingsView()
}

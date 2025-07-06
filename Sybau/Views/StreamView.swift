import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct StreamView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var streamURL = ""
    @State private var showingURLInput = false
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var connectionStatus: ConnectionStatus = .disconnected
    @State private var isStreaming = false
    @State private var streamProgress: Double = 0
    @State private var showingRemoteBrowser = false
    @State private var selectedRemoteSource: StreamSource?
    
    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
        
        var color: Color {
            switch self {
            case .disconnected: return .gray
            case .connecting: return .orange
            case .connected: return .green
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .disconnected: return "wifi.slash"
            case .connecting: return "wifi.exclamationmark"
            case .connected: return "wifi"
            case .error: return "wifi.slash"
            }
        }
        
        var text: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error(let message): return "Error: \(message)"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection Status
                    connectionStatusView
                    
                    // Stream Options
                    streamOptionsView
                    
                    // Current Stream Info
                    if isStreaming {
                        currentStreamView
                    }
                    
                    // Remote Sources
                    remoteSourcesView
                }
                .padding()
            }
            .navigationTitle("Stream")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Source") {
                        showingURLInput = true
                    }
                }
            }
            .sheet(isPresented: $showingURLInput) {
                URLInputView(onStreamURL: { url in
                    streamFromURL(url)
                })
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(
                    allowedTypes: ["public.movie", "public.audio", "public.audiovisual-content"],
                    onFilePicked: { urls in
                        if let url = urls.first {
                            streamFromURL(url.absoluteString)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoPicker(onImagePicked: { url in
                    if let url = url {
                        streamFromURL(url.absoluteString)
                    }
                })
            }
            .sheet(isPresented: $showingRemoteBrowser) {
                if let source = selectedRemoteSource {
                    RemoteBrowserView(source: source) { url in
                        streamFromURL(url.absoluteString)
                    }
                }
            }
        }
    }
    
    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: connectionStatus.icon)
                    .foregroundColor(connectionStatus.color)
                    .font(.title2)
                
                Text(connectionStatus.text)
                    .font(.headline)
                    .foregroundColor(connectionStatus.color)
                
                Spacer()
                
                if case .connecting = connectionStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .background(connectionStatus.color.opacity(0.1))
            .cornerRadius(12)
            
            if case .error(let message) = connectionStatus {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
    }
    
    private var streamOptionsView: some View {
        VStack(spacing: 16) {
            Text("Stream Options")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                StreamOptionCard(
                    title: "Stream URL",
                    subtitle: "Enter a direct stream URL",
                    icon: "link",
                    color: .blue
                ) {
                    showingURLInput = true
                }
                
                StreamOptionCard(
                    title: "From Files",
                    subtitle: "Select from device storage",
                    icon: "folder",
                    color: .green
                ) {
                    showingFilePicker = true
                }
                
                StreamOptionCard(
                    title: "From Photos",
                    subtitle: "Choose from photo library",
                    icon: "photo",
                    color: .orange
                ) {
                    showingPhotoPicker = true
                }
                
                StreamOptionCard(
                    title: "Network Share",
                    subtitle: "Browse network folders",
                    icon: "network",
                    color: .purple
                ) {
                    showingRemoteBrowser = true
                }
            }
        }
    }
    
    private var currentStreamView: some View {
        VStack(spacing: 16) {
            Text("Current Stream")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "play.rectangle")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        Text("Streaming...")
                            .font(.headline)
                        Text(streamURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: stopStream) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                }
                
                ProgressView(value: streamProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    Text("Buffering...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(streamProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var remoteSourcesView: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Remote Sources")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Add") {
                    showingURLInput = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if dataManager.streamSources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("No remote sources added")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Add network locations to browse remote media")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(dataManager.streamSources) { source in
                        RemoteSourceRow(source: source) {
                            selectedRemoteSource = source
                            showingRemoteBrowser = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    private func streamFromURL(_ url: String) {
        guard !url.isEmpty else { return }
        
        // Validate URL format
        guard let validURL = URL(string: url) else {
            connectionStatus = .error("Invalid URL format")
            return
        }
        
        // Check if it's a supported URL scheme
        guard ["http", "https", "rtsp", "rtmp", "file"].contains(validURL.scheme?.lowercased()) else {
            connectionStatus = .error("Unsupported URL scheme")
            return
        }
        
        streamURL = url
        connectionStatus = .connecting
        isStreaming = true
        
        // Add timeout for connection
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            if case .connecting = connectionStatus {
                connectionStatus = .error("Connection timeout")
                isStreaming = false
            }
        }
        
        // Start streaming immediately for URLs
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            timeoutTimer.invalidate()
            if case .connecting = connectionStatus {
                connectionStatus = .connected
                playStream(url)
            }
        }
    }
    
    private func playStream(_ url: String) {
        guard let streamURL = URL(string: url) else { 
            connectionStatus = .error("Invalid URL")
            return 
        }
        
        // Create a media file for streaming
        let mediaFile = MediaFile(
            name: streamURL.lastPathComponent.isEmpty ? "Stream" : streamURL.lastPathComponent,
            url: streamURL,
            size: 0,
            duration: nil,
            format: "stream",
            dateAdded: Date(),
            thumbnailPath: nil,
            type: url.contains("mp4") || url.contains("mov") || url.contains("mkv") ? .video : .audio
        )
        
        // Set as currently playing and navigate to player
        dataManager.currentlyPlaying = mediaFile
        dataManager.shouldNavigateToPlayer = true
        
        // Add to recent streams (after successful playback initiation)
        dataManager.addToRecentlyPlayed(mediaFile)
    }
    
    private func stopStream() {
        isStreaming = false
        streamProgress = 0
        connectionStatus = .disconnected
        streamURL = ""
    }
}

// MARK: - Stream Option Card
struct StreamOptionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(color)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Remote Source Row
struct RemoteSourceRow: View {
    let source: StreamSource
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: source.type.icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(source.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: source.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(source.isActive ? .green : .secondary)
                
                if let lastConnected = source.lastConnected {
                    Text(lastConnected, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Recent Stream Row
struct RecentStreamRow: View {
    let file: MediaFile
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "clock")
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(file.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(file.dateAdded, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture {
            action()
        }
    }
}

// MARK: - URL Input View
struct URLInputView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var urlText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    let onStreamURL: (String) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter Stream URL")
                        .font(.headline)
                    
                    Text("Supported formats: HTTP(S), RTSP, RTMP, and direct file links")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                TextField("https://example.com/stream.m3u8", text: $urlText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                if showingError {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Button("Stream") {
                    validateAndStream()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.isEmpty)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Stream URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func validateAndStream() {
        guard let url = URL(string: urlText) else {
            showError("Invalid URL format")
            return
        }
        
        guard ["http", "https", "rtsp", "rtmp", "file"].contains(url.scheme?.lowercased()) else {
            showError("Unsupported URL scheme. Please use HTTP, HTTPS, RTSP, RTMP, or file URLs.")
            return
        }
        
        showingError = false
        onStreamURL(urlText)
        presentationMode.wrappedValue.dismiss()
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Remote Browser View
struct RemoteBrowserView: View {
    @Environment(\.presentationMode) var presentationMode
    let source: StreamSource
    let onSelectURL: (URL) -> Void
    
    @State private var isLoading = false
    @State private var items: [RemoteItem] = []
    @State private var currentPath = ""
    
    struct RemoteItem: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        let isDirectory: Bool
        let size: Int64?
        let dateModified: Date?
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No items found")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                                .foregroundColor(item.isDirectory ? .blue : .secondary)
                            
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .font(.body)
                                
                                if let size = item.size {
                                    Text(formatFileSize(size))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if !item.isDirectory {
                                Button("Stream") {
                                    onSelectURL(item.url)
                                    presentationMode.wrappedValue.dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                            }
                        }
                        .onTapGesture {
                            if item.isDirectory {
                                // Navigate to directory
                                loadDirectory(item.url)
                            }
                        }
                    }
                }
            }
            .navigationTitle(source.name)
            .navigationBarTitleDisplayMode(.inline)
            .compatibleNavigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: !currentPath.isEmpty ? 
                    Button("Up") {
                        navigateUp()
                    } : nil
            )
            .onAppear {
                loadDirectory(source.url)
            }
        }
    }
    
    private func loadDirectory(_ url: URL) {
        isLoading = true
        // Simulate loading remote directory
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Mock data - in real implementation, this would fetch from the remote source
            items = [
                RemoteItem(name: "Videos", url: url.appendingPathComponent("Videos"), isDirectory: true, size: nil, dateModified: Date()),
                RemoteItem(name: "sample.mp4", url: url.appendingPathComponent("sample.mp4"), isDirectory: false, size: 1024000, dateModified: Date())
            ]
            isLoading = false
        }
    }
    
    private func navigateUp() {
        // Implement navigation up logic
        currentPath = String(currentPath.dropLast().drop(while: { $0 != "/" }))
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    let allowedTypes: [String]
    let onFilePicked: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = allowedTypes.compactMap { UTType($0) }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onFilePicked(urls)
        }
    }
}

// MARK: - Photo Picker
struct PhotoPicker: UIViewControllerRepresentable {
    let onImagePicked: (URL?) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        
        init(_ parent: PhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else {
                parent.onImagePicked(nil)
                return
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    DispatchQueue.main.async {
                        if let url = url {
                            // Copy to temporary directory to ensure access
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.copyItem(at: url, to: tempURL)
                            self.parent.onImagePicked(tempURL)
                        } else {
                            self.parent.onImagePicked(nil)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                    DispatchQueue.main.async {
                        if let url = url {
                            // Copy to temporary directory to ensure access
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.copyItem(at: url, to: tempURL)
                            self.parent.onImagePicked(tempURL)
                        } else {
                            self.parent.onImagePicked(nil)
                        }
                    }
                }
            } else {
                parent.onImagePicked(nil)
            }
        }
    }
}

#Preview {
    StreamView()
}

import SwiftUI

struct MainTabView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var showingPlayer = false
    
    var body: some View {
        TabView {
            FilesView()
                .tabItem {
                    Image(systemName: "folder")
                    Text("Files")
                }
            
            StreamView()
                .tabItem {
                    Image(systemName: "wifi")
                    Text("Stream")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
        }
        .accentColor(.blue)
        .onChange(of: dataManager.shouldNavigateToPlayer) { shouldNavigate in
            if shouldNavigate, let mediaFile = dataManager.currentlyPlaying {
                showingPlayer = true
                dataManager.shouldNavigateToPlayer = false
            }
        }
        .fullScreenCover(isPresented: $showingPlayer) {
            if let mediaFile = dataManager.currentlyPlaying {
                PlayerView(mediaFile: mediaFile)
            }
        }
    }
}

#Preview {
    MainTabView()
}

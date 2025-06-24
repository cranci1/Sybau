//
//  ContentView.swift
//  Sybau
//
//  Created by Francesco on 22/06/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            MediaLibraryView()
                .tabItem {
                    Label("Library", systemImage: "tv")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationView {
            Form {
                Section("About") {
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
                }
                
                Section("Playback") {
                    HStack {
                        Text("Default Volume")
                        Spacer()
                        Text("100%")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Auto-play next", isOn: .constant(true))
                    Toggle("Remember playback position", isOn: .constant(true))
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
}

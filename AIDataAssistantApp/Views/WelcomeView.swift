import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
            
            VStack(spacing: 10) {
                Text("Welcome to AI Data Assistant")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Connect to your database to get started")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 15) {
                if let error = appState.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Button(action: {
                    showingSettings = true
                }) {
                    Label("Configure Connection", systemImage: "gearshape.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                if !appState.databasePath.isEmpty && !appState.awsAccessKeyId.isEmpty {
                    Button(action: {
                        Task {
                            await appState.connect()
                        }
                    }) {
                        if appState.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 20)
                        } else {
                            Label("Connect", systemImage: "bolt.fill")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(appState.isLoading)
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Text("Features:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 40) {
                    FeatureLabel(icon: "text.bubble.fill", text: "Natural Language Queries")
                    FeatureLabel(icon: "brain.head.profile", text: "AI-Powered SQL Generation")
                    FeatureLabel(icon: "chart.bar.fill", text: "Smart Results")
                }
            }
            .padding(.bottom, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct FeatureLabel: View {
    let icon: String
    let text: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AppState())
}


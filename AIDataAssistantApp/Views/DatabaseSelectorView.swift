import SwiftUI
import AIDataAssistantCore

struct DatabaseSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showingAddConnection = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with add button
            HStack {
                Text("Databases")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddConnection = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add Database Connection")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Current connection status
            if let current = databaseManager.currentConnection {
                currentConnectionView(current)
            } else {
                noConnectionView
            }
            
            Divider()
            
            // Available connections list
            if !databaseManager.availableConnections.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(databaseManager.availableConnections) { connection in
                            connectionRow(connection)
                        }
                    }
                    .padding(8)
                }
            } else {
                emptyStateView
            }
        }
        .sheet(isPresented: $showingAddConnection) {
            DatabaseConnectionView(databaseManager: databaseManager)
        }
    }
    
    func currentConnectionView(_ connection: DatabaseConnection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                connectionIcon(for: connection.type)
                Text(connection.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                connectionStatusBadge
            }
            
            Text(connectionDescription(for: connection))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.1))
    }
    
    var noConnectionView: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No Connection")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 80)
    }
    
    var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Saved Connections")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Click + to add a database")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Add Connection") {
                showingAddConnection = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
    }
    
    func connectionRow(_ connection: DatabaseConnection) -> some View {
        HStack {
            connectionIcon(for: connection.type)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(connectionDescription(for: connection))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if databaseManager.currentConnection?.id == connection.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(8)
        .background(
            databaseManager.currentConnection?.id == connection.id 
                ? Color.accentColor.opacity(0.1) 
                : Color.clear
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            if databaseManager.currentConnection?.id != connection.id {
                Task {
                    await databaseManager.connect(to: connection)
                }
            }
        }
        .contextMenu {
            Button("Connect") {
                Task {
                    await databaseManager.connect(to: connection)
                }
            }
            .disabled(databaseManager.currentConnection?.id == connection.id)
            
            Divider()
            
            Button("Delete", role: .destructive) {
                databaseManager.removeConnection(connection)
            }
        }
    }
    
    func connectionIcon(for type: DatabaseType) -> some View {
        Image(systemName: iconName(for: type))
            .foregroundColor(iconColor(for: type))
            .frame(width: 20)
    }
    
    func iconName(for type: DatabaseType) -> String {
        switch type {
        case .mysql:
            return "cylinder.fill"
        case .sqlite:
            return "doc.fill"
        case .postgresql:
            return "server.rack"
        default:
            return "cylinder"
        }
    }
    
    func iconColor(for type: DatabaseType) -> Color {
        switch type {
        case .mysql:
            return .blue
        case .sqlite:
            return .green
        case .postgresql:
            return .purple
        default:
            return .gray
        }
    }
    
    func connectionDescription(for connection: DatabaseConnection) -> String {
        switch connection.type {
        case .mysql:
            if let host = connection.config.options?["host"],
               let database = connection.config.options?["database"] {
                return "\(host)/\(database)"
            }
        case .sqlite:
            return connection.config.connectionString
        default:
            break
        }
        return connection.config.connectionString
    }
    
    var connectionStatusBadge: some View {
        Group {
            switch databaseManager.connectionState {
            case .connected:
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            case .connecting:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Connecting...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            case .disconnected:
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 6, height: 6)
                    Text("Disconnected")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            case .error(let message):
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Error")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .help(message)
            }
        }
    }
}

#Preview {
    DatabaseSelectorView(databaseManager: DatabaseManager())
        .frame(width: 250, height: 400)
}


import Foundation

/// Connection state
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Database connection information
struct DatabaseConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: DatabaseType
    let config: DatabaseConfig
    
    init(id: UUID = UUID(), name: String, type: DatabaseType, config: DatabaseConfig) {
        self.id = id
        self.name = name
        self.type = type
        self.config = config
    }
    
    static func == (lhs: DatabaseConnection, rhs: DatabaseConnection) -> Bool {
        lhs.id == rhs.id
    }
}

/// Database manager for handling multiple database connections
@MainActor
class DatabaseManager: ObservableObject {
    @Published var currentConnection: DatabaseConnection?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var availableConnections: [DatabaseConnection] = []
    
    private var currentDatabase: DatabaseProtocol?
    
    init() {
        loadConnections()
    }
    
    /// Connect to a database
    func connect(to connection: DatabaseConnection) async {
        connectionState = .connecting
        
        do {
            // Disconnect from current database
            if let current = currentDatabase {
                try await current.disconnect()
            }
            
            // Create new database instance
            let database = createDatabase(for: connection.type)
            
            // Connect
            try await database.connect(config: connection.config)
            
            // Update state
            currentDatabase = database
            currentConnection = connection
            connectionState = .connected
            
            // Save as current connection
            saveCurrentConnection(connection)
            
            // Notify observers
            NotificationCenter.default.post(name: .databaseConnectionChanged, object: nil)
        } catch {
            connectionState = .error(error.localizedDescription)
            currentDatabase = nil
            currentConnection = nil
        }
    }
    
    /// Disconnect from current database
    func disconnect() async {
        if let database = currentDatabase {
            try? await database.disconnect()
        }
        
        currentDatabase = nil
        currentConnection = nil
        connectionState = .disconnected
        
        // Notify observers
        NotificationCenter.default.post(name: .databaseConnectionChanged, object: nil)
    }
    
    /// Get current database instance
    func getCurrentDatabase() -> DatabaseProtocol? {
        return currentDatabase
    }
    
    /// Add a new connection
    func addConnection(_ connection: DatabaseConnection) {
        availableConnections.append(connection)
        saveConnections()
    }
    
    /// Remove a connection
    func removeConnection(_ connection: DatabaseConnection) {
        availableConnections.removeAll { $0.id == connection.id }
        saveConnections()
        
        // If removing current connection, disconnect
        if currentConnection?.id == connection.id {
            Task {
                await disconnect()
            }
        }
    }
    
    /// Update a connection
    func updateConnection(_ connection: DatabaseConnection) {
        if let index = availableConnections.firstIndex(where: { $0.id == connection.id }) {
            availableConnections[index] = connection
            saveConnections()
        }
    }
    
    /// Test a connection without connecting
    func testConnection(_ connection: DatabaseConnection) async -> Result<String, Error> {
        let database = createDatabase(for: connection.type)
        
        do {
            try await database.connect(config: connection.config)
            let isValid = try await database.testConnection()
            try await database.disconnect()
            
            if isValid {
                return .success("Connection successful!")
            } else {
                return .failure(DatabaseError.connectionFailed("Connection test failed"))
            }
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func createDatabase(for type: DatabaseType) -> DatabaseProtocol {
        switch type {
        case .sqlite:
            return SQLiteDatabase()
        case .mysql:
            return MySQLDatabase()
        default:
            fatalError("Database type \(type) not yet implemented")
        }
    }

    private func loadConnections() {
        if let data = UserDefaults.standard.data(forKey: "database_connections"),
           let connections = try? JSONDecoder().decode([DatabaseConnection].self, from: data) {
            availableConnections = connections
        }

        // Load current connection
        if let data = UserDefaults.standard.data(forKey: "current_connection"),
           let connection = try? JSONDecoder().decode(DatabaseConnection.self, from: data) {
            // Auto-connect to last connection
            Task {
                await connect(to: connection)
            }
        }
    }

    private func saveConnections() {
        if let data = try? JSONEncoder().encode(availableConnections) {
            UserDefaults.standard.set(data, forKey: "database_connections")
        }
    }

    private func saveCurrentConnection(_ connection: DatabaseConnection) {
        if let data = try? JSONEncoder().encode(connection) {
            UserDefaults.standard.set(data, forKey: "current_connection")
        }
    }
}


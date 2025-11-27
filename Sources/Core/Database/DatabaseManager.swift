import Foundation

/// Connection state
public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Database connection information
public struct DatabaseConnection: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let type: DatabaseType
    public let config: DatabaseConfig
    
    public init(id: UUID = UUID(), name: String, type: DatabaseType, config: DatabaseConfig) {
        self.id = id
        self.name = name
        self.type = type
        self.config = config
    }
    
    public static func == (lhs: DatabaseConnection, rhs: DatabaseConnection) -> Bool {
        lhs.id == rhs.id
    }
}

/// Database manager for handling multiple database connections
@MainActor
public class DatabaseManager: ObservableObject {
    @Published public var currentConnection: DatabaseConnection?
    @Published public var connectionState: ConnectionState = .disconnected
    @Published public var availableConnections: [DatabaseConnection] = []
    
    private var currentDatabase: DatabaseProtocol?
    
    public init() {
        loadConnections()
    }
    
    /// Connect to a database
    public func connect(to connection: DatabaseConnection) async {
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
        } catch {
            connectionState = .error(error.localizedDescription)
            currentDatabase = nil
            currentConnection = nil
        }
    }
    
    /// Disconnect from current database
    public func disconnect() async {
        if let database = currentDatabase {
            try? await database.disconnect()
        }
        
        currentDatabase = nil
        currentConnection = nil
        connectionState = .disconnected
    }
    
    /// Get current database instance
    public func getCurrentDatabase() -> DatabaseProtocol? {
        return currentDatabase
    }
    
    /// Add a new connection
    public func addConnection(_ connection: DatabaseConnection) {
        availableConnections.append(connection)
        saveConnections()
    }
    
    /// Remove a connection
    public func removeConnection(_ connection: DatabaseConnection) {
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
    public func updateConnection(_ connection: DatabaseConnection) {
        if let index = availableConnections.firstIndex(where: { $0.id == connection.id }) {
            availableConnections[index] = connection
            saveConnections()
        }
    }
    
    /// Test a connection without connecting
    public func testConnection(_ connection: DatabaseConnection) async -> Result<String, Error> {
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


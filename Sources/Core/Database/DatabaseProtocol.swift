import Foundation

/// Protocol defining database operations
public protocol DatabaseProtocol {
    /// Connect to the database
    func connect(config: DatabaseConfig) async throws

    /// Disconnect from the database
    func disconnect() async throws

    /// Execute a SQL query and return results
    func executeQuery(_ sql: String) async throws -> QueryResult

    /// Get the database schema
    func getSchema() async throws -> DatabaseSchema

    /// Test if the connection is valid
    func testConnection() async throws -> Bool

    /// Check if currently connected
    var isConnected: Bool { get }

    /// Get the database type
    var databaseType: DatabaseType { get }
}

/// Database errors
public enum DatabaseError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)
    case schemaExtractionFailed(String)
    case invalidConfiguration(String)
    case unsupportedOperation(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Database is not connected"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .schemaExtractionFailed(let message):
            return "Schema extraction failed: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .unsupportedOperation(let message):
            return "Unsupported operation: \(message)"
        }
    }
}


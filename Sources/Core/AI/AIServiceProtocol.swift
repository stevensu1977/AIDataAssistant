import Foundation

/// Protocol defining AI service operations
public protocol AIServiceProtocol {
    /// Initialize the AI service with configuration
    func initialize(config: AIConfig) async throws

    /// Generate SQL from natural language query
    func generateSQL(naturalLanguage: String, schema: DatabaseSchema, context: QueryContext?, databaseType: DatabaseType) async throws -> String

    /// Explain a SQL query in natural language
    func explainQuery(sql: String) async throws -> String

    /// Suggest optimizations for a SQL query
    func suggestOptimizations(sql: String, schema: DatabaseSchema) async throws -> [String]

    /// Check if the service is initialized
    var isInitialized: Bool { get }
}

/// AI service errors
public enum AIServiceError: LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case generationFailed(String)
    case invalidResponse(String)
    case invalidConfiguration(String)
    case rateLimitExceeded
    case authenticationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "AI service is not initialized"
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        case .generationFailed(let message):
            return "SQL generation failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded, please try again later"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        }
    }
}


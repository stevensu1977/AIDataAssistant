import Foundation

/// Main query engine that coordinates database and AI services
public class QueryEngine {
    private let database: DatabaseProtocol
    private let aiService: AIServiceProtocol
    private var schemaCache: DatabaseSchema?
    private var queryHistory: [String] = []
    
    public init(database: DatabaseProtocol, aiService: AIServiceProtocol) {
        self.database = database
        self.aiService = aiService
    }

    /// Process a natural language query
    public func processQuery(_ request: QueryRequest) async throws -> QueryResponse {
        // Ensure we have the schema
        let schema = try await getOrFetchSchema()
        
        // Build context with query history
        let context = QueryContext(
            previousQueries: queryHistory,
            focusTables: request.context?.focusTables
        )
        
        // Generate SQL using AI with correct database dialect
        let dbType = database.databaseType
        print("\n🤖 Generating SQL from: \"\(request.naturalLanguage)\" for \(dbType.rawValue)")
        let sql = try await aiService.generateSQL(
            naturalLanguage: request.naturalLanguage,
            schema: schema,
            context: context,
            databaseType: dbType
        )
        
        print("📝 Generated SQL: \(sql)")
        
        // Execute the query
        print("⚡ Executing query...")
        let result = try await database.executeQuery(sql)
        
        // Add to history
        queryHistory.append(sql)
        if queryHistory.count > 10 {
            queryHistory.removeFirst()
        }
        
        // Generate explanation (optional)
        var explanation: String?
        do {
            explanation = try await aiService.explainQuery(sql: sql)
        } catch {
            // Explanation is optional, don't fail if it errors
            print("⚠️  Could not generate explanation: \(error.localizedDescription)")
        }
        
        return QueryResponse(
            generatedSQL: sql,
            result: result,
            explanation: explanation
        )
    }
    
    /// Execute a direct SQL query (bypass AI)
    public func executeSQL(_ sql: String) async throws -> QueryResult {
        print("⚡ Executing SQL: \(sql)")
        let result = try await database.executeQuery(sql)
        
        // Add to history
        queryHistory.append(sql)
        if queryHistory.count > 10 {
            queryHistory.removeFirst()
        }
        
        return result
    }
    
    /// Get the database schema
    public func getSchema() async throws -> DatabaseSchema {
        return try await getOrFetchSchema()
    }
    
    /// Refresh the schema cache
    public func refreshSchema() async throws {
        print("🔄 Refreshing schema cache...")
        schemaCache = try await database.getSchema()
        print("✓ Schema cache updated")
    }
    
    /// Get suggestions for optimizing a query
    public func getOptimizations(for sql: String) async throws -> [String] {
        let schema = try await getOrFetchSchema()
        return try await aiService.suggestOptimizations(sql: sql, schema: schema)
    }
    
    /// Clear query history
    public func clearHistory() {
        queryHistory.removeAll()
        print("✓ Query history cleared")
    }
    
    // MARK: - Private Helpers
    
    private func getOrFetchSchema() async throws -> DatabaseSchema {
        if let cached = schemaCache {
            return cached
        }
        
        print("📊 Fetching database schema...")
        let schema = try await database.getSchema()
        schemaCache = schema
        print("✓ Schema loaded: \(schema.tables.count) tables")
        return schema
    }
}

/// Query engine errors
public enum QueryEngineError: LocalizedError {
    case invalidQuery(String)
    case executionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidQuery(let message):
            return "Invalid query: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}


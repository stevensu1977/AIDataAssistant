import Foundation

/// AWS Bedrock AI service implementation using custom AWSBedrockClient
public class BedrockAIService: AIServiceProtocol {
    private var client: AWSBedrockClient?
    private var config: AIConfig?

    public var isInitialized: Bool {
        client != nil
    }

    public init() {}

    public func initialize(config: AIConfig) async throws {
        guard config.provider == .bedrock else {
            throw AIServiceError.invalidConfiguration("Expected Bedrock configuration")
        }

        guard let credentials = config.credentials,
              let accessKeyId = credentials.accessKeyId,
              let secretAccessKey = credentials.secretAccessKey,
              let region = config.region else {
            throw AIServiceError.invalidConfiguration("Missing required credentials or region")
        }

        self.config = config

        // Initialize custom AWS Bedrock client
        client = AWSBedrockClient(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region
        )

        print("✓ Initialized AWS Bedrock service in region: \(region)")
    }
    
    public func generateSQL(
        naturalLanguage: String,
        schema: DatabaseSchema,
        context: QueryContext?,
        databaseType: DatabaseType = .sqlite
    ) async throws -> String {
        guard let client = client, let config = config else {
            throw AIServiceError.notInitialized
        }

        let prompt = buildSQLGenerationPrompt(
            naturalLanguage: naturalLanguage,
            schema: schema,
            context: context,
            databaseType: databaseType
        )

        do {
            let response = try await invokeModel(client: client, modelId: config.model, prompt: prompt)
            return extractSQL(from: response)
        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
    }
    
    public func explainQuery(sql: String) async throws -> String {
        guard let client = client, let config = config else {
            throw AIServiceError.notInitialized
        }
        
        let prompt = """
        Explain the following SQL query in simple terms:
        
        \(sql)
        
        Provide a clear, concise explanation of what this query does.
        """
        
        do {
            return try await invokeModel(client: client, modelId: config.model, prompt: prompt)
        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
    }
    
    public func suggestOptimizations(sql: String, schema: DatabaseSchema) async throws -> [String] {
        guard let client = client, let config = config else {
            throw AIServiceError.notInitialized
        }
        
        let prompt = """
        Analyze the following SQL query and suggest optimizations:
        
        SQL Query:
        \(sql)
        
        Database Schema:
        \(schema.textDescription())
        
        Provide a list of specific optimization suggestions. Format each suggestion on a new line starting with "- ".
        """
        
        do {
            let response = try await invokeModel(client: client, modelId: config.model, prompt: prompt)
            return response.components(separatedBy: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("-") }
                .map { $0.trimmingCharacters(in: .whitespaces).dropFirst(1).trimmingCharacters(in: .whitespaces) }
                .map { String($0) }
        } catch {
            throw AIServiceError.generationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Helpers
    
    private func buildSQLGenerationPrompt(
        naturalLanguage: String,
        schema: DatabaseSchema,
        context: QueryContext?,
        databaseType: DatabaseType
    ) -> String {
        let dbTypeInfo = getSQLDialectInfo(for: databaseType)

        var prompt = """
        You are a SQL expert. Generate a SQL query based on the user's natural language request.

        Database Type: \(dbTypeInfo.name)

        Database Schema:
        \(schema.textDescription())

        User Request: \(naturalLanguage)

        """

        if let context = context, !context.previousQueries.isEmpty {
            prompt += "\nPrevious Queries:\n"
            for query in context.previousQueries.suffix(3) {
                prompt += "- \(query)\n"
            }
        }

        prompt += """

        Instructions:
        - Generate ONLY the SQL query, no explanations
        - Use proper SQL syntax for \(dbTypeInfo.name)
        \(dbTypeInfo.syntaxNotes)
        - Return only the SQL statement
        - Do not include markdown code blocks or formatting
        """

        return prompt
    }

    /// Get SQL dialect information for the database type
    private func getSQLDialectInfo(for databaseType: DatabaseType) -> (name: String, syntaxNotes: String) {
        switch databaseType {
        case .mysql:
            return (
                name: "MySQL",
                syntaxNotes: """
                - Use backticks (`) to quote identifiers if needed
                - Use LIMIT for pagination (e.g., LIMIT 10 OFFSET 20)
                - Use IFNULL() instead of COALESCE() when possible
                - String concatenation uses CONCAT() function
                - Use NOW() for current timestamp
                - Boolean values are 1 and 0
                """
            )
        case .postgresql:
            return (
                name: "PostgreSQL",
                syntaxNotes: """
                - Use double quotes (") to quote identifiers if needed
                - Use LIMIT/OFFSET for pagination
                - Use COALESCE() for null handling
                - String concatenation uses || operator
                - Use NOW() or CURRENT_TIMESTAMP for current timestamp
                - Boolean values are TRUE and FALSE
                - Use ILIKE for case-insensitive matching
                """
            )
        case .sqlite:
            return (
                name: "SQLite",
                syntaxNotes: """
                - Use double quotes (") or square brackets [] for identifiers if needed
                - Use LIMIT/OFFSET for pagination
                - Use IFNULL() or COALESCE() for null handling
                - String concatenation uses || operator
                - Use datetime('now') for current timestamp
                - Boolean values are 1 and 0
                """
            )
        case .duckdb:
            return (
                name: "DuckDB",
                syntaxNotes: """
                - Use double quotes (") to quote identifiers if needed
                - Use LIMIT/OFFSET for pagination
                - Supports modern SQL features like QUALIFY, EXCLUDE
                - String concatenation uses || operator
                - Use NOW() for current timestamp
                """
            )
        case .elasticache:
            return (
                name: "ElastiCache (Redis)",
                syntaxNotes: """
                - This is a key-value store, not a SQL database
                - Generate appropriate Redis-style commands if possible
                """
            )
        }
    }
    
    private func invokeModel(client: AWSBedrockClient, modelId: String, prompt: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            client.invokeText(prompt: prompt) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func extractSQL(from response: String) -> String {
        // Remove markdown code blocks if present
        var sql = response
        if sql.contains("```sql") {
            sql = sql.replacingOccurrences(of: "```sql", with: "")
                .replacingOccurrences(of: "```", with: "")
        }
        return sql.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


import Foundation

/// Query request from user
public struct QueryRequest {
    public let naturalLanguage: String
    public let context: QueryContext?
    
    public init(naturalLanguage: String, context: QueryContext? = nil) {
        self.naturalLanguage = naturalLanguage
        self.context = context
    }
}

/// Additional context for query generation
public struct QueryContext {
    public let previousQueries: [String]
    public let focusTables: [String]?
    
    public init(previousQueries: [String] = [], focusTables: [String]? = nil) {
        self.previousQueries = previousQueries
        self.focusTables = focusTables
    }
}

/// Query response to user
public struct QueryResponse {
    public let generatedSQL: String
    public let result: QueryResult
    public let explanation: String?
    
    public init(generatedSQL: String, result: QueryResult, explanation: String? = nil) {
        self.generatedSQL = generatedSQL
        self.result = result
        self.explanation = explanation
    }
}

/// Query execution result
public struct QueryResult {
    public let columns: [String]
    public let rows: [[Any]]
    public let rowCount: Int
    public let executionTime: TimeInterval
    
    public init(columns: [String], rows: [[Any]], executionTime: TimeInterval) {
        self.columns = columns
        self.rows = rows
        self.rowCount = rows.count
        self.executionTime = executionTime
    }
    
    /// Format result as a table string
    public func formatAsTable() -> String {
        guard !columns.isEmpty else { return "No results" }
        
        var output = ""
        
        // Header
        output += columns.joined(separator: " | ") + "\n"
        output += String(repeating: "-", count: columns.joined(separator: " | ").count) + "\n"
        
        // Rows
        for row in rows {
            let rowStrings = row.map { "\($0)" }
            output += rowStrings.joined(separator: " | ") + "\n"
        }
        
        output += "\n(\(rowCount) rows in \(String(format: "%.3f", executionTime))s)"
        
        return output
    }
}


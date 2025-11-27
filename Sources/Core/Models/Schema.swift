import Foundation

/// Database schema representation
public struct DatabaseSchema: Codable {
    public let tables: [TableSchema]
    
    public init(tables: [TableSchema]) {
        self.tables = tables
    }
    
    /// Get a table by name
    public func table(named name: String) -> TableSchema? {
        tables.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// Generate a text description of the schema for AI context
    public func textDescription() -> String {
        var description = "Database Schema:\n\n"
        for table in tables {
            description += "Table: \(table.name)\n"
            description += "Columns:\n"
            for column in table.columns {
                let nullable = column.isNullable ? "NULL" : "NOT NULL"
                let pk = column.isPrimaryKey ? " PRIMARY KEY" : ""
                description += "  - \(column.name): \(column.type) \(nullable)\(pk)\n"
            }
            if !table.foreignKeys.isEmpty {
                description += "Foreign Keys:\n"
                for fk in table.foreignKeys {
                    description += "  - \(fk.column) -> \(fk.referencedTable).\(fk.referencedColumn)\n"
                }
            }
            description += "\n"
        }
        return description
    }
}

/// Table schema representation
public struct TableSchema: Codable {
    public let name: String
    public let columns: [ColumnSchema]
    public let foreignKeys: [ForeignKeySchema]
    
    public init(name: String, columns: [ColumnSchema], foreignKeys: [ForeignKeySchema] = []) {
        self.name = name
        self.columns = columns
        self.foreignKeys = foreignKeys
    }
    
    /// Get a column by name
    public func column(named name: String) -> ColumnSchema? {
        columns.first { $0.name.lowercased() == name.lowercased() }
    }
}

/// Column schema representation
public struct ColumnSchema: Codable {
    public let name: String
    public let type: String
    public let isNullable: Bool
    public let isPrimaryKey: Bool
    public let defaultValue: String?
    
    public init(
        name: String,
        type: String,
        isNullable: Bool = true,
        isPrimaryKey: Bool = false,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
        self.defaultValue = defaultValue
    }
}

/// Foreign key schema representation
public struct ForeignKeySchema: Codable {
    public let column: String
    public let referencedTable: String
    public let referencedColumn: String
    
    public init(column: String, referencedTable: String, referencedColumn: String) {
        self.column = column
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
    }
}


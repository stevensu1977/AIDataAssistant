import Foundation
import SQLite

/// SQLite database implementation
public class SQLiteDatabase: DatabaseProtocol {
    private var connection: Connection?
    private var config: DatabaseConfig?

    public var isConnected: Bool {
        connection != nil
    }

    public var databaseType: DatabaseType {
        .sqlite
    }

    public init() {}
    
    public func connect(config: DatabaseConfig) async throws {
        guard config.type == .sqlite else {
            throw DatabaseError.invalidConfiguration("Expected SQLite configuration")
        }
        
        self.config = config
        
        do {
            let readOnly = config.options?["readOnly"] == "true"
            connection = try Connection(config.connectionString, readonly: readOnly)
            print("✓ Connected to SQLite database: \(config.connectionString)")
        } catch {
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }
    
    public func disconnect() async throws {
        connection = nil
        config = nil
        print("✓ Disconnected from database")
    }
    
    public func testConnection() async throws -> Bool {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }
        
        do {
            _ = try connection.scalar("SELECT 1") as? Int64
            return true
        } catch {
            return false
        }
    }
    
    public func executeQuery(_ sql: String) async throws -> QueryResult {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }
        
        let startTime = Date()
        
        do {
            let statement = try connection.prepare(sql)
            var columns: [String] = []
            var rows: [[Any]] = []
            
            // Get column names
            columns = statement.columnNames
            
            // Get rows
            for row in statement {
                var rowData: [Any] = []
                for (index, _) in columns.enumerated() {
                    if let value = row[index] {
                        rowData.append(value)
                    } else {
                        rowData.append("NULL")
                    }
                }
                rows.append(rowData)
            }
            
            let executionTime = Date().timeIntervalSince(startTime)
            return QueryResult(columns: columns, rows: rows, executionTime: executionTime)
            
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }
    
    public func getSchema() async throws -> DatabaseSchema {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }
        
        do {
            var tables: [TableSchema] = []
            
            // Get all table names
            let tableQuery = """
                SELECT name FROM sqlite_master 
                WHERE type='table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
            """
            
            let tableStatement = try connection.prepare(tableQuery)
            
            for tableRow in tableStatement {
                guard let tableName = tableRow[0] as? String else { continue }
                
                // Get columns for this table
                let columns = try getColumns(for: tableName, connection: connection)
                
                // Get foreign keys for this table
                let foreignKeys = try getForeignKeys(for: tableName, connection: connection)
                
                tables.append(TableSchema(name: tableName, columns: columns, foreignKeys: foreignKeys))
            }
            
            return DatabaseSchema(tables: tables)
            
        } catch {
            throw DatabaseError.schemaExtractionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Helpers
    
    private func getColumns(for tableName: String, connection: Connection) throws -> [ColumnSchema] {
        let pragmaQuery = "PRAGMA table_info('\(tableName)')"
        let statement = try connection.prepare(pragmaQuery)
        
        var columns: [ColumnSchema] = []
        
        for row in statement {
            guard let name = row[1] as? String,
                  let type = row[2] as? String else { continue }
            
            let notNull = (row[3] as? Int64) == 1
            let isPrimaryKey = (row[5] as? Int64) == 1
            let defaultValue = row[4] as? String
            
            columns.append(ColumnSchema(
                name: name,
                type: type,
                isNullable: !notNull,
                isPrimaryKey: isPrimaryKey,
                defaultValue: defaultValue
            ))
        }
        
        return columns
    }
    
    private func getForeignKeys(for tableName: String, connection: Connection) throws -> [ForeignKeySchema] {
        let pragmaQuery = "PRAGMA foreign_key_list('\(tableName)')"
        let statement = try connection.prepare(pragmaQuery)
        
        var foreignKeys: [ForeignKeySchema] = []
        
        for row in statement {
            guard let referencedTable = row[2] as? String,
                  let column = row[3] as? String,
                  let referencedColumn = row[4] as? String else { continue }
            
            foreignKeys.append(ForeignKeySchema(
                column: column,
                referencedTable: referencedTable,
                referencedColumn: referencedColumn
            ))
        }
        
        return foreignKeys
    }
}


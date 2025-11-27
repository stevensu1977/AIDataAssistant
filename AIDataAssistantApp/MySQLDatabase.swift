import Foundation
import MySQLNIO
import MySQLKit
import NIOCore
import NIOPosix

/// MySQL database implementation
class MySQLDatabase: DatabaseProtocol {
    private var eventLoopGroup: EventLoopGroup?
    private var connection: MySQLConnection?
    private var config: MySQLConfig?
    
    var isConnected: Bool {
        connection != nil
    }
    
    init() {
        // Empty initializer
    }
    
    deinit {
        // Clean up resources
        Task {
            try? await disconnect()
        }
    }
    
    func connect(config: DatabaseConfig) async throws {
        guard config.type == .mysql else {
            throw DatabaseError.invalidConfiguration("Expected MySQL configuration")
        }
        
        // Parse MySQL config from options
        guard let options = config.options,
              let host = options["host"],
              let portString = options["port"],
              let port = Int(portString),
              let username = options["username"],
              let password = options["password"],
              let database = options["database"],
              let sslString = options["ssl"],
              let ssl = Bool(sslString) else {
            throw DatabaseError.invalidConfiguration("Missing required MySQL configuration options")
        }
        
        let mysqlConfig = MySQLConfig(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            ssl: ssl
        )
        
        self.config = mysqlConfig
        
        // Create event loop group
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group
        
        // Create MySQL configuration
        let tlsConfig: TLSConfiguration? = ssl ? .makeClientConfiguration() : nil
        let mysqlNIOConfig = MySQLConnection.Configuration(
            address: .makeAddressResolvingHost(host, port: port),
            username: username,
            password: password,
            database: database,
            tlsConfiguration: tlsConfig
        )
        
        do {
            // Connect to MySQL
            let conn = try await MySQLConnection.connect(
                configuration: mysqlNIOConfig,
                on: group.next()
            ).get()
            
            self.connection = conn
        } catch {
            // Clean up on failure
            try? await eventLoopGroup?.shutdownGracefully()
            self.eventLoopGroup = nil
            throw DatabaseError.connectionFailed("Failed to connect to MySQL: \(error.localizedDescription)")
        }
    }
    
    func disconnect() async throws {
        try await connection?.close()
        connection = nil
        
        try await eventLoopGroup?.shutdownGracefully()
        eventLoopGroup = nil
    }
    
    func executeQuery(_ query: String) async throws -> QueryResult {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }
        
        do {
            let rows = try await connection.query(query).get()
            
            // Convert MySQL rows to QueryResult
            var columns: [String] = []
            var resultRows: [[String: Any]] = []
            
            for row in rows {
                var rowDict: [String: Any] = [:]
                
                // Get column names from first row
                if columns.isEmpty {
                    columns = row.columnDefinitions.map { $0.name }
                }
                
                // Extract values
                for (index, column) in columns.enumerated() {
                    if let value = row.column(column) {
                        rowDict[column] = convertMySQLValue(value)
                    } else {
                        rowDict[column] = NSNull()
                    }
                }
                
                resultRows.append(rowDict)
            }
            
            return QueryResult(
                columns: columns,
                rows: resultRows,
                rowCount: resultRows.count,
                executionTime: 0.0
            )
        } catch {
            throw DatabaseError.queryFailed("MySQL query failed: \(error.localizedDescription)")
        }
    }
    
    func getSchema() async throws -> DatabaseSchema {
        guard let config = config else {
            throw DatabaseError.notConnected
        }
        
        // Query to get all tables
        let tablesQuery = """
            SELECT TABLE_NAME, TABLE_TYPE, TABLE_COMMENT
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = '\(config.database)'
            ORDER BY TABLE_NAME
            """
        
        let tablesResult = try await executeQuery(tablesQuery)
        var tables: [TableInfo] = []

        for row in tablesResult.rows {
            guard let tableName = row["TABLE_NAME"] as? String else { continue }

            // Query to get columns for this table
            let columnsQuery = """
                SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_COMMENT
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = '\(config.database)' AND TABLE_NAME = '\(tableName)'
                ORDER BY ORDINAL_POSITION
                """

            let columnsResult = try await executeQuery(columnsQuery)
            var columns: [ColumnInfo] = []

            for columnRow in columnsResult.rows {
                guard let columnName = columnRow["COLUMN_NAME"] as? String,
                      let dataType = columnRow["DATA_TYPE"] as? String else { continue }

                let isNullable = (columnRow["IS_NULLABLE"] as? String) == "YES"
                let isPrimaryKey = (columnRow["COLUMN_KEY"] as? String) == "PRI"

                columns.append(ColumnInfo(
                    name: columnName,
                    type: dataType,
                    nullable: isNullable,
                    primaryKey: isPrimaryKey
                ))
            }

            tables.append(TableInfo(
                name: tableName,
                columns: columns,
                rowCount: 0 // MySQL doesn't provide accurate row count in schema query
            ))
        }

        return DatabaseSchema(
            databaseName: config.database,
            tables: tables
        )
    }

    func testConnection() async throws -> String {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }

        // Execute a simple query to test connection
        let result = try await connection.query("SELECT VERSION() as version").get()

        if let firstRow = result.first,
           let version = firstRow.column("version") {
            return "Connected to MySQL \(version)"
        }

        return "Connected to MySQL"
    }

    // MARK: - Helper Methods

    private func convertMySQLValue(_ value: MySQLData) -> Any {
        // Try to convert to common Swift types
        if let string = value.string {
            return string
        } else if let int = value.int {
            return int
        } else if let double = value.double {
            return double
        } else if let bool = value.bool {
            return bool
        } else if let date = value.date {
            return date
        } else if let time = value.time {
            return time
        } else {
            return NSNull()
        }
    }
}


import Foundation
import MySQLNIO
import MySQLKit
import NIOCore
import NIOPosix

/// MySQL database implementation
public class MySQLDatabase: DatabaseProtocol {
    private var eventLoopGroup: EventLoopGroup?
    private var connection: MySQLConnection?
    private var config: MySQLConfig?
    
    public var isConnected: Bool {
        connection != nil
    }
    
    public init() {
        // Empty initializer
    }
    
    deinit {
        // Clean up resources
        Task {
            try? await disconnect()
        }
    }
    
    public func connect(config: DatabaseConfig) async throws {
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
            try? await group.shutdownGracefully()
            self.eventLoopGroup = nil
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }
    
    public func disconnect() async throws {
        if let connection = connection {
            try await connection.close().get()
            self.connection = nil
        }
        
        if let group = eventLoopGroup {
            try await group.shutdownGracefully()
            self.eventLoopGroup = nil
        }
    }
    
    public func executeQuery(_ sql: String) async throws -> QueryResult {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }
        
        let startTime = Date()
        
        do {
            // Execute query
            let rows = try await connection.query(sql).get()
            
            // Parse columns
            let columns = rows.columns?.map { $0.name } ?? []
            
            // Parse rows
            var data: [[Any]] = []
            for row in rows {
                var rowData: [Any] = []
                for column in columns {
                    if let value = row.column(column) {
                        rowData.append(value.description)
                    } else {
                        rowData.append("NULL")
                    }
                }
                data.append(rowData)
            }
            
            let executionTime = Date().timeIntervalSince(startTime)
            
            return QueryResult(
                columns: columns,
                rows: data,
                rowCount: data.count,
                executionTime: executionTime
            )
        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }
    
    public func getSchema() async throws -> DatabaseSchema {
        guard let config = config else {
            throw DatabaseError.notConnected
        }
        
        // Get all tables
        let tablesQuery = """
        SELECT TABLE_NAME 
        FROM INFORMATION_SCHEMA.TABLES 
        WHERE TABLE_SCHEMA = '\(config.database)'
        ORDER BY TABLE_NAME
        """
        
        let tablesResult = try await executeQuery(tablesQuery)

        var tables: [TableSchema] = []

        for row in tablesResult.rows {
            guard let tableName = row.first as? String else { continue }

            // Get columns for this table
            let columnsQuery = """
            SELECT
                COLUMN_NAME,
                DATA_TYPE,
                IS_NULLABLE,
                COLUMN_KEY,
                COLUMN_DEFAULT,
                EXTRA
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = '\(config.database)'
            AND TABLE_NAME = '\(tableName)'
            ORDER BY ORDINAL_POSITION
            """

            let columnsResult = try await executeQuery(columnsQuery)

            let columns = columnsResult.rows.map { row -> ColumnSchema in
                let name = row[0] as? String ?? ""
                let type = row[1] as? String ?? ""
                let nullable = (row[2] as? String) == "YES"
                let isPrimaryKey = (row[3] as? String) == "PRI"

                return ColumnSchema(
                    name: name,
                    type: type,
                    nullable: nullable,
                    primaryKey: isPrimaryKey
                )
            }

            tables.append(TableSchema(name: tableName, columns: columns))
        }

        return DatabaseSchema(tables: tables)
    }

    public func testConnection() async throws -> Bool {
        guard let connection = connection else {
            return false
        }

        do {
            // Execute a simple query to test connection
            _ = try await connection.query("SELECT 1").get()
            return true
        } catch {
            return false
        }
    }
}


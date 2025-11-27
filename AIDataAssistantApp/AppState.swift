import Foundation
import SQLite
import MySQLNIO
import PostgresNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

/// Global application state
@MainActor
class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var currentDatabase: String?
    @Published var queryEngine: QueryEngine?
    @Published var schema: DatabaseSchema?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    // Database Manager
    @Published var databaseManager: DatabaseManager

    // Settings
    @Published var databasePath: String = ""
    @Published var awsRegion: String = "us-east-1"
    @Published var awsAccessKeyId: String = ""
    @Published var awsSecretAccessKey: String = ""
    @Published var bedrockModel: String = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

    init() {
        self.databaseManager = DatabaseManager()
        loadSettings()

        // Observe database manager connection state
        NotificationCenter.default.addObserver(
            forName: .databaseConnectionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.updateQueryEngine()
            }
        }
    }

    private func updateQueryEngine() async {
        // Check if we have a database connection
        guard let database = databaseManager.getCurrentDatabase(),
              database.isConnected else {
            // No database or not connected - clear state
            queryEngine = nil
            schema = nil
            isConnected = false
            return
        }

        do {
            // Setup AI service
            let aiConfig = BedrockConfig(
                region: awsRegion,
                model: BedrockModel(rawValue: bedrockModel) ?? .claude45Sonnet,
                accessKeyId: awsAccessKeyId,
                secretAccessKey: awsSecretAccessKey
            )
            let aiService = BedrockAIService()
            try await aiService.initialize(config: aiConfig.aiConfig)

            // Create query engine
            let engine = QueryEngine(database: database, aiService: aiService)

            // Load schema - check connection again before calling
            guard database.isConnected else {
                queryEngine = nil
                schema = nil
                isConnected = false
                return
            }

            let loadedSchema = try await engine.getSchema()

            // Update state - check connection one more time
            guard database.isConnected else {
                queryEngine = nil
                schema = nil
                isConnected = false
                return
            }

            self.queryEngine = engine
            self.schema = loadedSchema
            self.isConnected = true

        } catch {
            // Only show error if we're still supposed to be connected
            if databaseManager.connectionState == .connected {
                errorMessage = error.localizedDescription
            }
            queryEngine = nil
            schema = nil
            isConnected = false
        }
    }

    func connect() async {
        isLoading = true
        errorMessage = nil

        do {
            // Validate settings
            guard !databasePath.isEmpty else {
                throw AppError.invalidConfiguration("Database path is required")
            }
            guard !awsAccessKeyId.isEmpty, !awsSecretAccessKey.isEmpty else {
                throw AppError.invalidConfiguration("AWS credentials are required")
            }

            // Create SQLite connection
            let dbConfig = SQLiteConfig(path: databasePath)
            let connection = DatabaseConnection(
                name: "SQLite Database",
                type: .sqlite,
                config: dbConfig.databaseConfig
            )

            // Connect using database manager
            await databaseManager.connect(to: connection)

            // Update query engine
            await updateQueryEngine()

            // Save settings
            saveSettings()

        } catch {
            errorMessage = error.localizedDescription
            isConnected = false
        }

        isLoading = false
    }

    func disconnect() {
        Task {
            await databaseManager.disconnect()
        }
        queryEngine = nil
        schema = nil
        currentDatabase = nil
        isConnected = false
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        databasePath = defaults.string(forKey: "databasePath") ?? ""
        awsRegion = defaults.string(forKey: "awsRegion") ?? "us-east-1"
        awsAccessKeyId = defaults.string(forKey: "awsAccessKeyId") ?? ""
        awsSecretAccessKey = defaults.string(forKey: "awsSecretAccessKey") ?? ""
        bedrockModel = defaults.string(forKey: "bedrockModel") ?? "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(databasePath, forKey: "databasePath")
        defaults.set(awsRegion, forKey: "awsRegion")
        defaults.set(awsAccessKeyId, forKey: "awsAccessKeyId")
        defaults.set(awsSecretAccessKey, forKey: "awsSecretAccessKey")
        defaults.set(bedrockModel, forKey: "bedrockModel")
    }
}

enum AppError: LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        }
    }
}

// Notification for database connection changes
extension Notification.Name {
    static let databaseConnectionChanged = Notification.Name("databaseConnectionChanged")
}

// MARK: - Database Manager

/// Connection state
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Database connection information
struct DatabaseConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: DatabaseType
    let config: DatabaseConfig

    init(id: UUID = UUID(), name: String, type: DatabaseType, config: DatabaseConfig) {
        self.id = id
        self.name = name
        self.type = type
        self.config = config
    }

    static func == (lhs: DatabaseConnection, rhs: DatabaseConnection) -> Bool {
        lhs.id == rhs.id
    }
}

/// Database manager for handling multiple database connections
@MainActor
class DatabaseManager: ObservableObject {
    @Published var currentConnection: DatabaseConnection?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var availableConnections: [DatabaseConnection] = []

    private var currentDatabase: DatabaseProtocol?

    init() {
        loadConnections()
    }

    /// Connect to a database
    func connect(to connection: DatabaseConnection) async {
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

            // Notify observers
            NotificationCenter.default.post(name: .databaseConnectionChanged, object: nil)
        } catch {
            connectionState = .error(error.localizedDescription)
            currentDatabase = nil
            currentConnection = nil
        }
    }

    /// Disconnect from current database
    func disconnect() async {
        if let database = currentDatabase {
            try? await database.disconnect()
        }

        currentDatabase = nil
        currentConnection = nil
        connectionState = .disconnected

        // Notify observers
        NotificationCenter.default.post(name: .databaseConnectionChanged, object: nil)
    }

    /// Get current database instance
    func getCurrentDatabase() -> DatabaseProtocol? {
        return currentDatabase
    }

    /// Add a new connection
    func addConnection(_ connection: DatabaseConnection) {
        availableConnections.append(connection)
        saveConnections()
    }

    /// Remove a connection
    func removeConnection(_ connection: DatabaseConnection) {
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
    func updateConnection(_ connection: DatabaseConnection) {
        if let index = availableConnections.firstIndex(where: { $0.id == connection.id }) {
            availableConnections[index] = connection
            saveConnections()
        }
    }

    /// Test a connection without connecting
    func testConnection(_ connection: DatabaseConnection) async -> Swift.Result<String, Error> {
        let database = createDatabase(for: connection.type)

        do {
            try await database.connect(config: connection.config)
            let isValid = try await database.testConnection()
            try await database.disconnect()

            if isValid {
                return .success("Connection successful!")
            } else {
                return .failure(NSError(domain: "DatabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection test failed"]))
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
        case .postgresql:
            return PostgreSQLDatabase()
        case .duckdb:
            return DuckDBDatabase()
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

// MARK: - MySQL Database Implementation

/// MySQL database implementation
class MySQLDatabase: DatabaseProtocol {
    private var eventLoopGroup: EventLoopGroup?
    private var connection: MySQLConnection?
    private var config: MySQLConfig?

    var isConnected: Bool {
        guard let conn = connection else { return false }
        return !conn.isClosed
    }

    var databaseType: DatabaseType {
        .mysql
    }

    init() {
        // Empty initializer
    }

    deinit {
        // Clean up resources synchronously
        // Note: We need to close the connection before deinit completes
        if let conn = connection, !conn.isClosed {
            // Use synchronous close via the event loop
            _ = conn.close()
        }
        // Shutdown event loop group
        if let group = eventLoopGroup {
            try? group.syncShutdownGracefully()
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

        do {
            // Connect to MySQL using MySQLNIO
            let conn = try await MySQLConnection.connect(
                to: .makeAddressResolvingHost(host, port: port),
                username: username,
                database: database,
                password: password,
                tlsConfiguration: ssl ? .makeClientConfiguration() : nil,
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
        if let conn = connection {
            // Check if connection is still active before closing
            if !conn.isClosed {
                do {
                    // Close the connection properly - this returns EventLoopFuture<Void>
                    _ = try await conn.close().get()
                } catch {
                    // Ignore close errors, connection might already be closed
                    print("Warning: Error closing MySQL connection: \(error)")
                }
            }
            connection = nil
        }

        if let group = eventLoopGroup {
            do {
                try await group.shutdownGracefully()
            } catch {
                print("Warning: Error shutting down event loop: \(error)")
            }
            eventLoopGroup = nil
        }
    }

    func executeQuery(_ query: String) async throws -> QueryResult {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }

        let startTime = Date()

        do {
            let rows = try await connection.query(query).get()

            // Convert MySQL rows to QueryResult
            var columns: [String] = []
            var resultRows: [[Any]] = []

            for row in rows {
                // Get column names from first row
                if columns.isEmpty {
                    columns = row.columnDefinitions.map { $0.name }
                }

                // Extract values in column order
                var rowValues: [Any] = []
                for column in columns {
                    if let value = row.column(column) {
                        rowValues.append(convertMySQLValue(value))
                    } else {
                        rowValues.append(NSNull())
                    }
                }

                resultRows.append(rowValues)
            }

            let executionTime = Date().timeIntervalSince(startTime)

            return QueryResult(
                columns: columns,
                rows: resultRows,
                executionTime: executionTime
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
            SELECT TABLE_NAME
            FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = '\(config.database)'
            ORDER BY TABLE_NAME
            """

        let tablesResult = try await executeQuery(tablesQuery)
        var tables: [TableSchema] = []

        for row in tablesResult.rows {
            guard let tableName = row.first as? String else { continue }

            // Query to get columns for this table
            let columnsQuery = """
                SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = '\(config.database)' AND TABLE_NAME = '\(tableName)'
                ORDER BY ORDINAL_POSITION
                """

            let columnsResult = try await executeQuery(columnsQuery)
            var columns: [ColumnSchema] = []

            for columnRow in columnsResult.rows {
                guard columnRow.count >= 4,
                      let columnName = columnRow[0] as? String,
                      let dataType = columnRow[1] as? String else { continue }

                let isNullable = (columnRow[2] as? String) == "YES"
                let isPrimaryKey = (columnRow[3] as? String) == "PRI"

                columns.append(ColumnSchema(
                    name: columnName,
                    type: dataType,
                    isNullable: isNullable,
                    isPrimaryKey: isPrimaryKey
                ))
            }

            tables.append(TableSchema(
                name: tableName,
                columns: columns,
                foreignKeys: []
            ))
        }

        return DatabaseSchema(tables: tables)
    }

    func testConnection() async throws -> Bool {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }

        // Execute a simple query to test connection
        _ = try await connection.query("SELECT 1").get()
        return true
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

// MARK: - PostgreSQL Configuration

struct PostgreSQLConfig {
    let host: String
    let port: Int
    let username: String
    let password: String
    let database: String
    let ssl: Bool

    var databaseConfig: DatabaseConfig {
        DatabaseConfig(
            type: .postgresql,
            connectionString: "postgresql://\(username):\(password)@\(host):\(port)/\(database)",
            options: [
                "host": host,
                "port": String(port),
                "username": username,
                "password": password,
                "database": database,
                "ssl": String(ssl)
            ]
        )
    }
}

// MARK: - PostgreSQL Database Implementation

/// PostgreSQL database implementation using PostgresNIO
class PostgreSQLDatabase: DatabaseProtocol {
    private var eventLoopGroup: EventLoopGroup?
    private var connection: PostgresConnection?
    private var config: PostgreSQLConfig?
    private let logger = Logger(label: "PostgreSQLDatabase")

    var isConnected: Bool {
        connection != nil
    }

    var databaseType: DatabaseType {
        .postgresql
    }

    init() {
        // Empty initializer
    }

    deinit {
        // Clean up resources synchronously
        if connection != nil {
            connection = nil
        }
        if let group = eventLoopGroup {
            try? group.syncShutdownGracefully()
        }
    }

    func connect(config: DatabaseConfig) async throws {
        guard config.type == .postgresql else {
            throw DatabaseError.invalidConfiguration("Expected PostgreSQL configuration")
        }

        // Parse PostgreSQL config from options
        guard let options = config.options,
              let host = options["host"],
              let portString = options["port"],
              let port = Int(portString),
              let username = options["username"],
              let password = options["password"],
              let database = options["database"],
              let sslString = options["ssl"],
              let ssl = Bool(sslString) else {
            throw DatabaseError.invalidConfiguration("Missing required PostgreSQL configuration options")
        }

        let pgConfig = PostgreSQLConfig(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            ssl: ssl
        )

        self.config = pgConfig

        // Create event loop group
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        do {
            // Create PostgreSQL connection configuration
            let tlsMode: PostgresConnection.Configuration.TLS
            if ssl {
                var tlsConfig = TLSConfiguration.makeClientConfiguration()
                tlsConfig.certificateVerification = .none  // For self-signed certs
                tlsMode = .require(try NIOSSLContext(configuration: tlsConfig))
            } else {
                tlsMode = .disable
            }

            let pgConfiguration = PostgresConnection.Configuration(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: tlsMode
            )

            // Connect to PostgreSQL
            let conn = try await PostgresConnection.connect(
                configuration: pgConfiguration,
                id: 1,
                logger: logger
            )

            self.connection = conn
        } catch {
            // Clean up on failure
            try? await eventLoopGroup?.shutdownGracefully()
            self.eventLoopGroup = nil
            throw DatabaseError.connectionFailed("Failed to connect to PostgreSQL: \(error.localizedDescription)")
        }
    }

    func disconnect() async throws {
        if let conn = connection {
            try await conn.close()
            connection = nil
        }

        if let group = eventLoopGroup {
            do {
                try await group.shutdownGracefully()
            } catch {
                print("Warning: Error shutting down event loop: \(error)")
            }
            eventLoopGroup = nil
        }
    }


    func executeQuery(_ query: String) async throws -> QueryResult {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }

        let startTime = Date()

        do {
            // Collect all rows from the async sequence
            var resultRows: [[Any]] = []
            var columns: [String] = []

            let stream = try await connection.query(PostgresQuery(stringLiteral: query), logger: logger)

            for try await row in stream {
                let randomAccess = row.makeRandomAccess()

                // Extract values from each column
                var rowValues: [Any] = []
                for i in 0..<randomAccess.count {
                    let cell = randomAccess[i]
                    // Try different types
                    if let value = try? cell.decode(String.self) {
                        rowValues.append(value)
                    } else if let value = try? cell.decode(Int.self) {
                        rowValues.append(value)
                    } else if let value = try? cell.decode(Int64.self) {
                        rowValues.append(value)
                    } else if let value = try? cell.decode(Double.self) {
                        rowValues.append(value)
                    } else if let value = try? cell.decode(Bool.self) {
                        rowValues.append(value)
                    } else {
                        // Try as optional string (handles NULL)
                        if let value = try? cell.decode(String?.self) {
                            rowValues.append(value ?? NSNull())
                        } else {
                            rowValues.append(NSNull())
                        }
                    }
                }
                resultRows.append(rowValues)
            }

            // Generate column names as "col0", "col1", etc. for now
            // PostgresNIO doesn't easily expose column names in the current API
            if let firstRow = resultRows.first {
                columns = (0..<firstRow.count).map { "col\($0)" }
            }

            let executionTime = Date().timeIntervalSince(startTime)

            return QueryResult(
                columns: columns,
                rows: resultRows,
                executionTime: executionTime
            )
        } catch let error as PSQLError {
            // Get detailed PostgreSQL error information
            let message = error.serverInfo?[.message] ?? "Unknown error"
            let detail = error.serverInfo?[.detail] ?? ""
            let hint = error.serverInfo?[.hint] ?? ""
            var errorMsg = "PostgreSQL: \(message)"
            if !detail.isEmpty { errorMsg += " - \(detail)" }
            if !hint.isEmpty { errorMsg += " (\(hint))" }
            print("PSQLError: \(error)")
            throw DatabaseError.queryFailed(errorMsg)
        } catch {
            // Print full error details for debugging
            print("PostgreSQL query error type: \(type(of: error))")
            print("PostgreSQL query error: \(error)")
            throw DatabaseError.queryFailed("PostgreSQL: \(String(describing: error))")
        }
    }

    func getSchema() async throws -> DatabaseSchema {
        guard connection != nil else {
            throw DatabaseError.notConnected
        }

        var tables: [TableSchema] = []

        do {
            // Query to get all tables
            let tablesQuery = """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_type = 'BASE TABLE'
                ORDER BY table_name
                """

            let tablesResult = try await executeQuery(tablesQuery)

            for row in tablesResult.rows {
                guard let tableName = row.first as? String else { continue }

                // Query to get columns for this table
                let columnsQuery = """
                    SELECT column_name, data_type, is_nullable,
                           CASE WHEN pk.column_name IS NOT NULL THEN 'YES' ELSE 'NO' END as is_primary_key
                    FROM information_schema.columns c
                    LEFT JOIN (
                        SELECT ku.column_name
                        FROM information_schema.table_constraints tc
                        JOIN information_schema.key_column_usage ku
                            ON tc.constraint_name = ku.constraint_name
                        WHERE tc.constraint_type = 'PRIMARY KEY'
                            AND tc.table_name = '\(tableName)'
                            AND tc.table_schema = 'public'
                    ) pk ON c.column_name = pk.column_name
                    WHERE c.table_schema = 'public' AND c.table_name = '\(tableName)'
                    ORDER BY c.ordinal_position
                    """

                let columnsResult = try await executeQuery(columnsQuery)
                var columns: [ColumnSchema] = []

                for columnRow in columnsResult.rows {
                    guard columnRow.count >= 4,
                          let columnName = columnRow[0] as? String,
                          let dataType = columnRow[1] as? String else { continue }

                    let isNullable = (columnRow[2] as? String) == "YES"
                    let isPrimaryKey = (columnRow[3] as? String) == "YES"

                    columns.append(ColumnSchema(
                        name: columnName,
                        type: dataType,
                        isNullable: isNullable,
                        isPrimaryKey: isPrimaryKey
                    ))
                }

                tables.append(TableSchema(
                    name: tableName,
                    columns: columns,
                    foreignKeys: []
                ))
            }
        } catch {
            print("Error getting schema: \(error)")
            // Return empty schema on error
        }

        return DatabaseSchema(tables: tables)
    }

    func testConnection() async throws -> Bool {
        guard let connection = connection else {
            throw DatabaseError.notConnected
        }

        // Execute a simple query to test connection
        do {
            let stream = try await connection.query("SELECT 1 as test", logger: logger)
            for try await _ in stream {
                // Just iterate to consume the result
            }
            return true
        } catch {
            throw DatabaseError.connectionFailed("Connection test failed: \(error.localizedDescription)")
        }
    }
}
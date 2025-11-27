import Foundation
import DuckDB

/// DuckDB database implementation
class DuckDBDatabase: DatabaseProtocol {
    private var database: Database?
    private var connection: Connection?
    private var config: DatabaseConfig?
    private var attachedSources: [DuckDBDataSource] = []
    private var _isConnected = false

    var isConnected: Bool {
        _isConnected
    }

    var databaseType: DatabaseType {
        .duckdb
    }

    init() {}

    // MARK: - DatabaseProtocol

    func connect(config: DatabaseConfig) async throws {
        guard config.type == .duckdb else {
            throw DatabaseError.invalidConfiguration("Expected DuckDB configuration")
        }

        self.config = config

        do {
            let mode = config.options?["mode"] ?? "memory"

            if mode == "memory" {
                database = try Database(store: .inMemory)
                print("✓ Connected to DuckDB in-memory database")
            } else {
                let path = config.connectionString
                let fileURL = URL(fileURLWithPath: path)
                database = try Database(store: .file(at: fileURL))
                print("✓ Connected to DuckDB file database: \(path)")
            }

            connection = try database?.connect()
            _isConnected = true

            // Attach any data sources from config
            if let sourcesJson = config.options?["dataSources"],
               let sourcesData = sourcesJson.data(using: .utf8),
               let sources = try? JSONDecoder().decode([DuckDBDataSource].self, from: sourcesData) {
                for source in sources {
                    try await attachDataSource(source)
                }
            }

        } catch {
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() async throws {
        attachedSources.removeAll()
        connection = nil
        database = nil
        config = nil
        _isConnected = false
        print("✓ Disconnected from DuckDB")
    }

    func executeQuery(_ sql: String) async throws -> QueryResult {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        let startTime = Date()

        do {
            print("🦆 [DuckDB] Executing: \(sql.prefix(200))...")
            let result = try conn.query(sql)

            var columns: [String] = []
            var rows: [[Any]] = []

            // Get column names
            let colCount = Int(result.columnCount)
            for i in 0..<colCount {
                columns.append(result.columnName(at: DBInt(i)) ?? "column_\(i)")
            }

            // Get rows
            let rowCount = Int(result.rowCount)
            for rowIdx in 0..<rowCount {
                var rowData: [Any] = []
                for colIdx in 0..<colCount {
                    let value = extractValue(from: result, row: DBInt(rowIdx), col: DBInt(colIdx))
                    rowData.append(value)
                }
                rows.append(rowData)
            }

            let executionTime = Date().timeIntervalSince(startTime)
            print("✓ [DuckDB] Query returned \(rows.count) rows")
            return QueryResult(columns: columns, rows: rows, executionTime: executionTime)

        } catch {
            throw DatabaseError.queryFailed(error.localizedDescription)
        }
    }

    private func extractValue(from result: ResultSet, row: DBInt, col: DBInt) -> Any {
        let column = result[col]

        let stringCol = column.cast(to: String.self)
        if let v = stringCol[row] { return v }

        let int64Col = column.cast(to: Int64.self)
        if let v = int64Col[row] { return v }

        let int32Col = column.cast(to: Int32.self)
        if let v = int32Col[row] { return v }

        let doubleCol = column.cast(to: Double.self)
        if let v = doubleCol[row] { return v }

        let boolCol = column.cast(to: Bool.self)
        if let v = boolCol[row] { return v }

        return NSNull()
    }
    
    func getSchema() async throws -> DatabaseSchema {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        var tables: [TableSchema] = []

        do {
            let tablesResult = try conn.query("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'main'
                ORDER BY table_name
            """)

            let tableNameCol = tablesResult[0].cast(to: String.self)

            let tableRowCount = Int(tablesResult.rowCount)
            for rowIdx in 0..<tableRowCount {
                guard let tableName = tableNameCol[DBInt(rowIdx)] else { continue }

                let columnsResult = try conn.query("""
                    SELECT column_name, data_type, is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'main' AND table_name = '\(tableName)'
                    ORDER BY ordinal_position
                """)

                var columns: [ColumnSchema] = []
                let colNameCol = columnsResult[0].cast(to: String.self)
                let dataTypeCol = columnsResult[1].cast(to: String.self)
                let nullableCol = columnsResult[2].cast(to: String.self)

                let colRowCount = Int(columnsResult.rowCount)
                for colIdx in 0..<colRowCount {
                    let colName = colNameCol[DBInt(colIdx)] ?? ""
                    let dataType = dataTypeCol[DBInt(colIdx)] ?? ""
                    let nullable = nullableCol[DBInt(colIdx)] == "YES"

                    columns.append(ColumnSchema(
                        name: colName,
                        type: dataType,
                        isNullable: nullable,
                        isPrimaryKey: false
                    ))
                }

                tables.append(TableSchema(name: tableName, columns: columns))
            }

            // Add attached data sources as virtual tables
            for source in attachedSources {
                if !tables.contains(where: { $0.name == source.alias }) {
                    let sourceColumns = try await getDataSourceColumns(source)
                    tables.append(TableSchema(name: source.alias, columns: sourceColumns))
                }
            }

        } catch {
            print("⚠️ [DuckDB] Schema error: \(error)")
        }

        return DatabaseSchema(tables: tables)
    }

    func testConnection() async throws -> Bool {
        guard let conn = connection else {
            return false
        }

        do {
            _ = try conn.query("SELECT 1")
            return true
        } catch {
            return false
        }
    }

    // MARK: - Data Source Management

    func attachParquet(path: String, alias: String) async throws {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        let sql = "CREATE OR REPLACE VIEW \"\(alias)\" AS SELECT * FROM read_parquet('\(path)')"
        try conn.execute(sql)

        let source = DuckDBDataSource(alias: alias, type: .parquet, path: path, isDirectory: false)
        attachedSources.append(source)
        print("✓ [DuckDB] Attached Parquet: \(path) as \(alias)")
    }

    func attachCSV(path: String, alias: String, hasHeader: Bool = true) async throws {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        let sql = "CREATE OR REPLACE VIEW \"\(alias)\" AS SELECT * FROM read_csv('\(path)', header=\(hasHeader))"
        try conn.execute(sql)

        let source = DuckDBDataSource(alias: alias, type: .csv, path: path, isDirectory: false,
                                       options: ["hasHeader": String(hasHeader)])
        attachedSources.append(source)
        print("✓ [DuckDB] Attached CSV: \(path) as \(alias)")
    }

    func attachJSON(path: String, alias: String) async throws {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        let sql = "CREATE OR REPLACE VIEW \"\(alias)\" AS SELECT * FROM read_json('\(path)')"
        try conn.execute(sql)

        let source = DuckDBDataSource(alias: alias, type: .json, path: path, isDirectory: false)
        attachedSources.append(source)
        print("✓ [DuckDB] Attached JSON: \(path) as \(alias)")
    }

    func attachParquetDirectory(path: String, alias: String) async throws {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        let pattern = path.hasSuffix("/") ? "\(path)*.parquet" : "\(path)/*.parquet"
        let sql = "CREATE OR REPLACE VIEW \"\(alias)\" AS SELECT * FROM read_parquet('\(pattern)')"
        try conn.execute(sql)

        let source = DuckDBDataSource(alias: alias, type: .parquet, path: path, isDirectory: true)
        attachedSources.append(source)
        print("✓ [DuckDB] Attached Parquet directory: \(path) as \(alias)")
    }

    func detachSource(alias: String) async throws {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        try conn.execute("DROP VIEW IF EXISTS \"\(alias)\"")
        attachedSources.removeAll { $0.alias == alias }
        print("✓ [DuckDB] Detached: \(alias)")
    }

    func listAttachedSources() -> [DuckDBDataSource] {
        return attachedSources
    }

    // MARK: - Private Methods

    private func attachDataSource(_ source: DuckDBDataSource) async throws {
        switch source.type {
        case .parquet:
            if source.isDirectory {
                try await attachParquetDirectory(path: source.path, alias: source.alias)
            } else {
                try await attachParquet(path: source.path, alias: source.alias)
            }
        case .csv:
            let hasHeader = source.options?["hasHeader"] != "false"
            try await attachCSV(path: source.path, alias: source.alias, hasHeader: hasHeader)
        case .json:
            try await attachJSON(path: source.path, alias: source.alias)
        case .excel:
            throw DatabaseError.unsupportedOperation("Excel files not yet supported")
        }
    }

    private func getDataSourceColumns(_ source: DuckDBDataSource) async throws -> [ColumnSchema] {
        guard let conn = connection else {
            throw DatabaseError.notConnected
        }

        let result = try conn.query("DESCRIBE \"\(source.alias)\"")
        var columns: [ColumnSchema] = []

        let nameCol = result[0].cast(to: String.self)
        let typeCol = result[1].cast(to: String.self)

        let rowCount = Int(result.rowCount)
        for rowIdx in 0..<rowCount {
            let name = nameCol[DBInt(rowIdx)] ?? ""
            let type = typeCol[DBInt(rowIdx)] ?? ""

            columns.append(ColumnSchema(
                name: name,
                type: type,
                isNullable: true,
                isPrimaryKey: false
            ))
        }

        return columns
    }
}

// MARK: - Data Source Model

struct DuckDBDataSource: Identifiable, Codable {
    let id: UUID
    let alias: String
    let type: DataSourceType
    let path: String
    let isDirectory: Bool
    var options: [String: String]?

    init(id: UUID = UUID(), alias: String, type: DataSourceType, path: String,
         isDirectory: Bool = false, options: [String: String]? = nil) {
        self.id = id
        self.alias = alias
        self.type = type
        self.path = path
        self.isDirectory = isDirectory
        self.options = options
    }
}

enum DataSourceType: String, Codable {
    case parquet
    case csv
    case json
    case excel

    var icon: String {
        switch self {
        case .parquet: return "📊"
        case .csv: return "📄"
        case .json: return "📋"
        case .excel: return "📗"
        }
    }

    var displayName: String {
        switch self {
        case .parquet: return "Parquet"
        case .csv: return "CSV"
        case .json: return "JSON"
        case .excel: return "Excel"
        }
    }
}

// MARK: - DuckDB Configuration

struct DuckDBConfig {
    let mode: DuckDBMode
    let path: String?
    let dataSources: [DuckDBDataSource]

    init(mode: DuckDBMode = .memory, path: String? = nil, dataSources: [DuckDBDataSource] = []) {
        self.mode = mode
        self.path = path
        self.dataSources = dataSources
    }

    var databaseConfig: DatabaseConfig {
        var options: [String: String] = ["mode": mode.rawValue]

        if !dataSources.isEmpty,
           let sourcesData = try? JSONEncoder().encode(dataSources),
           let sourcesJson = String(data: sourcesData, encoding: .utf8) {
            options["dataSources"] = sourcesJson
        }

        return DatabaseConfig(
            type: .duckdb,
            connectionString: path ?? ":memory:",
            options: options
        )
    }
}

enum DuckDBMode: String {
    case memory = "memory"
    case file = "file"
}


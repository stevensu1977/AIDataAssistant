import Foundation

/// Database configuration model
public struct DatabaseConfig: Codable {
    public let type: DatabaseType
    public let connectionString: String
    public let options: [String: String]?
    
    public init(type: DatabaseType, connectionString: String, options: [String: String]? = nil) {
        self.type = type
        self.connectionString = connectionString
        self.options = options
    }
}

/// Supported database types
public enum DatabaseType: String, Codable {
    case sqlite
    case mysql
    case postgresql
    case duckdb
    case elasticache
}

/// SQLite specific configuration
public struct SQLiteConfig {
    public let path: String
    public let readOnly: Bool
    public let createIfNotExists: Bool

    public init(path: String, readOnly: Bool = false, createIfNotExists: Bool = true) {
        self.path = path
        self.readOnly = readOnly
        self.createIfNotExists = createIfNotExists
    }

    public var databaseConfig: DatabaseConfig {
        DatabaseConfig(
            type: .sqlite,
            connectionString: path,
            options: [
                "readOnly": String(readOnly),
                "createIfNotExists": String(createIfNotExists)
            ]
        )
    }
}

/// MySQL specific configuration
public struct MySQLConfig: Codable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let ssl: Bool

    public init(
        host: String = "localhost",
        port: Int = 3306,
        username: String,
        password: String,
        database: String,
        ssl: Bool = false
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.ssl = ssl
    }

    public var databaseConfig: DatabaseConfig {
        DatabaseConfig(
            type: .mysql,
            connectionString: "\(host):\(port)/\(database)",
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


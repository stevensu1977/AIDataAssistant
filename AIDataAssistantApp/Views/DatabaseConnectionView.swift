import SwiftUI
import AIDataAssistantCore

struct DatabaseConnectionView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var databaseManager: DatabaseManager
    
    @State private var connectionName = ""
    @State private var selectedType: DatabaseType = .mysql
    
    // MySQL fields
    @State private var mysqlHost = "localhost"
    @State private var mysqlPort = "3306"
    @State private var mysqlUsername = ""
    @State private var mysqlPassword = ""
    @State private var mysqlDatabase = ""
    @State private var mysqlSSL = false
    
    // SQLite fields
    @State private var sqlitePath = ""
    
    // Test connection state
    @State private var isTestingConnection = false
    @State private var testResult: String?
    @State private var testError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Database Connection")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Connection Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("My Database", text: $connectionName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Database Type
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Database Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Type", selection: $selectedType) {
                            Text("MySQL").tag(DatabaseType.mysql)
                            Text("SQLite").tag(DatabaseType.sqlite)
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Divider()
                    
                    // Type-specific fields
                    if selectedType == .mysql {
                        mysqlFields
                    } else {
                        sqliteFields
                    }
                    
                    // Test connection result
                    if let result = testResult {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(result)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    if let error = testError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(isTestingConnection || !isFormValid)
                
                if isTestingConnection {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Connect") {
                    saveAndConnect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }
    
    var mysqlFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Host
            VStack(alignment: .leading, spacing: 4) {
                Text("Host")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("localhost", text: $mysqlHost)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Port
            VStack(alignment: .leading, spacing: 4) {
                Text("Port")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("3306", text: $mysqlPort)
                    .textFieldStyle(.roundedBorder)
            }

            // Username
            VStack(alignment: .leading, spacing: 4) {
                Text("Username")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("root", text: $mysqlUsername)
                    .textFieldStyle(.roundedBorder)
            }

            // Password
            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("Password", text: $mysqlPassword)
                    .textFieldStyle(.roundedBorder)
            }

            // Database
            VStack(alignment: .leading, spacing: 4) {
                Text("Database")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("mydb", text: $mysqlDatabase)
                    .textFieldStyle(.roundedBorder)
            }

            // SSL
            Toggle("Use SSL/TLS", isOn: $mysqlSSL)
                .font(.caption)
        }
    }

    var sqliteFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Database File Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("/path/to/database.db", text: $sqlitePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectSQLiteFile()
                    }
                }
            }
        }
    }

    var isFormValid: Bool {
        if connectionName.isEmpty {
            return false
        }

        switch selectedType {
        case .mysql:
            return !mysqlHost.isEmpty &&
                   !mysqlPort.isEmpty &&
                   !mysqlUsername.isEmpty &&
                   !mysqlDatabase.isEmpty
        case .sqlite:
            return !sqlitePath.isEmpty
        default:
            return false
        }
    }

    func testConnection() {
        isTestingConnection = true
        testResult = nil
        testError = nil

        Task {
            let connection = createConnection()
            let result = await databaseManager.testConnection(connection)

            await MainActor.run {
                isTestingConnection = false

                switch result {
                case .success(let message):
                    testResult = message
                    testError = nil
                case .failure(let error):
                    testError = error.localizedDescription
                    testResult = nil
                }
            }
        }
    }

    func saveAndConnect() {
        let connection = createConnection()
        databaseManager.addConnection(connection)

        Task {
            await databaseManager.connect(to: connection)
            await MainActor.run {
                dismiss()
            }
        }
    }

    func createConnection() -> DatabaseConnection {
        let config: DatabaseConfig

        switch selectedType {
        case .mysql:
            let mysqlConfig = MySQLConfig(
                host: mysqlHost,
                port: Int(mysqlPort) ?? 3306,
                username: mysqlUsername,
                password: mysqlPassword,
                database: mysqlDatabase,
                ssl: mysqlSSL
            )
            config = mysqlConfig.databaseConfig

        case .sqlite:
            let sqliteConfig = SQLiteConfig(path: sqlitePath)
            config = sqliteConfig.databaseConfig

        default:
            fatalError("Unsupported database type")
        }

        return DatabaseConnection(
            name: connectionName,
            type: selectedType,
            config: config
        )
    }

    func selectSQLiteFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.database, .data]

        if panel.runModal() == .OK {
            if let url = panel.url {
                sqlitePath = url.path
            }
        }
    }
}

#Preview {
    DatabaseConnectionView(databaseManager: DatabaseManager())
}



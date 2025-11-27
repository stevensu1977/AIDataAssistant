import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTable: String?
    @State private var showConnectionSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            // Current Connection Header
            if let connection = appState.databaseManager.currentConnection {
                // Connected state - show connection info with tables
                VStack(spacing: 0) {
                    // Connection header
                    HStack {
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 8, height: 8)

                        Image(systemName: "cylinder.split.1x2.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.name)
                                .font(.headline)
                            Text(connection.type.rawValue.uppercased())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Disconnect button
                        Button(action: {
                            Task {
                                await appState.databaseManager.disconnect()
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Disconnect")

                        // Switch connection button
                        Button(action: {
                            showConnectionSwitcher.toggle()
                        }) {
                            Image(systemName: showConnectionSwitcher ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Switch Connection")
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                }

                Divider()

                // Tables list for current connection - DIRECTLY UNDER CONNECTION HEADER
                if let schema = appState.schema {
                    List(schema.tables, id: \.name, selection: $selectedTable) { table in
                        TableRowView(table: table)
                    }
                    .listStyle(.sidebar)
                } else {
                    VStack {
                        Spacer()
                        ProgressView("Loading schema...")
                        Spacer()
                    }
                }

                // Connection switcher at the BOTTOM (overlay style)
                if showConnectionSwitcher {
                    Divider()
                    ConnectionSwitcherView(databaseManager: appState.databaseManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            } else {
                // Not connected - show connection selector
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "cylinder.split.1x2.fill")
                            .foregroundStyle(.gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Database")
                                .font(.headline)
                            Text("Not connected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Show available connections
                    ConnectionListView(databaseManager: appState.databaseManager)
                }
            }
        }
        .frame(minWidth: 250)
        .animation(.easeInOut(duration: 0.2), value: showConnectionSwitcher)
    }

    private var connectionStatusColor: Color {
        switch appState.databaseManager.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

struct TableRowView: View {
    let table: TableSchema
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(table.columns, id: \.name) { column in
                HStack {
                    Image(systemName: column.isPrimaryKey ? "key.fill" : "text.alignleft")
                        .font(.caption)
                        .foregroundColor(column.isPrimaryKey ? .yellow : .secondary)
                        .frame(width: 16)
                    
                    Text(column.name)
                        .font(.caption)
                    
                    Spacer()
                    
                    Text(column.type)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                .padding(.leading, 8)
            }
        } label: {
            HStack {
                Image(systemName: "tablecells.fill")
                    .foregroundStyle(.blue)
                Text(table.name)
                    .font(.body)
                Spacer()
                Text("\(table.columns.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState())
}

// MARK: - Connection Switcher View (for switching when connected)

struct ConnectionSwitcherView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showingAddConnection = false

    private var otherConnections: [DatabaseConnection] {
        databaseManager.availableConnections.filter {
            $0.id != databaseManager.currentConnection?.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Switch Connection")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingAddConnection = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add Connection")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Other connections list
            if otherConnections.isEmpty {
                Text("No other connections")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(otherConnections) { connection in
                        ConnectionRowView(connection: connection, databaseManager: databaseManager)
                    }
                }
                .padding(8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .sheet(isPresented: $showingAddConnection) {
            DatabaseConnectionView(databaseManager: databaseManager)
        }
    }
}

// MARK: - Connection List View (for when not connected)

struct ConnectionListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showingAddConnection = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Available Connections")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingAddConnection = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Add Connection")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Connections list
            if databaseManager.availableConnections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No connections configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Add Connection") {
                        showingAddConnection = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(databaseManager.availableConnections) { connection in
                            ConnectionRowView(connection: connection, databaseManager: databaseManager)
                        }
                    }
                    .padding(8)
                }
            }

            Spacer()
        }
        .sheet(isPresented: $showingAddConnection) {
            DatabaseConnectionView(databaseManager: databaseManager)
        }
    }
}

// MARK: - Connection Row View

struct ConnectionRowView: View {
    let connection: DatabaseConnection
    @ObservedObject var databaseManager: DatabaseManager
    @State private var isHovering = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack {
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.subheadline)
                Text(connection.type.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Action buttons - show on hover
            if isHovering {
                HStack(spacing: 8) {
                    // Edit button
                    Button(action: {
                        showingEditSheet = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Connection")

                    // Delete button
                    Button(action: {
                        showingDeleteConfirm = true
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete Connection")
                }
            }

            // Connect button
            Button(action: {
                Task {
                    await databaseManager.connect(to: connection)
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("Connect")
                }
                .font(.caption)
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditConnectionView(connection: connection, databaseManager: databaseManager)
        }
        .alert("Delete Connection", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                databaseManager.removeConnection(connection)
            }
        } message: {
            Text("Are you sure you want to delete '\(connection.name)'? This action cannot be undone.")
        }
    }
}

// MARK: - Edit Connection View

struct EditConnectionView: View {
    let connection: DatabaseConnection
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var connectionName: String = ""

    // MySQL fields
    @State private var mysqlHost = "localhost"
    @State private var mysqlPort = "3306"
    @State private var mysqlUsername = ""
    @State private var mysqlPassword = ""
    @State private var mysqlDatabase = ""
    @State private var mysqlSSL = false

    // PostgreSQL fields
    @State private var pgHost = "localhost"
    @State private var pgPort = "5432"
    @State private var pgUsername = ""
    @State private var pgPassword = ""
    @State private var pgDatabase = ""
    @State private var pgSSL = false

    // SQLite fields
    @State private var sqlitePath = ""

    // DuckDB fields
    @State private var duckdbMode: DuckDBMode = .memory
    @State private var duckdbPath = ""
    @State private var duckdbDataSources: [DuckDBDataSource] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Connection")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

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

                    Divider()

                    // Type-specific fields (read-only type display)
                    HStack {
                        Text("Type:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(connection.type.rawValue.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    // Type-specific fields
                    switch connection.type {
                    case .mysql:
                        mysqlFieldsEdit
                    case .postgresql:
                        postgresqlFieldsEdit
                    case .sqlite:
                        sqliteFieldsEdit
                    case .duckdb:
                        duckdbFieldsEdit
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    saveConnection()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 400, height: 450)
        .onAppear {
            loadConnectionData()
        }
    }

    private var mysqlFieldsEdit: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host").font(.caption).foregroundColor(.secondary)
                    TextField("localhost", text: $mysqlHost).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port").font(.caption).foregroundColor(.secondary)
                    TextField("3306", text: $mysqlPort).textFieldStyle(.roundedBorder).frame(width: 80)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Username").font(.caption).foregroundColor(.secondary)
                TextField("root", text: $mysqlUsername).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Password").font(.caption).foregroundColor(.secondary)
                SecureField("password", text: $mysqlPassword).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Database").font(.caption).foregroundColor(.secondary)
                TextField("database_name", text: $mysqlDatabase).textFieldStyle(.roundedBorder)
            }
            Toggle("Use SSL/TLS", isOn: $mysqlSSL).font(.caption)
        }
    }

    private var postgresqlFieldsEdit: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host").font(.caption).foregroundColor(.secondary)
                    TextField("localhost", text: $pgHost).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port").font(.caption).foregroundColor(.secondary)
                    TextField("5432", text: $pgPort).textFieldStyle(.roundedBorder).frame(width: 80)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Username").font(.caption).foregroundColor(.secondary)
                TextField("postgres", text: $pgUsername).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Password").font(.caption).foregroundColor(.secondary)
                SecureField("password", text: $pgPassword).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Database").font(.caption).foregroundColor(.secondary)
                TextField("database_name", text: $pgDatabase).textFieldStyle(.roundedBorder)
            }
            Toggle("Use SSL/TLS", isOn: $pgSSL).font(.caption)
        }
    }

    private var sqliteFieldsEdit: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Database Path").font(.caption).foregroundColor(.secondary)
                HStack {
                    TextField("/path/to/database.db", text: $sqlitePath).textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseSQLiteFile()
                    }
                }
            }
        }
    }

    private var duckdbFieldsEdit: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Database mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Database Mode").font(.caption).foregroundColor(.secondary)
                Picker("Mode", selection: $duckdbMode) {
                    Text("In-Memory").tag(DuckDBMode.memory)
                    Text("File Database").tag(DuckDBMode.file)
                }
                .pickerStyle(.radioGroup)
            }

            if duckdbMode == .file {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database Path").font(.caption).foregroundColor(.secondary)
                    HStack {
                        TextField("/path/to/database.duckdb", text: $duckdbPath).textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseDuckDBFileEdit()
                        }
                    }
                }
            }

            Divider()

            // Data Sources
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Data Sources")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Optional - attach files to query")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // List of data sources
                if !duckdbDataSources.isEmpty {
                    ForEach(duckdbDataSources) { source in
                        HStack {
                            Text(source.type.icon)
                            VStack(alignment: .leading) {
                                Text(source.alias)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(source.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(action: {
                                duckdbDataSources.removeAll { $0.id == source.id }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }

                // Add buttons
                HStack(spacing: 8) {
                    Button("+ Parquet") {
                        addDataSourceEdit(type: .parquet)
                    }
                    .font(.caption)

                    Button("+ CSV") {
                        addDataSourceEdit(type: .csv)
                    }
                    .font(.caption)

                    Button("+ JSON") {
                        addDataSourceEdit(type: .json)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func addDataSourceEdit(type: DataSourceType) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = (type == .parquet)
        panel.allowsMultipleSelection = false
        panel.message = "Select \(type.rawValue.uppercased()) file to attach"

        switch type {
        case .parquet:
            panel.allowedContentTypes = [.init(filenameExtension: "parquet")!]
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
        case .json:
            panel.allowedContentTypes = [.json]
        case .excel:
            panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        }

        if panel.runModal() == .OK, let url = panel.url {
            let alias = url.deletingPathExtension().lastPathComponent
            let source = DuckDBDataSource(
                id: UUID(),
                alias: alias,
                type: type,
                path: url.path
            )
            duckdbDataSources.append(source)
        }
    }

    private func browseDuckDBFileEdit() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "duckdb")!, .init(filenameExtension: "db")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            duckdbPath = url.path
        }
    }

    private var isFormValid: Bool {
        guard !connectionName.isEmpty else { return false }
        switch connection.type {
        case .mysql:
            return !mysqlHost.isEmpty && !mysqlPort.isEmpty && !mysqlUsername.isEmpty && !mysqlDatabase.isEmpty
        case .postgresql:
            return !pgHost.isEmpty && !pgPort.isEmpty && !pgUsername.isEmpty && !pgDatabase.isEmpty
        case .sqlite:
            return !sqlitePath.isEmpty
        case .duckdb:
            return duckdbMode == .memory || !duckdbPath.isEmpty
        default:
            return false
        }
    }

    private func loadConnectionData() {
        connectionName = connection.name
        let options = connection.config.options ?? [:]

        switch connection.type {
        case .mysql:
            mysqlHost = options["host"] ?? "localhost"
            mysqlPort = options["port"] ?? "3306"
            mysqlUsername = options["username"] ?? ""
            mysqlPassword = options["password"] ?? ""
            mysqlDatabase = options["database"] ?? ""
            mysqlSSL = options["ssl"] == "true"
        case .postgresql:
            pgHost = options["host"] ?? "localhost"
            pgPort = options["port"] ?? "5432"
            pgUsername = options["username"] ?? ""
            pgPassword = options["password"] ?? ""
            pgDatabase = options["database"] ?? ""
            pgSSL = options["ssl"] == "true"
        case .sqlite:
            sqlitePath = options["path"] ?? connection.config.connectionString
        case .duckdb:
            duckdbMode = options["mode"] == "file" ? .file : .memory
            duckdbPath = connection.config.connectionString
            if let sourcesJson = options["dataSources"],
               let sourcesData = sourcesJson.data(using: .utf8),
               let sources = try? JSONDecoder().decode([DuckDBDataSource].self, from: sourcesData) {
                duckdbDataSources = sources
            }
        default:
            break
        }
    }

    private func saveConnection() {
        let config: DatabaseConfig

        switch connection.type {
        case .mysql:
            config = DatabaseConfig(
                type: .mysql,
                connectionString: "mysql://\(mysqlUsername):\(mysqlPassword)@\(mysqlHost):\(mysqlPort)/\(mysqlDatabase)",
                options: [
                    "host": mysqlHost,
                    "port": mysqlPort,
                    "username": mysqlUsername,
                    "password": mysqlPassword,
                    "database": mysqlDatabase,
                    "ssl": String(mysqlSSL)
                ]
            )
        case .postgresql:
            config = DatabaseConfig(
                type: .postgresql,
                connectionString: "postgresql://\(pgUsername):\(pgPassword)@\(pgHost):\(pgPort)/\(pgDatabase)",
                options: [
                    "host": pgHost,
                    "port": pgPort,
                    "username": pgUsername,
                    "password": pgPassword,
                    "database": pgDatabase,
                    "ssl": String(pgSSL)
                ]
            )
        case .sqlite:
            config = DatabaseConfig(
                type: .sqlite,
                connectionString: sqlitePath,
                options: ["path": sqlitePath]
            )
        case .duckdb:
            let duckConfig = DuckDBConfig(
                mode: duckdbMode,
                path: duckdbMode == .file ? duckdbPath : nil,
                dataSources: duckdbDataSources
            )
            config = duckConfig.databaseConfig
        default:
            return
        }

        let updatedConnection = DatabaseConnection(
            id: connection.id,
            name: connectionName,
            type: connection.type,
            config: config
        )

        databaseManager.updateConnection(updatedConnection)
    }

    private func browseSQLiteFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.database, .data]
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            if let url = panel.url {
                sqlitePath = url.path
            }
        }
    }
}



// MARK: - Database Connection View

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

    // PostgreSQL fields
    @State private var pgHost = "localhost"
    @State private var pgPort = "5432"
    @State private var pgUsername = ""
    @State private var pgPassword = ""
    @State private var pgDatabase = ""
    @State private var pgSSL = false

    // SQLite fields
    @State private var sqlitePath = ""

    // DuckDB fields
    @State private var duckdbMode: DuckDBMode = .memory
    @State private var duckdbPath = ""
    @State private var duckdbDataSources: [DuckDBDataSource] = []

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
                            Text("PostgreSQL").tag(DatabaseType.postgresql)
                            Text("SQLite").tag(DatabaseType.sqlite)
                            Text("DuckDB").tag(DatabaseType.duckdb)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Type-specific fields
                    switch selectedType {
                    case .mysql:
                        mysqlFields
                    case .postgresql:
                        postgresqlFields
                    case .sqlite:
                        sqliteFields
                    case .duckdb:
                        duckdbFields
                    default:
                        EmptyView()
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
                            Image(systemName: "xmark.circle.fill")
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
        .frame(width: 500, height: 600)
    }

    // MySQL fields
    private var mysqlFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MySQL Configuration")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("localhost", text: $mysqlHost)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("3306", text: $mysqlPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Username")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("root", text: $mysqlUsername)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("password", text: $mysqlPassword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Database")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("database_name", text: $mysqlDatabase)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Use SSL/TLS", isOn: $mysqlSSL)
                .font(.caption)
        }
    }

    // PostgreSQL fields
    private var postgresqlFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PostgreSQL Configuration")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("localhost", text: $pgHost)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("5432", text: $pgPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Username")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("postgres", text: $pgUsername)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("password", text: $pgPassword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Database")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("database_name", text: $pgDatabase)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Use SSL/TLS", isOn: $pgSSL)
                .font(.caption)
        }
    }

    // SQLite fields
    private var sqliteFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SQLite Configuration")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Database Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("/path/to/database.db", text: $sqlitePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseSQLiteFile()
                    }
                }
            }
        }
    }

    // DuckDB fields
    private var duckdbFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DuckDB Configuration")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Database mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Database Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Mode", selection: $duckdbMode) {
                    Text("In-Memory (Temporary)").tag(DuckDBMode.memory)
                    Text("File Database").tag(DuckDBMode.file)
                }
                .pickerStyle(.radioGroup)
            }

            // File path (only for file mode)
            if duckdbMode == .file {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("/path/to/database.duckdb", text: $duckdbPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            browseDuckDBFile()
                        }
                    }
                }
            }

            Divider()

            // Data Sources
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Data Sources")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Optional - attach files to query")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // List of data sources
                if !duckdbDataSources.isEmpty {
                    ForEach(duckdbDataSources) { source in
                        HStack {
                            Text(source.type.icon)
                            VStack(alignment: .leading) {
                                Text(source.alias)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(source.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(action: {
                                duckdbDataSources.removeAll { $0.id == source.id }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }

                // Add buttons
                HStack(spacing: 8) {
                    Button("+ Parquet") {
                        addDataSource(type: .parquet)
                    }
                    .font(.caption)

                    Button("+ CSV") {
                        addDataSource(type: .csv)
                    }
                    .font(.caption)

                    Button("+ JSON") {
                        addDataSource(type: .json)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func browseDuckDBFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "duckdb")!, .init(filenameExtension: "db")!]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a DuckDB database file (or create a new one)"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            duckdbPath = url.path
        }
    }

    private func addDataSource(type: DataSourceType) {
        let panel = NSOpenPanel()

        switch type {
        case .parquet:
            panel.allowedContentTypes = [.init(filenameExtension: "parquet")!]
            panel.message = "Select a Parquet file or directory"
            panel.canChooseDirectories = true
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.message = "Select a CSV file"
            panel.canChooseDirectories = false
        case .json:
            panel.allowedContentTypes = [.json]
            panel.message = "Select a JSON file"
            panel.canChooseDirectories = false
        case .excel:
            return // Not supported yet
        }

        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

            let alias = url.deletingPathExtension().lastPathComponent
            let source = DuckDBDataSource(
                alias: alias,
                type: type,
                path: url.path,
                isDirectory: isDirectory.boolValue
            )
            duckdbDataSources.append(source)
        }
    }

    // Form validation
    private var isFormValid: Bool {
        guard !connectionName.isEmpty else { return false }

        switch selectedType {
        case .mysql:
            return !mysqlHost.isEmpty && !mysqlPort.isEmpty &&
                   !mysqlUsername.isEmpty && !mysqlDatabase.isEmpty
        case .postgresql:
            return !pgHost.isEmpty && !pgPort.isEmpty &&
                   !pgUsername.isEmpty && !pgDatabase.isEmpty
        case .sqlite:
            return !sqlitePath.isEmpty
        case .duckdb:
            return duckdbMode == .memory || !duckdbPath.isEmpty
        default:
            return false
        }
    }

    // Test connection
    private func testConnection() {
        testResult = nil
        testError = nil
        isTestingConnection = true

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
                    testResult = nil
                    testError = error.localizedDescription
                }
            }
        }
    }

    // Save and connect
    private func saveAndConnect() {
        let connection = createConnection()
        databaseManager.addConnection(connection)

        Task {
            await databaseManager.connect(to: connection)
            await MainActor.run {
                dismiss()
            }
        }
    }

    // Browse SQLite file
    private func browseSQLiteFile() {
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

    // Create connection from form
    private func createConnection() -> DatabaseConnection {
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
        case .postgresql:
            let pgConfig = PostgreSQLConfig(
                host: pgHost,
                port: Int(pgPort) ?? 5432,
                username: pgUsername,
                password: pgPassword,
                database: pgDatabase,
                ssl: pgSSL
            )
            config = pgConfig.databaseConfig
        case .sqlite:
            config = DatabaseConfig(
                type: .sqlite,
                connectionString: sqlitePath,
                options: ["path": sqlitePath]
            )
        case .duckdb:
            let duckConfig = DuckDBConfig(
                mode: duckdbMode,
                path: duckdbMode == .file ? duckdbPath : nil,
                dataSources: duckdbDataSources
            )
            config = duckConfig.databaseConfig
        default:
            fatalError("Unsupported database type")
        }

        return DatabaseConnection(
            name: connectionName,
            type: selectedType,
            config: config
        )
    }
}


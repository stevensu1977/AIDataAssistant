import SwiftUI

struct QueryView: View {
    @EnvironmentObject var appState: AppState
    @State private var queryText = ""
    @State private var queryHistory: [QueryHistoryItem] = []
    @State private var isProcessing = false
    @State private var selectedHistoryItem: UUID?
    @State private var queryMode: QueryMode = .naturalLanguage

    enum QueryMode {
        case naturalLanguage
        case directSQL
    }

    var body: some View {
        VStack(spacing: 0) {
            // Query input area
            VStack(spacing: 12) {
                HStack {
                    // Mode selector
                    Picker("Query Mode", selection: $queryMode) {
                        Label("AI Query", systemImage: "brain.head.profile")
                            .tag(QueryMode.naturalLanguage)
                        Label("SQL Query", systemImage: "terminal")
                            .tag(QueryMode.directSQL)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)

                    Spacer()

                    Button(action: clearHistory) {
                        Label("Clear History", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(queryHistory.isEmpty)
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: queryMode == .naturalLanguage ? "bubble.left.fill" : "terminal.fill")
                        .font(.title2)
                        .foregroundStyle(queryMode == .naturalLanguage ? Color.blue.gradient : Color.green.gradient)
                        .padding(.top, 8)

                    TextField(
                        queryMode == .naturalLanguage ? "What would you like to know?" : "Enter SQL query...",
                        text: $queryText,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(queryMode == .directSQL ? .system(.body, design: .monospaced) : .body)
                    .lineLimit(3...10)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .onSubmit {
                        executeQuery()
                    }

                    Button(action: executeQuery) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                    .padding(.top, 8)
                }

                // Hint text
                if queryMode == .directSQL {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Direct SQL mode: Query will be executed without AI processing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Results area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if queryHistory.isEmpty {
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 60))
                                    .foregroundStyle(.secondary.opacity(0.5))
                                Text("Ask a question to get started")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                if queryMode == .naturalLanguage {
                                    Text("Try: \"Show me all users\" or \"What are the top 10 products?\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Try: \"SELECT * FROM Album LIMIT 10\"")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            ForEach(queryHistory) { item in
                                QueryHistoryItemView(item: item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: queryHistory.count) { _, _ in
                    if let lastItem = queryHistory.last {
                        withAnimation {
                            proxy.scrollTo(lastItem.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    private func executeQuery() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        queryText = ""
        isProcessing = true

        let historyItem = QueryHistoryItem(query: query, mode: queryMode)
        queryHistory.append(historyItem)

        // Capture values before entering Task to avoid @EnvironmentObject issues
        let currentMode = queryMode
        let engine = appState.queryEngine

        Task {
            do {
                guard let engine = engine else {
                    throw NSError(domain: "QueryView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Query engine not initialized"])
                }

                if currentMode == .naturalLanguage {
                    // AI-powered query
                    let request = QueryRequest(naturalLanguage: query)
                    let response = try await engine.processQuery(request)

                    await MainActor.run {
                        if let index = queryHistory.firstIndex(where: { $0.id == historyItem.id }) {
                            queryHistory[index].response = response
                            queryHistory[index].status = .success
                        }
                        isProcessing = false
                    }
                } else {
                    // Direct SQL query
                    let result = try await engine.executeSQL(query)

                    // Create a response without AI explanation
                    let response = QueryResponse(
                        generatedSQL: query,
                        result: result,
                        explanation: nil
                    )

                    await MainActor.run {
                        if let index = queryHistory.firstIndex(where: { $0.id == historyItem.id }) {
                            queryHistory[index].response = response
                            queryHistory[index].status = .success
                        }
                        isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    if let index = queryHistory.firstIndex(where: { $0.id == historyItem.id }) {
                        queryHistory[index].error = error.localizedDescription
                        queryHistory[index].status = .error
                    }
                    isProcessing = false
                }
            }
        }
    }
    
    private func clearHistory() {
        queryHistory.removeAll()
        if let engine = appState.queryEngine {
            engine.clearHistory()
        }
    }
}

struct QueryHistoryItem: Identifiable {
    let id = UUID()
    let query: String
    let timestamp = Date()
    let mode: QueryView.QueryMode
    var response: QueryResponse?
    var error: String?
    var status: Status = .processing

    enum Status {
        case processing
        case success
        case error
    }
}

#Preview {
    QueryView()
        .environmentObject(AppState())
}


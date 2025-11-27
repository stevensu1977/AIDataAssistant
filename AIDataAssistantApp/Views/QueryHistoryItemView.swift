import SwiftUI

struct QueryHistoryItemView: View {
    let item: QueryHistoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User query
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("You")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Mode badge
                        if item.mode == .directSQL {
                            HStack(spacing: 3) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 8))
                                Text("SQL")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 8))
                                Text("AI")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple)
                            .cornerRadius(4)
                        }
                    }

                    Text(item.query)
                        .font(item.mode == .directSQL ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                }

                Spacer()

                Text(item.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // AI response
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.mode == .directSQL ? "cylinder.fill" : "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(item.mode == .directSQL ? Color.green.gradient : Color.purple.gradient)

                VStack(alignment: .leading, spacing: 12) {
                    Text(item.mode == .directSQL ? "Database" : "AI Assistant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    switch item.status {
                    case .processing:
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Processing...")
                                .foregroundColor(.secondary)
                        }
                        
                    case .error:
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(item.error ?? "Unknown error")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        
                    case .success:
                        if let response = item.response {
                            VStack(alignment: .leading, spacing: 12) {
                                // Generated SQL (only show for AI mode)
                                if item.mode == .naturalLanguage {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Generated SQL:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        HStack {
                                            Text(response.generatedSQL)
                                                .font(.system(.body, design: .monospaced))
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(NSColor.controlBackgroundColor))
                                                .cornerRadius(6)
                                                .textSelection(.enabled)

                                            Button(action: {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(response.generatedSQL, forType: .string)
                                            }) {
                                                Image(systemName: "doc.on.doc")
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy SQL")
                                        }
                                    }
                                }

                                // Results table
                                ResultsTableView(result: response.result)

                                // Explanation (only for AI mode)
                                if item.mode == .naturalLanguage, let explanation = response.explanation {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Explanation:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(explanation)
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                            .padding(8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.blue.opacity(0.05))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
    }
}

struct ResultsTableView: View {
    let result: QueryResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Results:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(result.rowCount) rows in \(String(format: "%.3f", result.executionTime))s")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if result.rows.isEmpty {
                Text("No results")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        // Header row with grid borders
                        HStack(spacing: 0) {
                            ForEach(result.columns.indices, id: \.self) { index in
                                Text(result.columns[index])
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: 120, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                    )
                            }
                        }

                        // Data rows with grid borders
                        ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { colIndex, value in
                                    Text("\(value)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 120, alignment: .leading)
                                        .background(rowIndex % 2 == 0 ? Color(NSColor.controlBackgroundColor).opacity(0.3) : Color.clear)
                                        .overlay(
                                            Rectangle()
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                                        )
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 500)
                .background(Color.white.opacity(0.01))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
    }
}

#Preview {
    QueryHistoryItemView(item: QueryHistoryItem(query: "Show me all users", mode: .naturalLanguage))
        .padding()
}


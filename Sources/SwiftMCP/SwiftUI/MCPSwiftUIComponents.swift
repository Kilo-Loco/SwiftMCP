//
//  MCPSwiftUIComponents.swift
//  SwiftMCP
//
//  Ready-to-use SwiftUI components for MCP
//

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Server Status View

/// Displays the current server status
public struct MCPServerStatusView: View {
    @ObservedObject var viewModel: MCPServerViewModel
    
    public init(viewModel: MCPServerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            Text(viewModel.statusMessage)
                .font(.system(.body, design: .monospaced))
            
            Spacer()
            
            if viewModel.isRunning {
                Text("Uptime: \(formattedUptime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch viewModel.state {
        case .uninitialized, .terminated:
            return .gray
        case .initializing, .shuttingDown:
            return .orange
        case .ready:
            return .green
        }
    }
    
    private var formattedUptime: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: viewModel.uptime) ?? "0s"
    }
}

// MARK: - Tool List View

/// Displays a list of registered tools
public struct MCPToolListView: View {
    @ObservedObject var viewModel: MCPServerViewModel
    @State private var selectedTool: MCPTool?
    
    public init(viewModel: MCPServerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        List(viewModel.tools, id: \.name) { tool in
            ToolRowView(tool: tool) {
                selectedTool = tool
            }
        }
        .listStyle(PlainListStyle())
        .sheet(isPresented: .constant(selectedTool != nil)) {
            if let tool = selectedTool {
                ToolDetailView(tool: tool, serverViewModel: viewModel)
            }
        }
    }
}

struct ToolRowView: View {
    let tool: MCPTool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(tool.title ?? tool.name)
                        .font(.headline)
                    
                    if let description = tool.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ToolDetailView: View {
    let tool: MCPTool
    @ObservedObject var serverViewModel: MCPServerViewModel
    @StateObject private var executionViewModel: MCPToolExecutionViewModel
    @Environment(\.dismiss) var dismiss
    
    init(tool: MCPTool, serverViewModel: MCPServerViewModel) {
        self.tool = tool
        self.serverViewModel = serverViewModel
        self._executionViewModel = StateObject(wrappedValue: MCPToolExecutionViewModel(tool: tool, serverViewModel: serverViewModel))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Tool Information") {
                    LabeledContent("Name", value: tool.name)
                    if let title = tool.title {
                        LabeledContent("Title", value: title)
                    }
                    if let description = tool.description {
                        LabeledContent("Description", value: description)
                    }
                }
                
                if !executionViewModel.arguments.isEmpty {
                    Section("Arguments") {
                        ForEach(Array(executionViewModel.arguments.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                TextField("Value", text: binding(for: key))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await executionViewModel.execute()
                        }
                    }) {
                        if executionViewModel.isExecuting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Execute")
                        }
                    }
                    .disabled(executionViewModel.isExecuting)
                }
                
                if let result = executionViewModel.result {
                    Section("Result") {
                        if let content = result.content?.first,
                           case .text(let textContent) = content {
                            Text(textContent.text)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                
                if let error = executionViewModel.error {
                    Section("Error") {
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(tool.title ?? tool.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { executionViewModel.arguments[key] ?? "" },
            set: { executionViewModel.arguments[key] = $0 }
        )
    }
}

// MARK: - Resource List View

/// Displays a list of registered resources
public struct MCPResourceListView: View {
    @ObservedObject var viewModel: MCPServerViewModel
    
    public init(viewModel: MCPServerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        List(viewModel.resources, id: \.uri) { resource in
            ResourceRowView(resource: resource)
        }
        .listStyle(PlainListStyle())
    }
}

struct ResourceRowView: View {
    let resource: MCPResource
    
    var body: some View {
        HStack {
            Image(systemName: iconName(for: resource.mimeType))
                .foregroundColor(.green)
            
            VStack(alignment: .leading) {
                Text(resource.title ?? resource.uri)
                    .font(.headline)
                
                Text(resource.uri)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let description = resource.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if let mimeType = resource.mimeType {
                Text(mimeType.components(separatedBy: "/").last ?? mimeType)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconName(for mimeType: String?) -> String {
        guard let mimeType = mimeType else { return "doc" }
        
        if mimeType.contains("json") {
            return "curlybraces"
        } else if mimeType.contains("text") {
            return "doc.text"
        } else if mimeType.contains("image") {
            return "photo"
        } else {
            return "doc"
        }
    }
}

// MARK: - Connection Status View

/// Displays connection status
public struct MCPConnectionStatusView: View {
    @ObservedObject var status: MCPConnectionStatus
    
    public init(status: MCPConnectionStatus) {
        self.status = status
    }
    
    public var body: some View {
        HStack {
            Image(systemName: status.status.symbol)
                .foregroundColor(status.status.color)
            
            Text(statusText)
                .font(.caption)
            
            if case .connected = status.status {
                Divider()
                    .frame(height: 12)
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                    Text(formatBytes(status.bytesSent))
                        .font(.caption2)
                    
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                    Text(formatBytes(status.bytesReceived))
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
    }
    
    private var statusText: String {
        switch status.status {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Log View

/// Displays debug logs
public struct MCPLogView: View {
    @State private var logs: [LogEntry] = []
    @State private var filter: MCPDebugger.Level = .info
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: MCPDebugger.Level
        let message: String
    }
    
    public init() {}
    
    public var body: some View {
        VStack {
            // Filter toolbar
            Picker("Log Level", selection: $filter) {
                Text("Error").tag(MCPDebugger.Level.error)
                Text("Warning").tag(MCPDebugger.Level.warning)
                Text("Info").tag(MCPDebugger.Level.info)
                Text("Verbose").tag(MCPDebugger.Level.verbose)
                Text("Trace").tag(MCPDebugger.Level.trace)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Log list
            List(filteredLogs) { entry in
                HStack {
                    Text(entry.level.symbol)
                    
                    VStack(alignment: .leading) {
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                        
                        Text(formatTime(entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .listStyle(PlainListStyle())
            
            // Controls
            HStack {
                Button("Clear") {
                    logs.removeAll()
                }
                
                Spacer()
                
                Text("\(logs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .onAppear {
            setupLogCapture()
        }
    }
    
    private var filteredLogs: [LogEntry] {
        logs.filter { $0.level.rawValue <= filter.rawValue }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func setupLogCapture() {
        Task {
            await MCPDebugger.setLogHandler { message, level, _, _, _ in
                let entry = LogEntry(
                    timestamp: Date(),
                    level: level,
                    message: message
                )
                
                DispatchQueue.main.async {
                    self.logs.append(entry)
                    
                    // Keep only last 500 logs
                    if self.logs.count > 500 {
                        self.logs.removeFirst()
                    }
                }
            }
        }
    }
}
#endif
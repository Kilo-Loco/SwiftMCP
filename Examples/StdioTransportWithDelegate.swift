//
//  StdioTransportWithDelegate.swift
//  SwiftMCP Examples
//
//  Demonstrates using StdioTransport with the new delegate pattern and AsyncStream
//  Shows both delegate callbacks and async stream consumption patterns
//

import Foundation
import SwiftMCP
import SwiftMCPTransports

// MARK: - Transport Delegate Implementation

/// StdioTransportHandler demonstrates handling transport events via delegate
class StdioTransportHandler: StdioTransportDelegate {
    private weak var server: MCPServer?
    private var messageCount = 0
    private var startTime: Date?
    
    func setServer(_ server: MCPServer) {
        self.server = server
    }
    
    func transport(_ transport: StdioTransport, didReceive data: Data) async {
        messageCount += 1
        
        // Log received message
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 [\(messageCount)] Received: \(jsonString.prefix(100))...")
        }
        
        // Process through server
        if let server = server {
            if let response = await server.handleMessage(data) {
                // Send response back through transport
                try? await transport.send(response)
                
                if let responseString = String(data: response, encoding: .utf8) {
                    print("📤 [\(messageCount)] Sent: \(responseString.prefix(100))...")
                }
            }
        }
    }
    
    func transportDidConnect(_ transport: StdioTransport) async {
        startTime = Date()
        print("🔌 StdioTransport connected at \(startTime!.ISO8601Format())")
        print("📝 Ready to receive JSON-RPC messages via stdin")
        print("   Type messages and press Enter to send")
        print("   Use Ctrl+D to disconnect\n")
    }
    
    func transportDidDisconnect(_ transport: StdioTransport) async {
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        print("\n🔌 StdioTransport disconnected")
        print("📊 Statistics:")
        print("   - Messages processed: \(messageCount)")
        print("   - Duration: \(String(format: "%.2f", duration)) seconds")
        print("   - Average: \(String(format: "%.2f", Double(messageCount) / max(duration, 1))) msg/sec")
    }
    
    func transport(_ transport: StdioTransport, didEncounterError error: Error) async {
        print("❌ Transport error: \(error.localizedDescription)")
        
        // Attempt recovery based on error type
        if error is MCPTransportError {
            print("🔄 Attempting to reconnect...")
            // In production, implement reconnection logic
        }
    }
}

// MARK: - AsyncStream Consumer Example

/// AsyncStreamConsumer demonstrates using the AsyncStream API
actor AsyncStreamConsumer {
    private var server: MCPServer?
    private var transport: StdioTransport?
    private var isProcessing = false
    
    func setup(server: MCPServer, transport: StdioTransport) {
        self.server = server
        self.transport = transport
    }
    
    /// Process messages using AsyncStream instead of delegate
    func startProcessingWithAsyncStream() async {
        guard let transport = transport,
              let server = server else { return }
        
        isProcessing = true
        print("🔄 Starting AsyncStream message processing")
        
        // Get the async stream of received data
        let dataStream = await transport.receivedData
        
        // Process messages from the stream
        for await data in dataStream {
            guard isProcessing else { break }
            
            print("🔄 AsyncStream received data: \(data.count) bytes")
            
            // Process through server
            if let response = await server.handleMessage(data) {
                try? await transport.send(response)
                print("🔄 AsyncStream sent response: \(response.count) bytes")
            }
        }
        
        print("🔄 AsyncStream processing ended")
    }
    
    func stop() {
        isProcessing = false
    }
}

// MARK: - Interactive Server Example

/// InteractiveServer demonstrates a server that accepts commands via stdin
struct InteractiveServer {
    static func runInteractive() async throws {
        print("=== Interactive MCP Server with StdioTransport ===\n")
        
        // Create server with builder pattern including delegate
        let serverDelegate = CustomServerDelegate()
        let server = await MCPServer.builder(name: "interactive-server", version: "1.0.0")
            .withTitle("Interactive Stdio Server")
            .withInstructions("Server controlled via stdin/stdout")
            .withDelegate(serverDelegate)
            .withToolsListChanged()
            .withResourcesListChanged()
            .build()
        
        // Register interactive tools
        await server.registerTool(SimpleTool(
            name: "get_time",
            title: "Get Current Time",
            handler: { _ in
                MCPToolResult.success(text: "Current time: \(Date().ISO8601Format())")
            }
        ))
        
        await server.registerTool(SimpleTool(
            name: "calculate",
            title: "Calculator",
            inputSchema: [
                "type": "object",
                "properties": [
                    "expression": ["type": "string", "description": "Math expression to evaluate"]
                ]
            ],
            handler: { arguments in
                guard let expr = arguments?["expression"] as? String else {
                    return MCPToolResult.error("Missing expression")
                }
                // In production, use proper expression parser
                return MCPToolResult.success(text: "Result of '\(expr)': [calculated value]")
            }
        ))
        
        // Create transport with delegate
        let transport = StdioTransport()
        let transportHandler = StdioTransportHandler()
        transportHandler.setServer(server)
        
        await transport.setDelegate(transportHandler)
        
        // Start transport
        try await transport.start()
        
        print("Server is ready. Send JSON-RPC messages via stdin.")
        print("Example messages you can send:\n")
        
        printExampleMessages()
        
        // Keep running until interrupted
        // In a real application, you'd have proper signal handling
        try await Task.sleep(nanoseconds: .max)
    }
    
    static func printExampleMessages() {
        print("""
        1. Initialize:
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
        
        2. List tools:
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}
        
        3. Call tool:
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_time"}}
        
        4. Custom method:
        {"jsonrpc":"2.0","id":4,"method":"custom/echo","params":{"message":"Hello!"}}
        
        5. Send notification:
        {"jsonrpc":"2.0","method":"custom/log","params":{"message":"Test log"}}
        
        """)
    }
}

// MARK: - Dual Mode Example

/// DualModeExample shows using both delegate and AsyncStream simultaneously
struct DualModeExample {
    static func runDualMode() async throws {
        print("=== Dual Mode: Delegate + AsyncStream ===\n")
        
        // Create server
        let server = await MCPServer.create(
            name: "dual-mode-server",
            version: "1.0.0",
            title: "Dual Mode Server"
        )
        
        // Create transport
        let transport = StdioTransport()
        
        // Setup delegate for logging and monitoring
        let monitor = TransportMonitor()
        await transport.setDelegate(monitor)
        
        // Setup AsyncStream consumer for message processing
        let consumer = AsyncStreamConsumer()
        await consumer.setup(server: server, transport: transport)
        
        // Start transport
        try await transport.start()
        
        // Start async stream processing in parallel with delegate
        Task {
            await consumer.startProcessingWithAsyncStream()
        }
        
        print("Dual mode active: Delegate monitors, AsyncStream processes")
        
        // Run for demonstration
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
        
        await consumer.stop()
        await transport.stop()
    }
}

/// TransportMonitor only monitors without processing
class TransportMonitor: StdioTransportDelegate {
    private var stats = TransportStats()
    
    struct TransportStats {
        var messagesReceived = 0
        var bytesReceived = 0
        var errors = 0
        var connectTime: Date?
    }
    
    func transport(_ transport: StdioTransport, didReceive data: Data) async {
        stats.messagesReceived += 1
        stats.bytesReceived += data.count
        
        // Only monitor, don't process
        print("📊 Monitor: Message #\(stats.messagesReceived), \(data.count) bytes")
    }
    
    func transportDidConnect(_ transport: StdioTransport) async {
        stats.connectTime = Date()
        print("📊 Monitor: Connected")
    }
    
    func transportDidDisconnect(_ transport: StdioTransport) async {
        print("📊 Monitor: Disconnected")
        printStats()
    }
    
    func transport(_ transport: StdioTransport, didEncounterError error: Error) async {
        stats.errors += 1
        print("📊 Monitor: Error #\(stats.errors)")
    }
    
    private func printStats() {
        print("""
        📊 Transport Statistics:
           Messages: \(stats.messagesReceived)
           Bytes: \(stats.bytesReceived)
           Errors: \(stats.errors)
           Uptime: \(stats.connectTime.map { Date().timeIntervalSince($0) } ?? 0) seconds
        """)
    }
}

// MARK: - Main Entry Point

@main
struct StdioTransportExample {
    static func main() async throws {
        let mode = CommandLine.arguments.dropFirst().first ?? "interactive"
        
        switch mode {
        case "interactive":
            try await InteractiveServer.runInteractive()
            
        case "dual":
            try await DualModeExample.runDualMode()
            
        case "stream":
            print("AsyncStream mode - processing via async stream only")
            // Implementation for stream-only mode
            
        default:
            print("""
            Usage: StdioTransportExample [mode]
            
            Modes:
              interactive - Interactive server with delegate (default)
              dual        - Both delegate and AsyncStream
              stream      - AsyncStream only
            """)
        }
    }
}

// MARK: - Key Concepts

/*
 This example demonstrates:
 
 1. **StdioTransportDelegate** - Handling transport events
    - `transport(_:didReceive:)` - Process incoming data
    - `transportDidConnect(_:)` - Handle connection
    - `transportDidDisconnect(_:)` - Handle disconnection
    - `transport(_:didEncounterError:)` - Handle errors
 
 2. **AsyncStream API** - Alternative to delegate pattern
    - `transport.receivedData` - Get AsyncStream of incoming data
    - Process messages using async/await for-in loop
 
 3. **Dual Mode** - Using both patterns simultaneously
    - Delegate for monitoring/logging
    - AsyncStream for message processing
 
 4. **Integration** - Connecting transport to server
    - Use `server.handleMessage(_:)` to process messages
    - Send responses back through transport
 
 Key APIs:
 - `StdioTransport.setDelegate(_:)`
 - `StdioTransport.receivedData`
 - `MCPServer.handleMessage(_:)`
 - `MCPServer.setDelegate(_:)`
 */
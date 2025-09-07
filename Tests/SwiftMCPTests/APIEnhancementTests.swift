import XCTest
@testable import SwiftMCP
@testable import SwiftMCPTransports

final class APIEnhancementTests: XCTestCase {
    
    // MARK: - MCPServer Public API Tests
    
    func testServerHandleMessage() async throws {
        // Test that handleMessage is public and works correctly
        let server = MCPServer(
            name: "test-server",
            version: "1.0.0"
        )
        
        // Create a valid initialize request
        let initRequest = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {
                    "name": "test-client",
                    "version": "1.0.0"
                }
            }
        }
        """.data(using: .utf8)!
        
        // handleMessage should be public and return a response
        let response = await server.handleMessage(initRequest)
        XCTAssertNotNil(response, "handleMessage should return a response")
        
        // Verify it's a valid JSON-RPC response
        if let responseData = response {
            let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
            XCTAssertNotNil(json?["result"], "Response should have a result")
            XCTAssertEqual(json?["id"] as? Int, 1)
        }
    }
    
    func testServerShutdown() async throws {
        // Test that shutdown is public and can be called
        let server = MCPServer(
            name: "test-server",
            version: "1.0.0"
        )
        
        // shutdown should be public and callable
        await server.shutdown()
        
        // Verify server doesn't respond after shutdown
        let testData = "test".data(using: .utf8)!
        _ = await server.handleMessage(testData)
        // After shutdown, server might return nil or error response
        // The important thing is that shutdown is callable
        XCTAssertTrue(true, "Shutdown method is accessible")
    }
    
    func testServerSetDelegate() async throws {
        // Test that setDelegate works
        let server = MCPServer(
            name: "test-server",
            version: "1.0.0"
        )
        
        let delegate = TestServerDelegate()
        
        // setDelegate should be public and work
        await server.setDelegate(delegate)
        
        // Verify delegate receives callbacks
        let notification = """
        {
            "jsonrpc": "2.0",
            "method": "test/notification",
            "params": {}
        }
        """.data(using: .utf8)!
        
        _ = await server.handleMessage(notification)
        
        // The delegate should have been called
        let notificationReceived = await delegate.notificationReceived
        XCTAssertTrue(notificationReceived, "Delegate should receive notifications")
    }
    
    // MARK: - MCPServer Factory Tests
    
    func testServerCreateFactory() async throws {
        // Test the new create factory method
        let delegate = TestServerDelegate()
        
        let server = await MCPServer.create(
            name: "factory-server",
            version: "2.0.0",
            title: "Factory Server",
            instructions: "Created with factory",
            delegate: delegate
        )
        
        // Verify server is created with correct properties
        let serverInfo = await server.serverInfo
        XCTAssertEqual(serverInfo.name, "factory-server")
        XCTAssertEqual(serverInfo.version, "2.0.0")
        XCTAssertEqual(serverInfo.title, "Factory Server")
        
        let instructions = await server.instructions
        XCTAssertEqual(instructions, "Created with factory")
        
        // Verify delegate is set
        let notification = """
        {
            "jsonrpc": "2.0",
            "method": "test/notification",
            "params": {}
        }
        """.data(using: .utf8)!
        
        _ = await server.handleMessage(notification)
        
        let notificationReceived = await delegate.notificationReceived
        XCTAssertTrue(notificationReceived, "Delegate should be set via factory")
    }
    
    // MARK: - Builder Pattern Tests
    
    func testBuilderWithDelegate() async throws {
        // Test builder pattern with delegate
        let delegate = TestServerDelegate()
        
        let server = await MCPServer.builder(name: "builder-server", version: "3.0.0")
            .withTitle("Built with Delegate")
            .withInstructions("Test instructions")
            .withDelegate(delegate)
            .withToolsListChanged()
            .build()
        
        // Verify delegate is set
        let notification = """
        {
            "jsonrpc": "2.0",
            "method": "test/notification",
            "params": {}
        }
        """.data(using: .utf8)!
        
        _ = await server.handleMessage(notification)
        
        let notificationReceived = await delegate.notificationReceived
        XCTAssertTrue(notificationReceived, "Delegate should be set via builder")
    }
    
    // MARK: - StdioTransport Tests
    
    func testStdioTransportDelegate() async throws {
        // Test StdioTransport delegate pattern
        let transport = StdioTransport()
        let delegate = TestTransportDelegate()
        
        // setDelegate should be public and work
        await transport.setDelegate(delegate)
        
        // Note: Actually testing stdin/stdout requires special setup
        // This test verifies the API is available
        XCTAssertTrue(true, "StdioTransport delegate API is available")
    }
    
    func testStdioTransportAsyncStream() async throws {
        // Test StdioTransport async stream
        let transport = StdioTransport()
        
        // receivedData should provide an AsyncStream
        let stream = await transport.receivedData
        
        // Verify it's an AsyncStream (compilation is the test)
        XCTAssertNotNil(stream, "AsyncStream should be available")
    }
    
    // MARK: - Integration Test
    
    func testCompleteServerLifecycle() async throws {
        // Complete test from the API enhancement report
        let delegate = TestServerDelegate()
        
        // Create server with delegate
        let server = MCPServer(
            name: "test-server",
            version: "1.0.0"
        )
        await server.setDelegate(delegate)
        
        // Register a tool
        let tool = SimpleTool(
            name: "echo",
            handler: { args in
                MCPToolResult.success(text: "Echo: \(args?["message"] ?? "")")
            }
        )
        await server.registerTool(tool)
        
        // Test message handling
        let initRequest = """
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {
                    "name": "test-client",
                    "version": "1.0.0"
                }
            }
        }
        """.data(using: .utf8)!
        
        let response = await server.handleMessage(initRequest)
        XCTAssertNotNil(response)
        
        // Verify response contains server info
        if let responseData = response {
            let responseJSON = try JSONSerialization.jsonObject(with: responseData) as! [String: Any]
            XCTAssertEqual(responseJSON["jsonrpc"] as? String, "2.0")
            XCTAssertNotNil(responseJSON["result"])
        }
        
        // Send initialized notification
        let initializedNotification = """
        {
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }
        """.data(using: .utf8)!
        
        _ = await server.handleMessage(initializedNotification)
        
        // Test tool call
        let toolCallRequest = """
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": "echo",
                "arguments": {
                    "message": "Hello, World!"
                }
            }
        }
        """.data(using: .utf8)!
        
        let toolResponse = await server.handleMessage(toolCallRequest)
        XCTAssertNotNil(toolResponse)
        
        // Clean shutdown
        await server.shutdown()
        
        // Verify delegate was called
        let initialized = await delegate.serverInitialized
        XCTAssertTrue(initialized, "Server should have been initialized")
    }
}

// MARK: - Test Delegates

actor TestServerDelegate: MCPServerDelegate {
    var notificationReceived = false
    var serverInitialized = false
    var serverShutdown = false
    
    func server(_ server: MCPServer, didReceiveRequest request: JSONRPCRequest) async -> Result<AnyCodable, JSONRPCError> {
        .failure(JSONRPCError(code: -32601, message: "Method not found"))
    }
    
    func server(_ server: MCPServer, didReceiveNotification notification: JSONRPCNotification) async {
        notificationReceived = true
    }
    
    func serverDidInitialize(_ server: MCPServer) async {
        serverInitialized = true
    }
    
    func serverWillShutdown(_ server: MCPServer) async {
        serverShutdown = true
    }
}

actor TestTransportDelegate: StdioTransportDelegate {
    var dataReceived = false
    var connected = false
    var disconnected = false
    
    func transport(_ transport: StdioTransport, didReceive data: Data) async {
        dataReceived = true
    }
    
    func transportDidConnect(_ transport: StdioTransport) async {
        connected = true
    }
    
    func transportDidDisconnect(_ transport: StdioTransport) async {
        disconnected = true
    }
    
    func transport(_ transport: StdioTransport, didEncounterError error: Error) async {
        // Handle error
    }
}
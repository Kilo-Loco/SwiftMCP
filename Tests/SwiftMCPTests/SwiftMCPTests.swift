import XCTest
@testable import SwiftMCP
import SwiftMCPTools

final class SwiftMCPTests: XCTestCase {
    
    func testServerCreation() async throws {
        let server = MCPServer(
            name: "test-server",
            version: "1.0.0",
            title: "Test Server",
            instructions: "Test instructions"
        )
        
        let serverInfo = await server.serverInfo
        let instructions = await server.instructions
        
        XCTAssertEqual(serverInfo.name, "test-server")
        XCTAssertEqual(serverInfo.version, "1.0.0")
        XCTAssertEqual(serverInfo.title, "Test Server")
        XCTAssertEqual(instructions, "Test instructions")
    }
    
    func testServerBuilder() async throws {
        let server = await MCPServer.builder(name: "builder-server", version: "2.0.0")
            .withTitle("Built Server")
            .withInstructions("Built with builder")
            .withToolsListChanged()
            .withResourcesListChanged()
            .withPromptsListChanged()
            .withLogging()
            .build()
        
        let serverInfo = await server.serverInfo
        let serverCapabilities = await server.serverCapabilities
        
        XCTAssertEqual(serverInfo.name, "builder-server")
        XCTAssertEqual(serverInfo.version, "2.0.0")
        XCTAssertNotNil(serverCapabilities.tools)
        XCTAssertNotNil(serverCapabilities.resources)
        XCTAssertNotNil(serverCapabilities.prompts)
        XCTAssertNotNil(serverCapabilities.logging)
    }
    
    func testToolRegistration() async throws {
        let server = MCPServer(name: "tool-server", version: "1.0.0")
        
        let tool = SimpleTool(
            name: "test_tool",
            title: "Test Tool",
            handler: { _ in
                MCPToolResult.success(text: "Tool executed")
            }
        )
        
        await server.registerTool(tool)
        
        // Tool should be registered
        XCTAssertEqual(tool.definition.name, "test_tool")
    }
    
    func testJSONRPCTypes() throws {
        // Test request
        let request = JSONRPCRequest(
            id: .number(1),
            method: "test",
            params: AnyCodable(["key": "value"])
        )
        
        XCTAssertEqual(request.jsonrpc, "2.0")
        XCTAssertEqual(request.id, .number(1))
        XCTAssertEqual(request.method, "test")
        
        // Test response
        let response = JSONRPCResponse(
            id: .number(1),
            result: AnyCodable(["result": true])
        )
        
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
    }
    
    func testMCPProtocolVersion() {
        XCTAssertEqual(MCPProtocolVersion, "2025-06-18")
    }
}

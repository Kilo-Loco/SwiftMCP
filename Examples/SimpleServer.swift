//
//  SimpleServer.swift
//  SwiftMCP Examples
//
//  Example of a simple MCP server using SwiftMCP framework
//

import Foundation
import SwiftMCP
import SwiftMCPTools
import SwiftMCPTransports

@main
struct SimpleServer {
    static func main() async throws {
        // Create server using builder pattern
        let server = await MCPServer.builder(name: "simple-server", version: "1.0.0")
            .withTitle("Simple MCP Server")
            .withInstructions("This is a demo server showing SwiftMCP capabilities")
            // Add tools
            .withTool(CalculatorTool())
            .withTool(SimpleTool(
                name: "echo",
                title: "Echo Tool",
                description: "Echoes back the input",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "message": ["type": "string", "description": "Message to echo"]
                    ],
                    "required": ["message"]
                ],
                handler: { arguments in
                    guard let message = arguments?["message"] as? String else {
                        return MCPToolResult.error("Missing message parameter")
                    }
                    return MCPToolResult.success(text: "Echo: \(message)")
                }
            ))
            .withToolsListChanged()
            // Add resources
            .withResource(SimpleResource(
                resource: MCPResource(
                    uri: "config://app/settings",
                    title: "Application Settings",
                    description: "Current application configuration",
                    mimeType: "application/json",
                    text: """
                    {
                        "server": "simple-server",
                        "version": "1.0.0",
                        "features": ["tools", "resources", "prompts"]
                    }
                    """
                )
            ))
            .withResourcesListChanged()
            // Add prompts
            .withPrompt(SimplePrompt(
                name: "greeting",
                title: "Greeting Generator",
                description: "Generates a greeting message",
                arguments: [
                    MCPPromptArgument(name: "name", description: "Name to greet", required: true)
                ],
                generator: { arguments in
                    let name = arguments?["name"] ?? "World"
                    return [
                        .system("You are a friendly assistant."),
                        .user("Please greet \(name) warmly.")
                    ]
                }
            ))
            .withPromptsListChanged()
            // Enable logging
            .withLogging()
            .build()
        
        // Start server with stdio transport
        print("Starting Simple MCP Server...", to: &standardError)
        try await server.start(transport: StdioTransport())
        
        // Keep running
        try await Task.sleep(nanoseconds: .max)
    }
}

// Helper for printing to stderr
var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.write(data)
        }
    }
}
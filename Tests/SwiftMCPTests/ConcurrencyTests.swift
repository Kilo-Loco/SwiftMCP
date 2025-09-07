import XCTest
@testable import SwiftMCP

final class ConcurrencyTests: XCTestCase {
    
    // MARK: - Tool Concurrency Tests
    
    func testToolExecutionFromActorContext() async throws {
        // This test verifies that tools can be executed from within an actor context
        // without causing data race issues (the bug reported in the issue)
        
        let registry = MCPToolRegistry()
        
        let tool = SimpleTool(
            name: "test_tool",
            title: "Test Tool",
            description: "A tool for testing concurrency",
            inputSchema: ["type": "object"],
            handler: { arguments in
                // Verify we can access arguments safely
                if let args = arguments {
                    XCTAssertNotNil(args)
                }
                return MCPToolResult.success(text: "Executed with args: \(arguments ?? [:])")
            }
        )
        
        await registry.register(tool)
        
        // Execute from actor context - this would fail with the original bug
        let testArgs: [String: Any] = ["key": "value", "number": 42]
        let result = try await registry.execute(name: "test_tool", arguments: testArgs)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result.isError, false)
    }
    
    func testCustomToolExecutorFromActorContext() async throws {
        // Test custom tool executor implementation
        struct CustomTool: MCPToolExecutor {
            let definition: MCPTool
            private let executionCount = ActorCounter()
            
            init() {
                self.definition = MCPTool(
                    name: "custom_tool",
                    title: "Custom Tool",
                    description: "Custom tool implementation"
                )
            }
            
            nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
                // This should work without data race issues
                await executionCount.increment()
                let count = await executionCount.value
                return MCPToolResult.success(text: "Executed \(count) times")
            }
        }
        
        let registry = MCPToolRegistry()
        let customTool = CustomTool()
        
        await registry.register(customTool)
        
        // Execute multiple times concurrently
        let results = await withTaskGroup(of: MCPToolResult?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await registry.execute(name: "custom_tool", arguments: nil)
                }
            }
            
            var results: [MCPToolResult] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
        
        XCTAssertEqual(results.count, 10)
    }
    
    // MARK: - Resource Concurrency Tests
    
    func testResourceReadFromActorContext() async throws {
        let registry = MCPResourceRegistry()
        
        let resource = SimpleResource(
            uri: "test://resource",
            title: "Test Resource",
            description: "A test resource",
            mimeType: "text/plain",
            reader: {
                MCPResource(
                    uri: "test://resource",
                    title: "Test Resource",
                    text: "Resource content"
                )
            }
        )
        
        await registry.register(resource)
        
        // Read from actor context - this would fail with the original bug
        let result = try await registry.read(uri: "test://resource")
        
        XCTAssertEqual(result.uri, "test://resource")
        XCTAssertEqual(result.text, "Resource content")
    }
    
    func testDynamicResourceFromActorContext() async throws {
        let dynamicResource = DynamicResource(
            uri: "dynamic://resource",
            title: "Dynamic Resource",
            initialContent: "Initial",
            updateHandler: {
                MCPResource(
                    uri: "dynamic://resource",
                    title: "Dynamic Resource",
                    text: "Updated content"
                )
            }
        )
        
        let registry = MCPResourceRegistry()
        await registry.register(dynamicResource)
        
        // Test concurrent reads
        let results = await withTaskGroup(of: MCPResource?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try? await registry.read(uri: "dynamic://resource")
                }
            }
            
            var results: [MCPResource] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
        
        XCTAssertEqual(results.count, 5)
        results.forEach { resource in
            XCTAssertEqual(resource.uri, "dynamic://resource")
        }
    }
    
    // MARK: - Prompt Concurrency Tests
    
    func testPromptGenerationFromActorContext() async throws {
        let registry = MCPPromptRegistry()
        
        let prompt = SimplePrompt(
            name: "test_prompt",
            title: "Test Prompt",
            description: "A test prompt",
            arguments: [
                MCPPromptArgument(name: "input", description: "Input text", required: true)
            ],
            generator: { arguments in
                let input = arguments?["input"] ?? "default"
                return [
                    MCPPromptMessage.system("You are a test assistant"),
                    MCPPromptMessage.user("Process: \(input)")
                ]
            }
        )
        
        await registry.register(prompt)
        
        // Generate from actor context - this would fail with the original bug
        let messages = try await registry.generate(
            name: "test_prompt",
            arguments: ["input": "test input"]
        )
        
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[1].role, "user")
    }
    
    func testCustomPromptProviderFromActorContext() async throws {
        struct CustomPromptProvider: MCPPromptProvider {
            let definition: MCPPrompt
            
            init() {
                self.definition = MCPPrompt(
                    name: "custom_prompt",
                    title: "Custom Prompt"
                )
            }
            
            nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
                // This should work without data race issues
                let context = arguments?["context"] ?? "default"
                return [
                    MCPPromptMessage.assistant("Generated with context: \(context)")
                ]
            }
        }
        
        let registry = MCPPromptRegistry()
        let customPrompt = CustomPromptProvider()
        
        await registry.register(customPrompt)
        
        // Execute multiple times concurrently
        let results = await withTaskGroup(of: [MCPPromptMessage]?.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try? await registry.generate(
                        name: "custom_prompt",
                        arguments: ["context": "test-\(i)"]
                    )
                }
            }
            
            var results: [[MCPPromptMessage]] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
        
        XCTAssertEqual(results.count, 5)
    }
    
    // MARK: - Integration Tests
    
    func testServerWithToolsInStrictConcurrency() async throws {
        // This test simulates the actual usage pattern that would fail with the bug
        let server = MCPServer(name: "test-server", version: "1.0.0")
        
        // Register multiple tools
        for i in 0..<3 {
            let tool = SimpleTool(
                name: "tool_\(i)",
                title: "Tool \(i)",
                handler: { arguments in
                    MCPToolResult.success(text: "Tool \(i) executed")
                }
            )
            await server.registerTool(tool)
        }
        
        // Create separate registry to test execution
        let registry = MCPToolRegistry()
        for i in 0..<3 {
            let tool = SimpleTool(
                name: "tool_\(i)",
                title: "Tool \(i)",
                handler: { arguments in
                    MCPToolResult.success(text: "Tool \(i) executed")
                }
            )
            await registry.register(tool)
        }
        
        // Execute tools concurrently from actor context
        let results = await withTaskGroup(of: MCPToolResult?.self) { group in
            for i in 0..<3 {
                group.addTask {
                    try? await registry.execute(
                        name: "tool_\(i)",
                        arguments: ["index": i]
                    )
                }
            }
            
            var results: [MCPToolResult] = []
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
        
        XCTAssertEqual(results.count, 3)
        results.forEach { result in
            XCTAssertEqual(result.isError, false)
        }
    }
    
    func testMixedCapabilitiesInStrictConcurrency() async throws {
        // Test all capabilities together to ensure no cross-contamination of concurrency issues
        let toolRegistry = MCPToolRegistry()
        let resourceRegistry = MCPResourceRegistry()
        let promptRegistry = MCPPromptRegistry()
        
        // Register a tool
        let tool = SimpleTool(
            name: "mixed_tool",
            handler: { _ in MCPToolResult.success(text: "Mixed tool") }
        )
        await toolRegistry.register(tool)
        
        // Register a resource
        let resource = SimpleResource(
            uri: "mixed://resource",
            reader: { MCPResource(uri: "mixed://resource", text: "Mixed resource") }
        )
        await resourceRegistry.register(resource)
        
        // Register a prompt
        let prompt = SimplePrompt(
            name: "mixed_prompt",
            generator: { _ in [MCPPromptMessage.user("Mixed prompt")] }
        )
        await promptRegistry.register(prompt)
        
        // Execute all capabilities concurrently
        async let toolResult = toolRegistry.execute(name: "mixed_tool", arguments: nil)
        async let resourceResult = resourceRegistry.read(uri: "mixed://resource")
        async let promptResult = promptRegistry.generate(name: "mixed_prompt", arguments: nil)
        
        let (toolRes, resourceRes, promptRes) = try await (toolResult, resourceResult, promptResult)
        
        XCTAssertNotNil(toolRes)
        XCTAssertEqual(resourceRes.uri, "mixed://resource")
        XCTAssertEqual(promptRes.count, 1)
    }
}

// MARK: - Helper Types

private actor ActorCounter {
    private var count = 0
    
    var value: Int {
        count
    }
    
    func increment() {
        count += 1
    }
}
//
//  CustomProtocolImplementations.swift
//  SwiftMCP Examples
//
//  Demonstrates proper implementation of MCP protocols with Swift 6 concurrency
//  Shows the nonisolated pattern and various implementation strategies
//

import Foundation
import SwiftMCP

// MARK: - Custom Tool Implementations

/// StatelessTool - Simple tool without internal state
struct StatelessTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "stateless_calculator",
        title: "Stateless Calculator",
        description: "Performs calculations without maintaining state"
    )
    
    /// Key Point: Must be marked nonisolated for protocol conformance
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let operation = arguments?["operation"] as? String,
              let a = arguments?["a"] as? Double,
              let b = arguments?["b"] as? Double else {
            return MCPToolResult.error("Missing required parameters")
        }
        
        let result: Double
        switch operation {
        case "add": result = a + b
        case "subtract": result = a - b
        case "multiply": result = a * b
        case "divide":
            guard b != 0 else {
                return MCPToolResult.error("Division by zero")
            }
            result = a / b
        default:
            return MCPToolResult.error("Unknown operation: \(operation)")
        }
        
        return MCPToolResult.success(text: "Result: \(result)")
    }
}

/// StatefulTool - Tool with actor-isolated state
class StatefulTool: MCPToolExecutor {
    let definition: MCPTool
    private let stateManager: StateManager
    
    init(name: String) {
        self.definition = MCPTool(
            name: name,
            title: "Stateful Tool",
            description: "Tool that maintains state across executions"
        )
        self.stateManager = StateManager()
    }
    
    /// Actor for managing tool state
    private actor StateManager {
        private var executionCount = 0
        private var lastResult: String?
        private var history: [String] = []
        
        func recordExecution(result: String) {
            executionCount += 1
            lastResult = result
            history.append(result)
            
            // Keep history bounded
            if history.count > 100 {
                history.removeFirst()
            }
        }
        
        func getStats() -> [String: Any] {
            [
                "execution_count": executionCount,
                "last_result": lastResult ?? "none",
                "history_size": history.count
            ]
        }
    }
    
    /// Key Point: nonisolated method can safely call into actor
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        let input = arguments?["input"] as? String ?? "default"
        let result = "Processed: \(input)"
        
        // Record in state manager (actor-isolated)
        await stateManager.recordExecution(result: result)
        
        // Get current stats
        let stats = await stateManager.getStats()
        
        return MCPToolResult(
            content: [
                .text(MCPTextContent(
                    text: result,
                    annotations: MCPAnnotations(
                        audience: ["developer"],
                        metadata: stats.mapValues { String(describing: $0) }
                    )
                ))
            ],
            isError: false
        )
    }
}

/// GenericTool - Demonstrates generic tool implementation
struct GenericTool<T: Codable & Sendable>: MCPToolExecutor {
    let definition: MCPTool
    private let processor: @Sendable (T) async throws -> String
    
    init(
        name: String,
        title: String,
        processor: @escaping @Sendable (T) async throws -> String
    ) {
        self.definition = MCPTool(name: name, title: title)
        self.processor = processor
    }
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let data = arguments?["data"] else {
            return MCPToolResult.error("Missing data parameter")
        }
        
        // Convert arguments to expected type
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let typedData = try JSONDecoder().decode(T.self, from: jsonData)
        
        // Process with the provided processor
        let result = try await processor(typedData)
        
        return MCPToolResult.success(text: result)
    }
}

// MARK: - Custom Resource Implementations

/// ImmutableResource - Resource that never changes
struct ImmutableResource: MCPResourceProvider {
    private let resource: MCPResource
    
    init(uri: String, content: String) {
        self.resource = MCPResource(
            uri: uri,
            title: "Immutable Resource",
            mimeType: "text/plain",
            text: content
        )
    }
    
    var definition: MCPResource {
        get async { resource }
    }
    
    nonisolated func read() async throws -> MCPResource {
        resource
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // Immutable resource sends once and never updates
        handler(resource)
    }
    
    nonisolated func unsubscribe() async {
        // No-op for immutable resource
    }
}

/// ComputedResource - Resource computed on each read
class ComputedResource: MCPResourceProvider {
    private let uri: String
    private let computer: @Sendable () async throws -> String
    
    init(uri: String, computer: @escaping @Sendable () async throws -> String) {
        self.uri = uri
        self.computer = computer
    }
    
    var definition: MCPResource {
        get async {
            MCPResource(
                uri: uri,
                title: "Computed Resource",
                description: "Dynamically computed resource"
            )
        }
    }
    
    nonisolated func read() async throws -> MCPResource {
        let content = try await computer()
        return MCPResource(
            uri: uri,
            title: "Computed Resource",
            text: content
        )
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        // Send initial value
        let resource = try await read()
        handler(resource)
        
        // For computed resources, we might poll periodically
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if let updated = try? await read() {
                    handler(updated)
                }
            }
        }
    }
    
    nonisolated func unsubscribe() async {
        // Cancellation handled by Task
    }
}

/// ObservableResource - Resource that notifies on changes
actor ObservableResource: MCPResourceProvider {
    private let uri: String
    private var content: String
    private var observers: [UUID: @Sendable (MCPResource) -> Void] = [:]
    
    init(uri: String, initialContent: String) {
        self.uri = uri
        self.content = initialContent
    }
    
    nonisolated var definition: MCPResource {
        get async {
            await MCPResource(
                uri: self.uri,
                title: "Observable Resource",
                description: "Resource with change notifications"
            )
        }
    }
    
    /// Update the resource content and notify observers
    func updateContent(_ newContent: String) {
        content = newContent
        let resource = MCPResource(uri: uri, text: content)
        
        // Notify all observers
        for observer in observers.values {
            observer(resource)
        }
    }
    
    nonisolated func read() async throws -> MCPResource {
        await self._read()
    }
    
    private func _read() async -> MCPResource {
        MCPResource(uri: uri, text: content)
    }
    
    nonisolated func subscribe(handler: @escaping @Sendable (MCPResource) -> Void) async throws {
        await self._subscribe(handler: handler)
    }
    
    private func _subscribe(handler: @escaping @Sendable (MCPResource) -> Void) {
        let id = UUID()
        observers[id] = handler
        
        // Send current value immediately
        let resource = MCPResource(uri: uri, text: content)
        handler(resource)
    }
    
    nonisolated func unsubscribe() async {
        await self._unsubscribe()
    }
    
    private func _unsubscribe() {
        observers.removeAll()
    }
}

// MARK: - Custom Prompt Implementations

/// TemplatePrompt - Simple template-based prompt
struct TemplatePrompt: MCPPromptProvider {
    let definition: MCPPrompt
    private let template: String
    
    init(name: String, template: String) {
        self.definition = MCPPrompt(
            name: name,
            title: "Template Prompt",
            arguments: [
                MCPPromptArgument(name: "variables", description: "Template variables")
            ]
        )
        self.template = template
    }
    
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        var result = template
        
        // Replace template variables
        if let variables = arguments {
            for (key, value) in variables {
                result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
            }
        }
        
        return [MCPPromptMessage.user(result)]
    }
}

/// ChainedPrompt - Prompt that chains multiple sub-prompts
class ChainedPrompt: MCPPromptProvider {
    let definition: MCPPrompt
    private let prompts: [MCPPromptProvider]
    
    init(name: String, prompts: [MCPPromptProvider]) {
        self.definition = MCPPrompt(
            name: name,
            title: "Chained Prompt",
            description: "Combines multiple prompts"
        )
        self.prompts = prompts
    }
    
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        var allMessages: [MCPPromptMessage] = []
        
        // Generate messages from each prompt in sequence
        for prompt in prompts {
            let messages = try await prompt.generate(arguments: arguments)
            allMessages.append(contentsOf: messages)
        }
        
        return allMessages
    }
}

/// AdaptivePrompt - Prompt that adapts based on context
actor AdaptivePrompt: MCPPromptProvider {
    nonisolated var definition: MCPPrompt {
        get async {
            MCPPrompt(
                name: "adaptive_prompt",
                title: "Adaptive Prompt",
                description: "Adapts based on usage patterns"
            )
        }
    }
    
    private var usagePatterns: [String: Int] = [:]
    private var userPreferences: [String: String] = [:]
    
    func recordUsage(pattern: String) {
        usagePatterns[pattern, default: 0] += 1
    }
    
    func setPreference(key: String, value: String) {
        userPreferences[key] = value
    }
    
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        await self._generate(arguments: arguments)
    }
    
    private func _generate(arguments: [String: String]?) async -> [MCPPromptMessage] {
        let topic = arguments?["topic"] ?? "general"
        
        // Record usage
        recordUsage(pattern: topic)
        
        // Adapt based on usage patterns
        let style = userPreferences["style"] ?? "standard"
        let depth = usagePatterns[topic, default: 0] > 5 ? "advanced" : "basic"
        
        let systemPrompt = """
        You are an adaptive assistant. Style: \(style), Depth: \(depth).
        Topic frequency: \(usagePatterns[topic, default: 0]) times.
        """
        
        let userPrompt = "Help with: \(topic)"
        
        return [
            MCPPromptMessage.system(systemPrompt),
            MCPPromptMessage.user(userPrompt)
        ]
    }
}

// MARK: - Advanced Pattern: Composable Implementations

/// Protocol for composable tool behaviors
protocol ToolBehavior: Sendable {
    func preExecute(arguments: [String: Any]?) async throws
    func postExecute(result: MCPToolResult) async throws -> MCPToolResult
}

/// Logging behavior
struct LoggingBehavior: ToolBehavior {
    private let logger = Logger()
    
    actor Logger {
        func log(_ message: String) {
            print("[LOG] \(Date()): \(message)")
        }
    }
    
    func preExecute(arguments: [String: Any]?) async throws {
        await logger.log("Executing with arguments: \(String(describing: arguments))")
    }
    
    func postExecute(result: MCPToolResult) async throws -> MCPToolResult {
        await logger.log("Execution completed with result: \(String(describing: result))")
        return result
    }
}

/// Validation behavior
struct ValidationBehavior: ToolBehavior {
    private let validator: @Sendable ([String: Any]?) throws -> Void
    
    init(validator: @escaping @Sendable ([String: Any]?) throws -> Void) {
        self.validator = validator
    }
    
    func preExecute(arguments: [String: Any]?) async throws {
        try validator(arguments)
    }
    
    func postExecute(result: MCPToolResult) async throws -> MCPToolResult {
        result
    }
}

/// Composable tool with behaviors
struct ComposableTool: MCPToolExecutor {
    let definition: MCPTool
    private let behaviors: [ToolBehavior]
    private let implementation: @Sendable ([String: Any]?) async throws -> MCPToolResult
    
    init(
        name: String,
        behaviors: [ToolBehavior] = [],
        implementation: @escaping @Sendable ([String: Any]?) async throws -> MCPToolResult
    ) {
        self.definition = MCPTool(name: name)
        self.behaviors = behaviors
        self.implementation = implementation
    }
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        // Apply pre-execution behaviors
        for behavior in behaviors {
            try await behavior.preExecute(arguments: arguments)
        }
        
        // Execute core implementation
        var result = try await implementation(arguments)
        
        // Apply post-execution behaviors
        for behavior in behaviors.reversed() {
            result = try await behavior.postExecute(result: result)
        }
        
        return result
    }
}

// MARK: - Usage Examples

func demonstrateCustomImplementations() async throws {
    print("=== Custom Protocol Implementations Demo ===\n")
    
    // 1. Stateless tool
    let statelessTool = StatelessTool()
    let calcResult = try await statelessTool.execute(
        arguments: ["operation": "multiply", "a": 5.0, "b": 3.0]
    )
    print("1. Stateless tool result: \(calcResult)")
    
    // 2. Stateful tool
    let statefulTool = StatefulTool(name: "stateful_demo")
    for i in 1...3 {
        let result = try await statefulTool.execute(
            arguments: ["input": "iteration-\(i)"]
        )
        print("   Stateful execution \(i): \(result)")
    }
    
    // 3. Generic tool
    struct UserData: Codable, Sendable {
        let name: String
        let age: Int
    }
    
    let userTool = GenericTool<UserData>(
        name: "user_processor",
        title: "User Processor"
    ) { user in
        "Processed user: \(user.name), age \(user.age)"
    }
    
    let userResult = try await userTool.execute(
        arguments: ["data": ["name": "Alice", "age": 30]]
    )
    print("2. Generic tool result: \(userResult)")
    
    // 4. Observable resource
    let observableResource = ObservableResource(
        uri: "observable://demo",
        initialContent: "Initial content"
    )
    
    await observableResource.subscribe { resource in
        print("   Resource updated: \(resource.text ?? "empty")")
    }
    
    await observableResource.updateContent("Updated content")
    
    // 5. Adaptive prompt
    let adaptivePrompt = AdaptivePrompt()
    
    for i in 1...3 {
        let messages = await adaptivePrompt.generate(
            arguments: ["topic": "swift"]
        )
        print("3. Adaptive prompt iteration \(i): \(messages.count) messages")
    }
    
    // 6. Composable tool with behaviors
    let composableTool = ComposableTool(
        name: "composable_demo",
        behaviors: [
            LoggingBehavior(),
            ValidationBehavior { args in
                guard args?["required"] != nil else {
                    throw ValidationError.missingRequired
                }
            }
        ],
        implementation: { args in
            MCPToolResult.success(text: "Executed with: \(String(describing: args))")
        }
    )
    
    let composableResult = try await composableTool.execute(
        arguments: ["required": "value", "optional": "extra"]
    )
    print("4. Composable tool result: \(composableResult)")
}

enum ValidationError: Error {
    case missingRequired
}

// MARK: - Best Practices Summary

/*
 Custom Protocol Implementation Best Practices:
 
 1. **Always use nonisolated**: All protocol methods must be marked nonisolated.
 
 2. **Actor pattern for state**: Use actors for any mutable state management.
 
 3. **Sendable closures**: Mark all closures as @Sendable for thread safety.
 
 4. **Private actor methods**: Use private actor methods called from nonisolated wrappers.
 
 5. **Generic constraints**: Add Sendable constraints to generic types.
 
 6. **Composition over inheritance**: Use protocol composition for flexible designs.
 
 7. **Error handling**: Provide clear error messages and handle all edge cases.
 
 8. **Resource cleanup**: Implement proper cleanup in unsubscribe/deinit.
 
 9. **Testing**: Test implementations with concurrent access patterns.
 
 10. **Documentation**: Document concurrency assumptions and guarantees.
 
 Key Pattern for Actor-based Implementations:
 ```swift
 actor MyImplementation: MCPProtocol {
     // Actor-isolated state
     private var state: State
     
     // Nonisolated protocol method
     nonisolated func protocolMethod() async throws -> Result {
         // Call into actor-isolated implementation
         try await self._protocolMethod()
     }
     
     // Actor-isolated implementation
     private func _protocolMethod() async throws -> Result {
         // Safe access to state
         return processState(state)
     }
 }
 ```
 */
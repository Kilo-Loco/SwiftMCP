//
//  ConcurrentOperationsExample.swift
//  SwiftMCP Examples
//
//  Demonstrates concurrent operations across tools, resources, and prompts
//  Shows how to handle multiple simultaneous requests safely
//

import Foundation
import SwiftMCP

// MARK: - Orchestration Service

/// OrchestrationService coordinates complex multi-step operations
actor OrchestrationService {
    struct OperationResult {
        let id: String
        let status: Status
        let startTime: Date
        let endTime: Date?
        let results: [String: Any]
        let errors: [String]
        
        enum Status {
            case pending, running, completed, failed
        }
    }
    
    private var operations: [String: OperationResult] = [:]
    private var runningOperations = Set<String>()
    private let maxConcurrentOps = 10
    
    func startOperation(id: String) async throws {
        guard runningOperations.count < maxConcurrentOps else {
            throw OrchestrationError.tooManyOperations
        }
        
        operations[id] = OperationResult(
            id: id,
            status: .running,
            startTime: Date(),
            endTime: nil,
            results: [:],
            errors: []
        )
        runningOperations.insert(id)
    }
    
    func updateOperation(id: String, results: [String: Any] = [:], errors: [String] = []) {
        guard var operation = operations[id] else { return }
        
        var updatedResults = operation.results
        for (key, value) in results {
            updatedResults[key] = value
        }
        
        operation = OperationResult(
            id: id,
            status: operation.status,
            startTime: operation.startTime,
            endTime: operation.endTime,
            results: updatedResults,
            errors: operation.errors + errors
        )
        
        operations[id] = operation
    }
    
    func completeOperation(id: String, success: Bool) {
        guard var operation = operations[id] else { return }
        
        operation = OperationResult(
            id: id,
            status: success ? .completed : .failed,
            startTime: operation.startTime,
            endTime: Date(),
            results: operation.results,
            errors: operation.errors
        )
        
        operations[id] = operation
        runningOperations.remove(id)
    }
    
    func getOperation(id: String) -> OperationResult? {
        operations[id]
    }
    
    func getActiveOperations() -> [OperationResult] {
        operations.values.filter { $0.status == .running }
    }
}

enum OrchestrationError: Error {
    case tooManyOperations
    case operationNotFound
}

// MARK: - Data Processing Pipeline

/// DataPipelineTool demonstrates complex data processing with multiple stages
struct DataPipelineTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "data_pipeline",
        title: "Data Processing Pipeline",
        description: "Processes data through multiple concurrent stages",
        inputSchema: [
            "type": "object",
            "properties": [
                "data": [
                    "type": "array",
                    "description": "Input data array"
                ],
                "stages": [
                    "type": "array",
                    "description": "Processing stages to apply"
                ]
            ],
            "required": ["data"]
        ]
    )
    
    private let orchestrator = OrchestrationService()
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let data = arguments?["data"] as? [Any] else {
            return MCPToolResult.error("Missing or invalid data parameter")
        }
        
        let stages = (arguments?["stages"] as? [String]) ?? ["validate", "transform", "aggregate"]
        let operationId = UUID().uuidString
        
        do {
            try await orchestrator.startOperation(id: operationId)
            
            // Process data through stages concurrently where possible
            let results = try await processDataPipeline(
                data: data,
                stages: stages,
                operationId: operationId
            )
            
            await orchestrator.completeOperation(id: operationId, success: true)
            
            let jsonData = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            return MCPToolResult.success(text: jsonString)
        } catch {
            await orchestrator.completeOperation(id: operationId, success: false)
            return MCPToolResult.error("Pipeline failed: \(error.localizedDescription)")
        }
    }
    
    private func processDataPipeline(
        data: [Any],
        stages: [String],
        operationId: String
    ) async throws -> [String: Any] {
        var processedData = data
        var stageResults: [String: Any] = [:]
        
        for stage in stages {
            let (result, processed) = try await processStage(
                stage: stage,
                data: processedData,
                operationId: operationId
            )
            
            stageResults[stage] = result
            processedData = processed
            
            await orchestrator.updateOperation(
                id: operationId,
                results: [stage: result]
            )
        }
        
        return [
            "stages": stageResults,
            "final_data": processedData,
            "operation_id": operationId
        ]
    }
    
    private func processStage(
        stage: String,
        data: [Any],
        operationId: String
    ) async throws -> (result: [String: Any], processed: [Any]) {
        // Simulate stage processing
        try await Task.sleep(nanoseconds: 100_000_000)
        
        switch stage {
        case "validate":
            let validCount = data.count
            let invalidCount = 0
            return (
                ["valid": validCount, "invalid": invalidCount],
                data
            )
            
        case "transform":
            let transformed = data.map { item in
                // Simple transformation example
                if let str = item as? String {
                    return str.uppercased()
                }
                return item
            }
            return (
                ["transformed_count": transformed.count],
                transformed
            )
            
        case "aggregate":
            let aggregated: [String: Any] = [
                "count": data.count,
                "types": Set(data.map { type(of: $0) }).count
            ]
            return (aggregated, data)
            
        default:
            return (["status": "unknown stage"], data)
        }
    }
}

// MARK: - Batch Operations Tool

/// BatchOperationsTool demonstrates handling multiple operations concurrently
struct BatchOperationsTool: MCPToolExecutor {
    let definition = MCPTool(
        name: "batch_operations",
        title: "Batch Operations Processor",
        description: "Executes multiple operations concurrently with rate limiting",
        inputSchema: [
            "type": "object",
            "properties": [
                "operations": [
                    "type": "array",
                    "description": "Array of operations to execute"
                ],
                "max_concurrent": [
                    "type": "number",
                    "description": "Maximum concurrent operations"
                ]
            ],
            "required": ["operations"]
        ]
    )
    
    nonisolated func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let operations = arguments?["operations"] as? [[String: Any]] else {
            return MCPToolResult.error("Missing or invalid operations parameter")
        }
        
        let maxConcurrent = (arguments?["max_concurrent"] as? Int) ?? 5
        
        // Execute operations with controlled concurrency
        let results = try await withThrowingTaskGroup(of: OperationResult.self) { group in
            var results: [OperationResult] = []
            var activeCount = 0
            var operationIndex = 0
            
            // Start initial batch
            while operationIndex < min(maxConcurrent, operations.count) {
                let operation = operations[operationIndex]
                group.addTask {
                    try await self.executeOperation(operation)
                }
                activeCount += 1
                operationIndex += 1
            }
            
            // Process results and add new operations as others complete
            for try await result in group {
                results.append(result)
                activeCount -= 1
                
                // Add next operation if available
                if operationIndex < operations.count {
                    let operation = operations[operationIndex]
                    group.addTask {
                        try await self.executeOperation(operation)
                    }
                    activeCount += 1
                    operationIndex += 1
                }
            }
            
            return results
        }
        
        // Summarize results
        let summary: [String: Any] = [
            "total": results.count,
            "successful": results.filter { $0.success }.count,
            "failed": results.filter { !$0.success }.count,
            "results": results.map { result in
                [
                    "id": result.id,
                    "success": result.success,
                    "duration": result.duration,
                    "output": result.output
                ]
            }
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return MCPToolResult.success(text: jsonString)
    }
    
    private struct OperationResult {
        let id: String
        let success: Bool
        let duration: TimeInterval
        let output: String
    }
    
    private func executeOperation(_ operation: [String: Any]) async throws -> OperationResult {
        let id = (operation["id"] as? String) ?? UUID().uuidString
        let startTime = Date()
        
        // Simulate operation execution
        let delay = UInt64.random(in: 50_000_000...500_000_000)
        try await Task.sleep(nanoseconds: delay)
        
        let success = Bool.random()
        let duration = Date().timeIntervalSince(startTime)
        let output = success ? "Operation completed" : "Operation failed"
        
        return OperationResult(
            id: id,
            success: success,
            duration: duration,
            output: output
        )
    }
}

// MARK: - Concurrent Server Example

/// ConcurrentMCPServer demonstrates a server handling multiple concurrent requests
class ConcurrentMCPServer {
    private let toolRegistry = MCPToolRegistry()
    private let resourceRegistry = MCPResourceRegistry()
    private let promptRegistry = MCPPromptRegistry()
    private let orchestrator = OrchestrationService()
    
    init() {
        Task {
            await setupServer()
        }
    }
    
    private func setupServer() async {
        // Register tools
        await toolRegistry.register(DataPipelineTool())
        await toolRegistry.register(BatchOperationsTool())
        await toolRegistry.register(DatabaseQueryTool())
        await toolRegistry.register(AnalyticsTool())
        await toolRegistry.register(CacheTool())
        
        // Register resources
        await resourceRegistry.register(SystemMetricsResource())
        await resourceRegistry.register(ConfigurationResource())
        await resourceRegistry.register(LogStreamResource())
        
        // Register prompts
        await promptRegistry.register(CodeReviewPrompt())
        await promptRegistry.register(DocumentationPrompt())
        await promptRegistry.register(ProblemSolvingPrompt())
    }
    
    /// Demonstrates handling multiple concurrent client requests
    func handleConcurrentRequests() async throws {
        // Simulate multiple clients making requests simultaneously
        await withTaskGroup(of: Void.self) { group in
            // Client 1: Execute data pipeline
            group.addTask {
                _ = try? await self.toolRegistry.execute(
                    name: "data_pipeline",
                    arguments: [
                        "data": ["item1", "item2", "item3"],
                        "stages": ["validate", "transform"]
                    ]
                )
            }
            
            // Client 2: Batch operations
            group.addTask {
                let operations = (1...10).map { i in
                    ["id": "op-\(i)", "type": "process"]
                }
                _ = try? await self.toolRegistry.execute(
                    name: "batch_operations",
                    arguments: [
                        "operations": operations,
                        "max_concurrent": 3
                    ]
                )
            }
            
            // Client 3: Read system metrics
            group.addTask {
                _ = try? await self.resourceRegistry.read(uri: "system://metrics")
            }
            
            // Client 4: Generate code review
            group.addTask {
                _ = try? await self.promptRegistry.generate(
                    name: "code_review",
                    arguments: [
                        "code": "func example() { }",
                        "language": "Swift"
                    ]
                )
            }
            
            // Client 5: Analytics tracking
            group.addTask {
                for event in ["login", "view", "action"] {
                    _ = try? await self.toolRegistry.execute(
                        name: "analytics",
                        arguments: ["action": "track", "event": event]
                    )
                }
            }
        }
    }
    
    /// Demonstrates complex orchestrated workflow
    func executeComplexWorkflow(userId: String) async throws -> [String: Any] {
        let workflowId = UUID().uuidString
        try await orchestrator.startOperation(id: workflowId)
        
        var workflowResults: [String: Any] = [:]
        
        // Step 1: Fetch user context and system status in parallel
        async let userAnalytics = toolRegistry.execute(
            name: "analytics",
            arguments: ["action": "report"]
        )
        async let systemMetrics = resourceRegistry.read(uri: "system://metrics")
        async let appConfig = resourceRegistry.read(uri: "config://app/settings")
        
        // Wait for all initial data
        let (analytics, metrics, config) = try await (userAnalytics, systemMetrics, appConfig)
        
        workflowResults["initial_data"] = [
            "analytics": analytics,
            "metrics": metrics.text ?? "",
            "config": config.text ?? ""
        ]
        
        await orchestrator.updateOperation(
            id: workflowId,
            results: ["step1": "completed"]
        )
        
        // Step 2: Process data based on initial results
        let pipelineResult = try await toolRegistry.execute(
            name: "data_pipeline",
            arguments: [
                "data": [analytics, metrics.text ?? "", config.text ?? ""],
                "stages": ["validate", "transform", "aggregate"]
            ]
        )
        
        workflowResults["pipeline_result"] = pipelineResult
        
        await orchestrator.updateOperation(
            id: workflowId,
            results: ["step2": "completed"]
        )
        
        // Step 3: Generate documentation for the workflow
        let documentation = try await promptRegistry.generate(
            name: "documentation",
            arguments: [
                "code": "Workflow \(workflowId)",
                "type": "readme"
            ]
        )
        
        workflowResults["documentation"] = documentation.map { msg in
            ["role": msg.role, "content": String(describing: msg.content)]
        }
        
        await orchestrator.completeOperation(id: workflowId, success: true)
        
        return [
            "workflow_id": workflowId,
            "status": "completed",
            "results": workflowResults
        ]
    }
}

// MARK: - Stress Test Example

/// StressTestRunner demonstrates the system under high concurrent load
class StressTestRunner {
    private let server = ConcurrentMCPServer()
    
    func runStressTest(
        clients: Int = 100,
        requestsPerClient: Int = 10
    ) async throws {
        print("Starting stress test with \(clients) clients, \(requestsPerClient) requests each")
        
        let startTime = Date()
        var successCount = 0
        var failureCount = 0
        
        // Create concurrent clients
        let results = await withTaskGroup(of: Bool.self) { group in
            for clientId in 0..<clients {
                group.addTask {
                    await self.simulateClient(
                        id: clientId,
                        requests: requestsPerClient
                    )
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
                if result {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }
            return results
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let totalRequests = clients * requestsPerClient
        let requestsPerSecond = Double(totalRequests) / duration
        
        print("""
        Stress Test Results:
        - Total requests: \(totalRequests)
        - Duration: \(String(format: "%.2f", duration)) seconds
        - Requests/second: \(String(format: "%.2f", requestsPerSecond))
        - Success rate: \(String(format: "%.1f%%", Double(successCount) / Double(clients) * 100))
        - Failures: \(failureCount)
        """)
    }
    
    private func simulateClient(id: Int, requests: Int) async -> Bool {
        for requestNum in 0..<requests {
            // Random delay between requests
            let delay = UInt64.random(in: 10_000_000...100_000_000)
            try? await Task.sleep(nanoseconds: delay)
            
            // Execute random operation
            let operationType = Int.random(in: 0...4)
            
            do {
                switch operationType {
                case 0:
                    // Tool execution
                    _ = try await server.toolRegistry.execute(
                        name: "cache",
                        arguments: [
                            "operation": "set",
                            "key": "client-\(id)-\(requestNum)",
                            "value": "test-value"
                        ]
                    )
                    
                case 1:
                    // Resource read
                    _ = try await server.resourceRegistry.read(uri: "logs://app/stream")
                    
                case 2:
                    // Prompt generation
                    _ = try await server.promptRegistry.generate(
                        name: "problem_solving",
                        arguments: ["problem": "Test problem \(requestNum)"]
                    )
                    
                case 3:
                    // Analytics
                    _ = try await server.toolRegistry.execute(
                        name: "analytics",
                        arguments: [
                            "action": "track",
                            "event": "client_\(id)_event_\(requestNum)"
                        ]
                    )
                    
                default:
                    // Complex workflow
                    _ = try await server.executeComplexWorkflow(userId: "client-\(id)")
                }
            } catch {
                // Log error but continue
                print("Client \(id) request \(requestNum) failed: \(error)")
                return false
            }
        }
        
        return true
    }
}

// MARK: - Usage Example

func demonstrateConcurrentOperations() async throws {
    print("=== Concurrent Operations Demo ===\n")
    
    // 1. Basic concurrent server operations
    let server = ConcurrentMCPServer()
    print("1. Handling concurrent requests...")
    try await server.handleConcurrentRequests()
    print("   ✓ Concurrent requests completed\n")
    
    // 2. Complex orchestrated workflow
    print("2. Executing complex workflow...")
    let workflowResult = try await server.executeComplexWorkflow(userId: "demo-user")
    print("   ✓ Workflow completed: \(workflowResult["workflow_id"] ?? "unknown")\n")
    
    // 3. Stress test
    print("3. Running stress test...")
    let stressTest = StressTestRunner()
    try await stressTest.runStressTest(clients: 10, requestsPerClient: 5)
    print("   ✓ Stress test completed\n")
}

// MARK: - Best Practices Summary

/*
 Concurrent Operations Best Practices:
 
 1. **Controlled concurrency**: Use TaskGroup with limits to prevent resource exhaustion.
 
 2. **Operation tracking**: Track operation status and results for debugging and monitoring.
 
 3. **Rate limiting**: Implement rate limiting to prevent overwhelming downstream services.
 
 4. **Error isolation**: Handle errors gracefully without affecting other concurrent operations.
 
 5. **Resource pooling**: Use connection/resource pools for efficient resource utilization.
 
 6. **Timeout management**: Set appropriate timeouts for all async operations.
 
 7. **Backpressure handling**: Implement backpressure mechanisms when queues build up.
 
 8. **Monitoring and metrics**: Track performance metrics for optimization.
 
 9. **Graceful degradation**: Design systems to degrade gracefully under load.
 
 10. **Testing under load**: Always test concurrent systems under realistic load conditions.
 */
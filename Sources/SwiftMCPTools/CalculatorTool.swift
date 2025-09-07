//
//  CalculatorTool.swift
//  SwiftMCPTools
//
//  Basic calculator tool
//

import Foundation
import SwiftMCP

public struct CalculatorTool: MCPToolExecutor {
    public let definition: MCPTool
    
    public init() {
        self.definition = MCPTool(
            name: "calculator",
            title: "Calculator",
            description: "Perform basic arithmetic operations",
            inputSchema: [
                "type": "object",
                "properties": [
                    "operation": [
                        "type": "string",
                        "enum": ["add", "subtract", "multiply", "divide"],
                        "description": "The arithmetic operation to perform"
                    ],
                    "a": [
                        "type": "number",
                        "description": "First operand"
                    ],
                    "b": [
                        "type": "number",
                        "description": "Second operand"
                    ]
                ],
                "required": ["operation", "a", "b"]
            ],
            outputSchema: [
                "type": "object",
                "properties": [
                    "result": [
                        "type": "number",
                        "description": "The result of the calculation"
                    ]
                ],
                "required": ["result"]
            ]
        )
    }
    
    public func execute(arguments: [String: Any]?) async throws -> MCPToolResult {
        guard let args = arguments,
              let operation = args["operation"] as? String,
              let a = args["a"] as? Double,
              let b = args["b"] as? Double else {
            throw JSONRPCError.invalidParams(data: AnyCodable("Missing required parameters"))
        }
        
        let result: Double
        
        switch operation {
        case "add":
            result = a + b
        case "subtract":
            result = a - b
        case "multiply":
            result = a * b
        case "divide":
            guard b != 0 else {
                return MCPToolResult.error("Error: Division by zero")
            }
            result = a / b
        default:
            throw JSONRPCError.invalidParams(data: AnyCodable("Unknown operation: \(operation)"))
        }
        
        let structuredResult = ["result": result]
        let textResult = "\(a) \(operation) \(b) = \(result)"
        
        return MCPToolResult(
            content: [.text(MCPTextContent(text: textResult))],
            structuredContent: AnyCodable(structuredResult),
            isError: false
        )
    }
}
//
//  AsyncPromptExample.swift
//  SwiftMCP Examples
//
//  Demonstrates implementing MCPPromptProvider with async operations and external data sources
//  Shows how to generate dynamic prompts based on real-time data
//

import Foundation
import SwiftMCP

// MARK: - Knowledge Base Manager

/// KnowledgeBase manages a searchable knowledge base for prompt generation
actor KnowledgeBase {
    struct Article {
        let id: String
        let title: String
        let content: String
        let category: String
        let tags: [String]
        let lastUpdated: Date
        let relevanceScore: Double
    }
    
    private var articles: [Article] = []
    private var indexedTerms: [String: Set<String>] = [:] // term -> article IDs
    
    init() {
        // Initialize with sample data
        loadSampleArticles()
    }
    
    private func loadSampleArticles() {
        articles = [
            Article(
                id: "swift-concurrency",
                title: "Swift Concurrency Guide",
                content: "Swift's modern concurrency features including async/await, actors, and structured concurrency provide powerful tools for writing safe concurrent code.",
                category: "Programming",
                tags: ["swift", "concurrency", "async", "actors"],
                lastUpdated: Date(),
                relevanceScore: 0.95
            ),
            Article(
                id: "mcp-protocol",
                title: "Model Context Protocol Overview",
                content: "The Model Context Protocol (MCP) enables AI assistants to interact with external systems through a standardized interface for tools, resources, and prompts.",
                category: "AI",
                tags: ["mcp", "ai", "protocol", "integration"],
                lastUpdated: Date(),
                relevanceScore: 0.90
            ),
            Article(
                id: "best-practices",
                title: "Software Engineering Best Practices",
                content: "Following established best practices including SOLID principles, clean code, and test-driven development leads to maintainable software.",
                category: "Engineering",
                tags: ["best-practices", "solid", "tdd", "clean-code"],
                lastUpdated: Date(),
                relevanceScore: 0.85
            )
        ]
        
        // Build search index
        for article in articles {
            let terms = extractTerms(from: article)
            for term in terms {
                indexedTerms[term.lowercased(), default: []].insert(article.id)
            }
        }
    }
    
    private func extractTerms(from article: Article) -> Set<String> {
        let text = "\(article.title) \(article.content) \(article.tags.joined(separator: " "))"
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { $0.count > 2 }
        return Set(words)
    }
    
    func search(query: String, limit: Int = 3) async -> [Article] {
        // Simulate async search operation
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let queryTerms = query.lowercased().components(separatedBy: .whitespaces)
        var relevantArticleIds = Set<String>()
        
        for term in queryTerms {
            if let articleIds = indexedTerms[term] {
                relevantArticleIds.formUnion(articleIds)
            }
        }
        
        let relevantArticles = articles.filter { relevantArticleIds.contains($0.id) }
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(limit)
        
        return Array(relevantArticles)
    }
    
    func getArticle(id: String) async -> Article? {
        articles.first { $0.id == id }
    }
    
    func getRelatedArticles(to articleId: String, limit: Int = 2) async -> [Article] {
        guard let article = articles.first(where: { $0.id == articleId }) else {
            return []
        }
        
        // Find articles with overlapping tags
        let relatedArticles = articles
            .filter { $0.id != articleId }
            .map { otherArticle in
                let commonTags = Set(article.tags).intersection(Set(otherArticle.tags))
                return (article: otherArticle, score: Double(commonTags.count))
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.article }
        
        return Array(relatedArticles)
    }
}

// MARK: - External API Client

/// ExternalAPIClient simulates fetching data from external sources
actor ExternalAPIClient {
    struct UserContext {
        let userId: String
        let preferences: [String: String]
        let history: [String]
        let expertise: String
    }
    
    struct ProjectInfo {
        let name: String
        let description: String
        let technologies: [String]
        let currentPhase: String
    }
    
    func fetchUserContext(userId: String) async throws -> UserContext {
        // Simulate API call
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        return UserContext(
            userId: userId,
            preferences: [
                "language": "Swift",
                "style": "detailed",
                "format": "markdown"
            ],
            history: ["swift-concurrency", "mcp-protocol"],
            expertise: "intermediate"
        )
    }
    
    func fetchProjectInfo(projectId: String) async throws -> ProjectInfo {
        // Simulate API call
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        return ProjectInfo(
            name: "SwiftMCP",
            description: "A Swift implementation of the Model Context Protocol",
            technologies: ["Swift", "Concurrency", "JSON-RPC"],
            currentPhase: "development"
        )
    }
    
    func fetchRecentActivity(limit: Int = 5) async throws -> [String] {
        // Simulate API call
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        return [
            "Implemented actor-based tool executor",
            "Fixed concurrency issues in protocol methods",
            "Added comprehensive test coverage",
            "Created example implementations",
            "Updated documentation"
        ]
    }
}

// MARK: - Intelligent Prompt Providers

/// CodeReviewPrompt generates context-aware code review prompts
struct CodeReviewPrompt: MCPPromptProvider {
    let definition = MCPPrompt(
        name: "code_review",
        title: "Intelligent Code Review",
        description: "Generates comprehensive code review prompts with context",
        arguments: [
            MCPPromptArgument(name: "code", description: "Code to review", required: true),
            MCPPromptArgument(name: "language", description: "Programming language", required: false),
            MCPPromptArgument(name: "focus", description: "Review focus areas", required: false),
            MCPPromptArgument(name: "user_id", description: "User ID for personalization", required: false)
        ]
    )
    
    private let knowledgeBase = KnowledgeBase()
    private let apiClient = ExternalAPIClient()
    
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        guard let code = arguments?["code"] else {
            throw PromptError.missingRequiredArgument("code")
        }
        
        let language = arguments?["language"] ?? "Swift"
        let focus = arguments?["focus"] ?? "general"
        let userId = arguments?["user_id"]
        
        // Fetch context in parallel
        async let bestPractices = knowledgeBase.search(query: "\(language) best practices", limit: 2)
        async let userContext = userId.map { apiClient.fetchUserContext(userId: $0) }
        
        // Wait for all data
        let practices = await bestPractices
        let context = try? await userContext
        
        // Build comprehensive prompt
        var messages: [MCPPromptMessage] = []
        
        // System message with context
        var systemPrompt = "You are an expert \(language) code reviewer with deep knowledge of best practices, "
        systemPrompt += "design patterns, and performance optimization. "
        
        if let expertise = context?.expertise {
            systemPrompt += "The user has \(expertise) level expertise. "
        }
        
        if !practices.isEmpty {
            systemPrompt += "Consider these best practices: "
            systemPrompt += practices.map { $0.title }.joined(separator: ", ")
            systemPrompt += ". "
        }
        
        messages.append(.system(systemPrompt))
        
        // Add relevant knowledge base content
        for article in practices {
            messages.append(.system("Reference: \(article.title) - \(article.content)"))
        }
        
        // User message with the code
        var userPrompt = "Please review the following \(language) code"
        
        if focus != "general" {
            userPrompt += " with special attention to \(focus)"
        }
        
        userPrompt += ":\n\n```\(language.lowercased())\n\(code)\n```\n\n"
        userPrompt += "Provide specific, actionable feedback on:\n"
        userPrompt += "1. Code quality and readability\n"
        userPrompt += "2. Potential bugs or issues\n"
        userPrompt += "3. Performance considerations\n"
        userPrompt += "4. Best practices and design patterns\n"
        userPrompt += "5. Suggestions for improvement"
        
        messages.append(.user(userPrompt))
        
        return messages
    }
}

/// DocumentationPrompt generates documentation with project context
struct DocumentationPrompt: MCPPromptProvider {
    let definition = MCPPrompt(
        name: "documentation",
        title: "Smart Documentation Generator",
        description: "Generates documentation with project and user context",
        arguments: [
            MCPPromptArgument(name: "code", description: "Code to document", required: true),
            MCPPromptArgument(name: "type", description: "Documentation type (api, tutorial, readme)", required: false),
            MCPPromptArgument(name: "project_id", description: "Project ID for context", required: false)
        ]
    )
    
    private let knowledgeBase = KnowledgeBase()
    private let apiClient = ExternalAPIClient()
    
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        guard let code = arguments?["code"] else {
            throw PromptError.missingRequiredArgument("code")
        }
        
        let docType = arguments?["type"] ?? "api"
        let projectId = arguments?["project_id"]
        
        // Fetch project context
        let projectInfo = projectId != nil
            ? try? await apiClient.fetchProjectInfo(projectId: projectId!)
            : nil
        
        // Search for documentation best practices
        let docPractices = await knowledgeBase.search(
            query: "documentation \(docType) best practices",
            limit: 2
        )
        
        var messages: [MCPPromptMessage] = []
        
        // System message
        var systemPrompt = "You are a technical documentation expert. "
        
        if let project = projectInfo {
            systemPrompt += "You're documenting code for \(project.name): \(project.description). "
            systemPrompt += "The project uses: \(project.technologies.joined(separator: ", ")). "
        }
        
        messages.append(.system(systemPrompt))
        
        // Add documentation guidelines
        if !docPractices.isEmpty {
            let guidelines = docPractices.map { "- \($0.title): \($0.content)" }.joined(separator: "\n")
            messages.append(.system("Documentation guidelines:\n\(guidelines)"))
        }
        
        // User message
        let userPrompt = buildDocumentationPrompt(for: code, type: docType, project: projectInfo)
        messages.append(.user(userPrompt))
        
        return messages
    }
    
    private func buildDocumentationPrompt(
        for code: String,
        type: String,
        project: ExternalAPIClient.ProjectInfo?
    ) -> String {
        switch type {
        case "api":
            return """
            Generate comprehensive API documentation for the following code:
            
            ```swift
            \(code)
            ```
            
            Include:
            - Purpose and overview
            - Parameters with descriptions
            - Return values
            - Throws documentation
            - Usage examples
            - Related APIs
            """
            
        case "tutorial":
            return """
            Create a step-by-step tutorial for using the following code:
            
            ```swift
            \(code)
            ```
            
            Include:
            - Introduction and prerequisites
            - Step-by-step instructions
            - Code examples for each step
            - Common use cases
            - Troubleshooting tips
            """
            
        case "readme":
            return """
            Generate a README section for the following code:
            
            ```swift
            \(code)
            ```
            
            Include:
            - Feature overview
            - Installation/setup
            - Quick start example
            - Configuration options
            - API reference links
            """
            
        default:
            return "Document the following code:\n\n```swift\n\(code)\n```"
        }
    }
}

/// ProblemSolvingPrompt generates problem-solving prompts with historical context
struct ProblemSolvingPrompt: MCPPromptProvider {
    let definition = MCPPrompt(
        name: "problem_solving",
        title: "Contextual Problem Solver",
        description: "Generates problem-solving prompts with relevant context",
        arguments: [
            MCPPromptArgument(name: "problem", description: "Problem description", required: true),
            MCPPromptArgument(name: "constraints", description: "Constraints or requirements", required: false),
            MCPPromptArgument(name: "context", description: "Additional context", required: false)
        ]
    )
    
    private let knowledgeBase = KnowledgeBase()
    private let apiClient = ExternalAPIClient()
    
    nonisolated func generate(arguments: [String: String]?) async throws -> [MCPPromptMessage] {
        guard let problem = arguments?["problem"] else {
            throw PromptError.missingRequiredArgument("problem")
        }
        
        let constraints = arguments?["constraints"]
        let context = arguments?["context"]
        
        // Search for related solutions and recent activity
        async let relatedArticles = knowledgeBase.search(query: problem, limit: 3)
        async let recentActivity = apiClient.fetchRecentActivity(limit: 3)
        
        let articles = await relatedArticles
        let activities = (try? await recentActivity) ?? []
        
        var messages: [MCPPromptMessage] = []
        
        // System message
        messages.append(.system("""
            You are a senior software engineer and problem-solving expert. \
            Approach problems systematically, considering multiple solutions \
            and trade-offs. Provide practical, implementable solutions.
            """))
        
        // Add relevant knowledge
        if !articles.isEmpty {
            let knowledge = articles.map { article in
                "[\(article.category)] \(article.title): \(article.content)"
            }.joined(separator: "\n\n")
            
            messages.append(.system("Relevant knowledge base entries:\n\(knowledge)"))
        }
        
        // Add recent context
        if !activities.isEmpty {
            messages.append(.system("Recent project activities:\n" + activities.joined(separator: "\n")))
        }
        
        // User message
        var userPrompt = "Problem: \(problem)\n\n"
        
        if let constraints = constraints {
            userPrompt += "Constraints: \(constraints)\n\n"
        }
        
        if let context = context {
            userPrompt += "Additional Context: \(context)\n\n"
        }
        
        userPrompt += """
        Please provide:
        1. Analysis of the problem
        2. Multiple solution approaches
        3. Recommended solution with justification
        4. Implementation steps
        5. Potential pitfalls and how to avoid them
        """
        
        messages.append(.user(userPrompt))
        
        return messages
    }
}

// MARK: - Error Types

enum PromptError: Error, LocalizedError {
    case missingRequiredArgument(String)
    case invalidArgument(String, String)
    case externalAPIError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredArgument(let arg):
            return "Missing required argument: \(arg)"
        case .invalidArgument(let arg, let reason):
            return "Invalid argument '\(arg)': \(reason)"
        case .externalAPIError(let message):
            return "External API error: \(message)"
        }
    }
}

// MARK: - Usage Example

func demonstrateAsyncPrompts() async throws {
    let registry = MCPPromptRegistry()
    
    // Register intelligent prompts
    await registry.register(CodeReviewPrompt())
    await registry.register(DocumentationPrompt())
    await registry.register(ProblemSolvingPrompt())
    
    // Generate code review prompt with full context
    let codeReviewMessages = try await registry.generate(
        name: "code_review",
        arguments: [
            "code": """
            actor DataCache {
                private var cache: [String: Data] = [:]
                
                func get(_ key: String) -> Data? {
                    cache[key]
                }
                
                func set(_ key: String, value: Data) {
                    cache[key] = value
                }
            }
            """,
            "language": "Swift",
            "focus": "concurrency and thread safety",
            "user_id": "user123"
        ]
    )
    
    print("Code Review Prompt:")
    for message in codeReviewMessages {
        print("[\(message.role)]: \(message.content)")
    }
    
    // Generate documentation prompt
    let docMessages = try await registry.generate(
        name: "documentation",
        arguments: [
            "code": "public protocol MCPToolExecutor: Sendable { ... }",
            "type": "api",
            "project_id": "swiftmcp"
        ]
    )
    
    print("\nDocumentation Prompt:")
    print("Generated \(docMessages.count) messages")
    
    // Generate problem-solving prompt
    let problemMessages = try await registry.generate(
        name: "problem_solving",
        arguments: [
            "problem": "How to handle concurrent access to shared resources in Swift",
            "constraints": "Must work with Swift 6 strict concurrency",
            "context": "Building an MCP server with multiple clients"
        ]
    )
    
    print("\nProblem Solving Prompt:")
    print("Generated \(problemMessages.count) messages with context")
}

// MARK: - Best Practices Summary

/*
 Async Prompt Generation Best Practices:
 
 1. **Nonisolated protocol methods**: Always mark generate() as nonisolated.
 
 2. **Parallel data fetching**: Use async let to fetch multiple data sources concurrently.
 
 3. **Error handling**: Throw descriptive errors for missing or invalid arguments.
 
 4. **Context enrichment**: Fetch relevant context from knowledge bases and APIs.
 
 5. **Caching**: Consider caching frequently accessed data to improve response times.
 
 6. **Timeout handling**: Implement timeouts for external API calls.
 
 7. **Graceful degradation**: Provide useful prompts even if some context fetching fails.
 
 8. **Structured prompts**: Build clear, structured prompts with specific instructions.
 
 9. **Personalization**: Use user context to tailor prompt generation.
 
 10. **Performance**: Balance context richness with response time requirements.
 */
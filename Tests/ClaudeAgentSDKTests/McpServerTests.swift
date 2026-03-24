import Testing
import Foundation
@testable import ClaudeAgentSDK

@Suite("MCP SDK Server")
struct McpServerTests {

    @Test("tool() builder creates definition")
    func toolBuilder() {
        let t = tool("greet", description: "Say hello", inputSchema: [
            "type": "object",
            "properties": [
                "name": ["type": "string"]
            ]
        ]) { input in
            let name = input["name"]?.stringValue ?? "world"
            return .text("Hello, \(name)!")
        }

        #expect(t.name == "greet")
        #expect(t.description == "Say hello")
        #expect(t.inputSchema["type"]?.stringValue == "object")
    }

    @Test("SdkMcpServer callTool dispatches correctly")
    func callToolDispatches() async throws {
        let server = createSdkMcpServer(
            name: "test-server",
            tools: [
                tool("add", description: "Add two numbers", inputSchema: [:]) { input in
                    let a = input["a"]?.intValue ?? 0
                    let b = input["b"]?.intValue ?? 0
                    return .text("\(a + b)")
                }
            ]
        )

        let result = try await server.callTool(name: "add", input: ["a": 3, "b": 4])
        let text = result.content.first?["text"]?.stringValue
        #expect(text == "7")
    }

    @Test("SdkMcpServer throws for unknown tool")
    func unknownToolThrows() async {
        let server = createSdkMcpServer(name: "test", tools: [])

        do {
            _ = try await server.callTool(name: "nonexistent", input: [:])
            Issue.record("Expected error")
        } catch {
            #expect("\(error)".contains("Unknown MCP tool"))
        }
    }

    @Test("SdkMcpServer listTools returns schemas")
    func listToolsReturnsSchemas() async {
        let server = createSdkMcpServer(
            name: "test",
            tools: [
                tool("foo", description: "Do foo", inputSchema: ["type": "object"]) { _ in .text("ok") },
                tool("bar", description: "Do bar", inputSchema: ["type": "object"]) { _ in .text("ok") },
            ]
        )

        let tools = await server.listTools()
        #expect(tools.count == 2)
        let names = Set(tools.compactMap { $0["name"]?.stringValue })
        #expect(names.contains("foo"))
        #expect(names.contains("bar"))
    }

    @Test("SdkMcpToolResult convenience initializers")
    func toolResultConvenience() {
        let textResult = SdkMcpToolResult.text("hello")
        #expect(textResult.isError == nil)
        #expect(textResult.content.first?["text"]?.stringValue == "hello")

        let errorResult = SdkMcpToolResult.error("something broke")
        #expect(errorResult.isError == true)
        #expect(errorResult.content.first?["text"]?.stringValue == "something broke")
    }

    @Test("McpServerConfig decodes sdk type")
    func mcpConfigSdkType() throws {
        let json = """
        {"type":"sdk","name":"my-server"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let config = try decoder.decode(McpServerConfig.self, from: Data(json.utf8))
        guard case let .sdk(sdkConfig) = config else {
            Issue.record("Expected sdk config")
            return
        }
        #expect(sdkConfig.name == "my-server")
    }
}

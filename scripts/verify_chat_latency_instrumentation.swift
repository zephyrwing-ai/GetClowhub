import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fatalError(message)
    }
}

let dashboard = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let gateway = read("OpenClawInstaller/Services/GatewayClient.swift")

require(
    dashboard.contains("let chatSendStart = ContinuousClock.now"),
    "sendChatMessage should record the local send start time"
)
require(
    dashboard.contains(#"phase=chat_send_start"#),
    "sendChatMessage should log chat_send_start"
)
require(
    dashboard.contains(#"phase=chat_send_ack"#),
    "sendChatMessage should log chat_send_ack after runId is received"
)
require(
    dashboard.contains(#"phase=chat_first_event"#),
    "sendChatMessage should log the first gateway event after ack"
)
require(
    dashboard.contains(#"phase=chat_first_delta"#),
    "sendChatMessage should log the first text delta"
)
require(
    dashboard.contains(#"phase=chat_final"#),
    "sendChatMessage should log final event timing"
)
require(
    dashboard.contains(#"phase=chat_error"#),
    "sendChatMessage should log error event timing"
)
require(
    gateway.contains("pendingChatSendStartedAt"),
    "GatewayClient should track chat.send request start times"
)
require(
    gateway.contains(#"phase=chat_send_ws_send"#),
    "GatewayClient should log when the WebSocket send callback succeeds"
)
require(
    gateway.contains(#"phase=chat_send_ack"#),
    "GatewayClient should log when the gateway ack returns a runId"
)
require(
    gateway.contains(#"phase=chat_send_ack_timeout"#),
    "GatewayClient should log chat.send ack timeout"
)

print("Chat latency instrumentation checks passed")

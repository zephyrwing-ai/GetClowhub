#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let gateway = try read("OpenClawInstaller/Services/GatewayClient.swift")
let viewModel = try read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")

require(gateway.contains("\"caps\": [\"tool-events\"]"), "macOS gateway connect should subscribe to structured tool events")
require(gateway.contains("case activity(runId: String, sessionKey: String?, event: GatewayActivityEvent)"), "gateway chat events should include structured activity")
require(gateway.contains("handleAgentEventPayload"), "gateway should handle agent events, not only chat text events")
require(gateway.contains("stream == \"tool\""), "gateway should parse tool stream events")
require(gateway.contains("data[\"args\"] as? [String: Any]"), "gateway tool activity parser should read tool start args")
require(gateway.contains("case agentUsed"), "gateway activity events should include structured agent usage")
require(gateway.contains("case agentRecruited"), "gateway activity events should include structured agent recruitment")
require(gateway.contains("parseAgentActivity"), "gateway should parse structured agent/recruit events without reading assistant prose")
require(gateway.contains("delete data.result") == false, "macOS client should not depend on full tool result payloads")

require(viewModel.contains("case .activity(let eventRunId, _, let event):"), "dashboard stream loop should handle activity events")
require(viewModel.contains("mergeActivityEvent(event, into: &accumulatedActivityEvents)"), "activity events should merge into accumulated activities")
require(viewModel.contains("case agentUsed"), "chat activity model should represent structured agent usage")
require(viewModel.contains("case agentRecruited"), "chat activity model should represent structured agent recruitment")
require(viewModel.contains("Used \\(count) \\(count == 1 ? \"agent\" : \"agents\")"), "working summary should describe used agents")
require(viewModel.contains("Recruited \\(count) \\(count == 1 ? \"agent\" : \"agents\")"), "working summary should describe recruited agents")
require(!viewModel.contains("ChatActivityExtractor.extract(from: accumulatedText)"), "activity should not be extracted from assistant text deltas")
require(!viewModel.contains("ChatActivityExtractor.extract(from: finalText)"), "activity should not be extracted from final assistant text")
require(!viewModel.contains("enum ChatActivityExtractor"), "hard-coded assistant-text activity extractor should be removed")

print("PASS: structured chat activity event contracts verified")

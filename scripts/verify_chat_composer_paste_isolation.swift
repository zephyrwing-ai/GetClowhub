#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let composerURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChatComposerView.swift")
let timelineURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChatTimelineSurface.swift")

guard let source = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
}

func readRequiredFile(_ url: URL, _ name: String) -> String {
    guard FileManager.default.fileExists(atPath: url.path) else {
        fputs("FAIL: \(name) should exist.\n", stderr)
        exit(1)
    }
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(name)")
    }
    return contents
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let chatView = slice(
    source,
    from: "struct ChatView: View",
    to: "private struct ComposerInputCardBoundsKey"
)
let composerInputCardWrapper = slice(
    source,
    from: "private var composerInputCard: some View",
    to: "private var terminalPanel: some View"
)
let composerSource = readRequiredFile(composerURL, "ChatComposerView.swift")
let timelineSource = readRequiredFile(timelineURL, "ChatTimelineSurface.swift")

require(
    source.contains("ChatComposerView("),
    "DashboardView should compose ChatComposerView instead of keeping composer layout inline."
)
require(
    composerSource.contains("struct ChatComposerView: View"),
    "ChatComposerView.swift should declare ChatComposerView."
)
require(
    !composerSource.contains("Text(inputText.isEmpty ? \" \" : inputText)") &&
        !composerSource.contains("Text(inputText"),
    "Composer should not use hidden Text(inputText) to measure pasted content."
)
require(
    composerSource.contains("let composerEditorHeight: CGFloat") ||
        chatView.contains("private let composerEditorHeight"),
    "Composer should use an explicit editor height to isolate paste layout cost."
)
require(
    composerSource.contains(".frame(height: composerEditorHeight)") ||
        composerSource.contains(".frame(height: Self.composerEditorHeight)"),
    "TextEditor should be constrained to a stable height so long paste scrolls internally."
)
require(
    !composerSource.contains(".fixedSize(horizontal: false, vertical: true)"),
    "Composer text editor container should not vertically resize from pasted text."
)
require(
    composerInputCardWrapper.contains("ChatComposerView(") &&
        !composerInputCardWrapper.contains("TextEditor(text:"),
    "Dashboard composerInputCard should be a thin wrapper around ChatComposerView."
)
require(
    timelineSource.contains("struct ChatTimelineSurface: View"),
    "ChatTimelineSurface.swift should declare ChatTimelineSurface."
)
require(
    !source.contains("private struct ChatTimelineSurface: View"),
    "DashboardView.swift should not keep ChatTimelineSurface inline."
)
require(
    source.contains("ChatTimelineSurface(") &&
        source.contains("messages: viewModel.chatMessages"),
    "ChatView should pass messages into ChatTimelineSurface instead of mixing timeline layout with composer input state."
)
require(
    !timelineSource.contains("inputText") &&
        !timelineSource.contains("showSlashPanel") &&
        !timelineSource.contains("showSkillsPanel") &&
        !timelineSource.contains("showAgentPanel"),
    "ChatTimelineSurface should not depend on composer input or suggestion state."
)

print("Chat composer paste isolation verification passed")

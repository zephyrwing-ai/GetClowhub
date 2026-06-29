#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")

guard let source = try? String(contentsOf: dashboardPath, encoding: .utf8) else {
    fputs("FAIL: could not read \(dashboardPath.path)\n", stderr)
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice DashboardView.swift between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let chatView = slice(
    from: "struct ChatView: View",
    to: "private struct ComposerInputCardBoundsKey"
)

require(
    !source.contains("ChatScrollContentMetricsKey") &&
        !source.contains("ChatScrollViewportHeightKey"),
    "Chat scroll should not publish continuous geometry preference metrics."
)
require(
    !chatView.contains("chatScrollOffset") &&
        !chatView.contains("chatScrollViewportHeight") &&
        !chatView.contains("chatScrollContentHeight"),
    "ChatView should not retain scroll geometry state."
)
require(
    !chatView.contains("updateChatScrollMetricsIfNeeded") &&
        !chatView.contains("updateChatScrollViewportHeightIfNeeded"),
    "ChatView should not write geometry metrics back into @State."
)
require(
    !chatView.contains("showTransientChatScrollIndicator()"),
    "Scroll wheel handling should not drive a custom chat indicator when native indicators are enabled."
)
require(
    !chatView.contains("private var chatScrollIndicator: some View") &&
        !chatView.contains("chatScrollIndicatorHideTask") &&
        chatView.contains("ChatScrollIntentObserver("),
    "ChatView should remove the custom indicator while keeping bottom reattachment observation."
)

print("Native chat scrollbar guard verification passed")

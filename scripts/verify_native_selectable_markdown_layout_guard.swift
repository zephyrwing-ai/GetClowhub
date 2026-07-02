#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    source.contains("textView.textContainer?.widthTracksTextView = false"),
    "Native selectable text view should own textContainer width updates instead of also letting AppKit track width."
)

require(
    source.contains("@discardableResult\n        func updateContainerWidth(_ width: CGFloat) -> Bool"),
    "Container width updates should return whether they invalidated intrinsic height."
)

require(
    source.contains("func refreshMeasuredHeightAfterContentChange()"),
    "Content updates should refresh measured height instead of always invalidating intrinsic size."
)

require(
    source.contains("guard width > 1 else {\n                return NSSize(width: NSView.noIntrinsicMetric, height: max(22, cachedIntrinsicHeight ?? 22))"),
    "Intrinsic height should not be measured against the initial 1px fallback width."
)

require(
    source.contains("private func measureHeight(for textContainer: NSTextContainer) -> CGFloat"),
    "Height measurement should be centralized so width and content updates share the same guard."
)

require(
    source.contains("let heightChanged = previousHeight.map { abs($0 - measuredHeight) > Self.layoutEpsilon } ?? true")
        && source.contains("if heightChanged {\n                invalidateIntrinsicContentSize()"),
    "Intrinsic invalidation should only happen when measured height meaningfully changes."
)

require(
    source.contains("NSMutableAttributedString(string: markdown)"),
    "Plain text rendering should avoid constructing a Markdown AttributedString."
)

print("OK: native selectable markdown layout guard is present")

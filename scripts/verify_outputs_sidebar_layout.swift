import CoreGraphics

@main
struct VerifyOutputsSidebarLayout {
    static func main() {
        let metrics = OutputsSidebarLayoutMetrics()

        assertEqual(
            metrics.collapsedWidth,
            0,
            "closed sidebar reserves no trailing strip width"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: false, hasEditor: false, availableWidth: 1200),
            0,
            "closed sidebar reserves no trailing strip width"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: true, hasEditor: false, availableWidth: 1200),
            metrics.browserWidth,
            "expanded sidebar shows the workspace browser width"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: true, hasEditor: true, availableWidth: 1600),
            metrics.browserWidth + metrics.editorWidth,
            "expanded sidebar includes editor width when a file is open"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: true, hasEditor: false, availableWidth: 760),
            0,
            "narrow windows close Outputs without leaving a trailing strip"
        )
        assertEqual(
            metrics.chatColumnWidth(for: 1400),
            metrics.chatColumnMaxWidth,
            "wide chat stages keep a stable maximum column width"
        )
        assertEqual(
            metrics.chatColumnWidth(for: 600),
            600,
            "narrow chat stages use the available width"
        )

        print("OutputsSidebarLayoutMetrics verification passed")
    }

    private static func assertEqual(
        _ actual: CGFloat,
        _ expected: CGFloat,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard abs(actual - expected) < 0.001 else {
            fatalError("\(message): expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}

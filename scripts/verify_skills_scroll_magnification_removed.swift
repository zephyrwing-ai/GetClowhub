#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let skillsViewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabView.swift")
let skillsView = try String(contentsOf: skillsViewPath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let catalogRow = slice(
    skillsView,
    from: "private struct CatalogSkillListRow: View",
    to: "private struct InstalledSkillListRow: View"
)
let installedRow = slice(
    skillsView,
    from: "private struct InstalledSkillListRow: View",
    to: "private struct InstalledStatusMark: View"
)

require(!skillsView.contains("skillPointerLocation"), "Skills tab should not store continuous pointer location state.")
require(!skillsView.contains(".onContinuousHover"), "Skills tab should not write state on every pointer movement.")
require(!skillsView.contains("SkillDockMagnification"), "Skills tab should not compute Dock-style row magnification.")
require(!skillsView.contains("SkillRowFramePreferenceKey"), "Skills tab should not measure every row frame for hover scaling.")
require(!skillsView.contains("SkillMagnifiedRow"), "Skills rows should not be wrapped in a magnification view.")
require(!skillsView.contains(".scaleEffect(rowScale"), "Skills rows should not scale during scroll/hover.")

require(catalogRow.contains("@State private var isHovered"), "Catalog skill rows should keep lightweight hover state.")
require(!catalogRow.contains("withAnimation(.easeInOut(duration: 0.18))"), "Catalog skill row hover should not animate during scrolling.")
require(!catalogRow.contains("pointerLocation"), "Catalog skill rows should not receive pointer location.")

require(installedRow.contains("@State private var isHovered"), "Installed skill rows should keep lightweight hover state.")
require(!installedRow.contains("withAnimation(.easeInOut(duration: 0.18))"), "Installed skill row hover should not animate during scrolling.")
require(!installedRow.contains("pointerLocation"), "Installed skill rows should not receive pointer location.")

require(skillsView.contains("Markdown(detailMarkdown)") && skillsView.contains(".textSelection(.enabled)"),
        "Skill detail Markdown should remain selectable for copying.")

print("Skills scroll magnification removal verification passed")

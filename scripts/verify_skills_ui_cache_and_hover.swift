#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let viewModelPath = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let skillsViewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/SkillsTabView.swift")

let viewModel = try String(contentsOf: viewModelPath, encoding: .utf8)
let skillsView = try String(contentsOf: skillsViewPath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    viewModel.contains("private var hasLoadedSkillCatalog = false"),
    "Skill catalog should remember when the catalog is already loaded."
)
require(
    viewModel.contains("func loadSkillMarket(forceSync: Bool = false) async"),
    "loadSkillMarket should expose an explicit forceSync flag."
)
require(
    viewModel.contains("if hasLoadedSkillCatalog && !forceSync"),
    "Skill market should reuse the loaded catalog unless refresh is explicit."
)
require(
    viewModel.contains("let shouldSync = forceSync || !FileManager.default.fileExists"),
    "Skill market should sync only for forced refresh or a missing cache."
)
require(
    skillsView.contains("loadSkillMarket(forceSync: true)"),
    "Refresh action should force catalog sync."
)
require(
    skillsView.contains("withAnimation(.easeInOut(duration: 0.18))"),
    "Skill row hover state should animate."
)
require(
    skillsView.contains(".animation(.easeInOut(duration: 0.18), value: isHovered)"),
    "Skill row hover background should fade instead of switching instantly."
)
require(
    !skillsView.contains("ProgressView()"),
    "Skills UI should use quiet text/icon states instead of spinner progress views."
)
require(
    skillsView.contains("Markdown(detailMarkdown)"),
    "Skill detail should render the SKILL.md body as Markdown."
)
require(
    skillsView.contains(".transition(.asymmetric("),
    "Skill detail sheet should animate in and out instead of appearing abruptly."
)
require(
    skillsView.contains("private var detailMarkdown: String"),
    "Skill detail should trim the repeated leading title from the Markdown body."
)
require(
    skillsView.contains(".frame(height: 344)"),
    "Skill detail Markdown should live in a fixed-height scroll box."
)
require(
    skillsView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)"),
    "Skill detail overlay should fill the available page and center the narrower sheet."
)
require(
    skillsView.contains(".frame(width: 640)"),
    "Skill detail sheet should be narrower than the 760px skill list column."
)

print("OK: skills UI cache and hover policy verified")

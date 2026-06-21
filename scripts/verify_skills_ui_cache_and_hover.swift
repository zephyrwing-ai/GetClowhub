#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let viewModelPath = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let skillCatalogItemPath = root.appendingPathComponent("OpenClawInstaller/Models/SkillCatalogItem.swift")
let skillsViewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/SkillsTabView.swift")
let dashboardViewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let skillCatalogServicePath = root.appendingPathComponent("OpenClawInstaller/Services/SkillCatalogService.swift")

let viewModel = try String(contentsOf: viewModelPath, encoding: .utf8)
let skillCatalogItem = try String(contentsOf: skillCatalogItemPath, encoding: .utf8)
let skillsView = try String(contentsOf: skillsViewPath, encoding: .utf8)
let dashboardView = try String(contentsOf: dashboardViewPath, encoding: .utf8)
let skillCatalogService = try String(contentsOf: skillCatalogServicePath, encoding: .utf8)

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
let detailSheet = slice(
    skillsView,
    from: "struct SkillCatalogDetailSheet: View",
    to: "private struct SkillDetailChip: View"
)

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
    skillCatalogItem.contains("let isRecommended: Bool"),
    "Skill catalog items should carry a recommended flag from marketplace.json."
)
require(
    skillCatalogItem.contains("let tags: [String]") &&
        skillCatalogItem.contains("let sortOrder: Int"),
    "Skill catalog items should carry marketplace tags and ordering metadata."
)
require(
    !skillCatalogItem.contains("SkillCatalogCategory") &&
        !skillCatalogItem.contains("SkillLibrarySection") &&
        !skillCatalogItem.contains("builtIn") &&
        !skillCatalogItem.contains(#"Built-in"#),
    "Skill catalog should no longer expose built-in/library section enums; source classification is tag-driven."
)
require(
    skillCatalogService.contains("marketplace.json") &&
        skillCatalogService.contains("JSONDecoder()") &&
        skillCatalogService.contains("private struct SkillMarketplace") &&
        skillCatalogService.contains("private struct SkillMarketplaceEntry") &&
        skillCatalogService.contains("isRecommended: isRecommended"),
    "SkillCatalogService should parse recommended, tags, and order from marketplace.json."
)
require(
    !skillCatalogService.contains(#"frontmatter["recommended"]"#),
    "SkillCatalogService should not use SKILL.md frontmatter for recommendation state."
)
require(
    skillCatalogService.contains(#".appendingPathComponent("skills")"#) &&
        !skillCatalogService.contains(#".appendingPathComponent(SkillCatalogCategory.builtIn.rawValue)"#) &&
        !skillCatalogService.contains(#".appendingPathComponent("built-in")"#),
    "SkillCatalogService should scan direct skills/* directories instead of falling back to old category folders."
)
require(
    skillsView.contains("@State private var displayMode: SkillDisplayMode = .recommend") &&
        skillsView.contains(#"case recommend = "Recommend""#) &&
        skillsView.range(of: #"case recommend = "Recommend""#)!.lowerBound < skillsView.range(of: #"case all = "All""#)!.lowerBound,
    "Skills tab should default to Recommend and place it before All."
)
require(
    skillsView.contains("private var filteredRecommendedCatalogItems: [SkillCatalogItem]") &&
        skillsView.contains("filteredCatalogItems.filter(\\.isRecommended)") &&
        skillsView.contains("recommendedSkillsContent") &&
        skillsView.contains("case .recommend:"),
    "Skills tab should render a dedicated Recommend list from recommended catalog items."
)
require(
    skillsView.contains("item.tags") &&
        skillsView.contains("item.tags.joined"),
    "Skills tab search should include marketplace tags."
)
require(
    !skillsView.contains("InstalledSection") &&
        !skillsView.contains("installedSections") &&
        skillsView.contains(#"SkillSectionHeader(title: "Installed""#),
    "Installed skills should render as one list instead of preserving Catalog/Custom sub-sections."
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
    skillsView.contains("@State private var skillPointerLocation: CGPoint?"),
    "Skills UI should track the current pointer location for proximity-based row magnification."
)
require(
    skillsView.contains(".coordinateSpace(name: SkillDockMagnification.coordinateSpace)") &&
        skillsView.contains(".onContinuousHover"),
    "Skills UI should expose a named coordinate space and continuously track pointer movement."
)
require(
    skillsView.contains("private enum SkillDockMagnification") &&
        skillsView.contains("static let radius") &&
        skillsView.contains("static let maxScale") &&
        skillsView.contains("hypot("),
    "Skills UI should compute Dock-style scale from pointer-to-row center distance."
)
require(
    skillsView.contains("private struct SkillMagnifiedRow<Content: View>: View") &&
        skillsView.contains(".scaleEffect(rowScale, anchor: .center)") &&
        skillsView.contains("SkillRowFramePreferenceKey"),
    "Skills UI should apply Dock-style scale to the whole row."
)
require(
    !skillsView.contains("private struct SkillMagnifiedIcon"),
    "Skills UI should not magnify icons separately."
)
require(
    catalogRow.contains("let pointerLocation: CGPoint?") &&
        catalogRow.contains("SkillMagnifiedRow(pointerLocation: pointerLocation)") &&
        !catalogRow.contains("SkillMagnifiedIcon("),
    "Catalog skill rows should render through the whole-row magnification wrapper."
)
require(
    installedRow.contains("let pointerLocation: CGPoint?") &&
        installedRow.contains("SkillMagnifiedRow(pointerLocation: pointerLocation)") &&
        !installedRow.contains("SkillMagnifiedIcon("),
    "Installed skill rows should render through the whole-row magnification wrapper."
)
require(
    !catalogRow.contains(".clipShape(RoundedRectangle(cornerRadius: 8))") &&
        !installedRow.contains(".clipShape(RoundedRectangle(cornerRadius: 8))"),
    "Skill rows should not clip their content because clipping hides row magnification."
)
require(
    skillsView.contains("@Environment(\\.accessibilityReduceMotion)"),
    "Dock-style skill magnification should respect reduce motion."
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
    dashboardView.contains(".transition(.asymmetric("),
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
    !skillsView.contains("private func catalogDetailOverlay"),
    "Skill detail overlay should not be scoped to the Skills tab column."
)
require(
    dashboardView.contains("private func skillDetailOverlay"),
    "DashboardView should own the full-window skill detail overlay."
)
require(
    dashboardView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)"),
    "Skill detail overlay should fill the whole dashboard window and center the narrower sheet."
)
require(
    skillsView.contains("let onOpenSkillDetail: (SkillDetailPresentationItem) -> Void"),
    "SkillsTabView should notify DashboardView with a unified skill detail presentation item."
)
require(
    skillsView.contains(".font(.system(size: 22, weight: .semibold))"),
    "Skill detail title should use the smaller approved font size."
)
require(
    skillsView.contains(".font(.system(size: 16, weight: .regular))"),
    "Skill detail summary should be smaller than the Markdown body area."
)
require(
    skillsView.contains(".font(.system(size: 12, weight: .semibold))"),
    "Skill detail Description label should use a smaller font size."
)
require(
    skillsView.contains(".font(.system(size: 10, weight: .semibold))"),
    "Skill detail close icon should use the smaller approved font size."
)
require(
    skillsView.contains(".frame(width: 640)"),
    "Skill detail sheet should be narrower than the 760px skill list column."
)
require(
    catalogRow.contains("onInstall"),
    "Catalog skill rows should keep the quick install action."
)
require(
    catalogRow.contains(#"Image(systemName: "plus")"#),
    "Catalog skill rows should keep the install plus button."
)
require(
    !installedRow.contains("onRemove"),
    "Installed skill rows should not contain uninstall actions; uninstall belongs in the detail sheet."
)
require(
    !installedRow.contains(#"Image(systemName: "trash")"#),
    "Installed skill rows should not render the uninstall trash button."
)
require(
    installedRow.contains("let onOpen: () -> Void") &&
        installedRow.contains(".onTapGesture(perform: onOpen)"),
    "Installed skill rows should open the unified detail sheet when the row is clicked."
)
require(
    !installedRow.contains("onInfo") &&
        !installedRow.contains(#"Image(systemName: "info.circle")"#),
    "Installed skill rows should not use the old info button detail entry."
)
require(
    skillsView.contains("SkillDetailPresentationItem.fromCatalog") &&
        skillsView.contains("SkillDetailPresentationItem.fromInstalled"),
    "Both catalog and installed skills should be converted into the same detail presentation model."
)
require(
    !skillsView.contains("selectedSkillDetail") &&
        !skillsView.contains("func loadSkillDetail"),
    "SkillsTabView should not use the old selectedSkillDetail sheet path."
)
require(
    detailSheet.contains("let item: SkillDetailPresentationItem") &&
        detailSheet.contains("item.sourceTitle"),
    "Skill detail sheet should render from the unified presentation model."
)
require(
    detailSheet.contains("let isInstalling: Bool") &&
        detailSheet.contains("let isRemoving: Bool") &&
        detailSheet.contains("let canRemove: Bool") &&
        detailSheet.contains("let onInstall: () -> Void") &&
        detailSheet.contains("let onRemove: () -> Void"),
    "Skill detail sheet should own install and uninstall actions."
)
require(
    detailSheet.contains(#"Text("Install")"#) &&
        detailSheet.contains(#"Text("Uninstall")"#),
    "Skill detail sheet should render install and uninstall controls."
)
require(
    skillsView.contains("private struct SkillPillButtonStyle: ButtonStyle"),
    "Skills UI should use a local pill button style for skill install and uninstall controls."
)
require(
    skillsView.contains(".buttonStyle(SkillPillButtonStyle(tone: .install") &&
        detailSheet.contains(".buttonStyle(SkillPillButtonStyle(tone: .destructive"),
    "Skill install actions should use a dedicated install tone and uninstall should use the destructive pill style."
)
require(
    skillsView.contains("private enum SkillInstallPalette"),
    "Skills UI should centralize the install colors in a small palette."
)
require(
    skillsView.contains("Color(red: 1.0, green: 0.18, blue: 0.20)") &&
        skillsView.contains(".opacity(colorScheme == .dark ? 0.20 : 0.14)"),
    "Skill uninstall should use a translucent red pill background."
)
require(
    skillsView.contains("Color(red: 0.72, green: 0.47, blue: 0.12)") &&
        skillsView.contains("Color(red: 0.66, green: 0.40, blue: 0.23)"),
    "Skill install actions should use muted amber plus a subtle copper accent instead of blue or green."
)
require(
    !skillsView.contains(".buttonStyle(.borderedProminent)"),
    "Skill install controls should not use the system prominent blue button style."
)
require(
    skillsView.contains("@State private var showManualInstallSheet = false") &&
        skillsView.contains("manualInstallOverlay") &&
        skillsView.contains("ManualSkillInstallSheet") &&
        skillsView.contains("Install skill from GitHub repository"),
    "Skills UI should expose manual GitHub repository skill installation from the plus button."
)
require(
    viewModel.contains("@Published var isInstallingManualSkill = false") &&
        viewModel.contains("func installManualSkill") &&
        viewModel.contains("SkillCatalogService.manualInstallCommand"),
    "DashboardViewModel should keep manual repository skill installation state and actions."
)
require(
    skillCatalogService.contains("manualInstallCommand") &&
        skillCatalogService.contains("normalizedRepositoryURL"),
    "SkillCatalogService should build manual repository install commands."
)
require(
    skillsView.contains("private var filteredCustomInstalledSkills: [SkillInfo]") &&
        skillsView.contains("catalogItemsByName[$0.name] == nil") &&
        skillsView.contains("allSkillsContent") &&
        skillsView.contains("filteredCustomInstalledSkills"),
    "All skills should include custom installed skills that are missing from the catalog."
)
require(
    dashboardView.contains("onInstall: {") &&
        dashboardView.contains("installCatalogSkill(catalogItem)") &&
        dashboardView.contains("onRemove: {") &&
        dashboardView.contains("skillPendingRemoval = skill"),
    "Dashboard skill detail overlay should wire install and uninstall actions."
)

print("OK: skills UI cache and hover policy verified")

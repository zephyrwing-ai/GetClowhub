import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let skillsView = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("Skills")
    .appendingPathComponent("SkillsTabView.swift")
let dashboardView = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let dashboardViewModel = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("ViewModels")
    .appendingPathComponent("DashboardViewModel.swift")
let configView = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("ConfigTabView.swift")
let appAppearance = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Models")
    .appendingPathComponent("AppAppearance.swift")

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let viewText = (try? String(contentsOf: skillsView, encoding: .utf8)) ?? ""
let dashboardText = (try? String(contentsOf: dashboardView, encoding: .utf8)) ?? ""
let dashboardViewModelText = (try? String(contentsOf: dashboardViewModel, encoding: .utf8)) ?? ""
let configText = (try? String(contentsOf: configView, encoding: .utf8)) ?? ""
let appAppearanceText = (try? String(contentsOf: appAppearance, encoding: .utf8)) ?? ""
expect(appAppearanceText.contains(#"static let skills = "wand.and.sparkles""#), "The shared Skills SF Symbol should be centralized in AppSystemSymbol")
expect(viewText.contains(#"Image(systemName: AppSystemSymbol.skills)"#), "SkillsTabView should use the shared Skills SF Symbol as the default skill icon")
expect(!viewText.contains(#"Image(systemName: "puzzlepiece")"#), "SkillsTabView default skill icon should not reuse the Plugins puzzlepiece symbol")
expect(!viewText.contains(#"Image("SkillAvatarUnifiedDark")"#), "SkillsTabView should not use the SVG asset fallback for default skill icons")
expect(viewText.contains(".font(.system(size: size * 0.58, weight: .medium))"), "Default skill SF Symbol should be rendered through font metrics for crisp small sizes")
expect(viewText.contains("isUsingDefaultIcon"), "SkillCatalogIcon should distinguish default icons from custom icons")
expect(viewText.contains("skillDefaultIconBackground"), "SkillCatalogIcon should give the default icon its own contrast background")
expect(dashboardText.contains(#"navRow(.skills, title: String(localized: "Skills", bundle: languageManager.localizedBundle), systemImage: AppSystemSymbol.skills)"#), "Main sidebar Skills entry should use the shared Skills SF Symbol")
expect(dashboardViewModelText.contains(#"case .skills: return AppSystemSymbol.skills"#), "DashboardTab Skills icon should use the shared Skills SF Symbol")
expect(configText.contains(#"previewSidebarRow(icon: AppSystemSymbol.skills, title: localizedString("Skills"), active: true)"#), "Settings sidebar preview should use the shared Skills SF Symbol")

print("Skill default avatar uses an SF Symbol fallback")

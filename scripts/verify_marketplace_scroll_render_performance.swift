#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return source
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let plugins = read("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let skills = read("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabView.swift")

let pluginCatalogSection = slice(
    plugins,
    from: "private func catalogSection",
    to: "private func installedSection"
)
let pluginInstalledSection = slice(
    plugins,
    from: "private func installedSection",
    to: "private func matchesSearch"
)
let pluginIcon = slice(
    plugins,
    from: "private struct PluginCatalogIcon",
    to: "private struct PluginLoadingStateView"
)
let pluginCatalogRow = slice(
    plugins,
    from: "private struct CatalogPluginListRow",
    to: "private struct InstalledPluginListRow"
)
let pluginInstalledRow = slice(
    plugins,
    from: "private struct InstalledPluginListRow",
    to: "private struct PluginStatusMark"
)

let skillCatalogSection = slice(
    skills,
    from: "private func catalogSkillSection",
    to: "private var installedSkillsContent"
)
let skillInstalledSection = slice(
    skills,
    from: "private var installedSkillsContent",
    to: "private func matchesSearch"
)
let skillAllSection = slice(
    skills,
    from: "private func allSkillSection",
    to: "private func catalogSkillSection"
)
let skillIcon = slice(
    skills,
    from: "private struct SkillCatalogIcon",
    to: "private struct LoadingStateView"
)
let skillCatalogRow = slice(
    skills,
    from: "private struct CatalogSkillListRow",
    to: "private struct InstalledSkillListRow"
)
let skillInstalledRow = slice(
    skills,
    from: "private struct InstalledSkillListRow",
    to: "private struct InstalledStatusMark"
)

require(
    pluginCatalogSection.contains("LazyVStack(spacing: 0)") &&
        pluginInstalledSection.contains("LazyVStack(spacing: 0)"),
    "Plugins catalog and installed sections should use LazyVStack so offscreen rows are not eagerly built."
)
require(
    skillAllSection.contains("LazyVStack(spacing: 0)") &&
        skillCatalogSection.contains("LazyVStack(spacing: 0)") &&
        skillInstalledSection.contains("LazyVStack(spacing: 0)"),
    "Skills catalog and installed sections should use LazyVStack so offscreen rows are not eagerly built."
)
require(
    plugins.contains("private final class PluginIconImageCache") &&
        pluginIcon.contains("PluginIconImageCache.shared.image(for: iconURL)") &&
        !pluginIcon.contains("NSImage(contentsOf: iconURL)"),
    "Plugin icons should use a shared NSImage cache instead of synchronous image loading during body recomputation."
)
require(
    skills.contains("private final class SkillIconImageCache") &&
        skillIcon.contains("SkillIconImageCache.shared.image(for: iconURL)") &&
        !skillIcon.contains("NSImage(contentsOf: iconURL)"),
    "Skill icons should use a shared NSImage cache instead of synchronous image loading during body recomputation."
)
require(
    !pluginCatalogRow.contains("withAnimation(.easeInOut(duration: 0.18))") &&
        !pluginInstalledRow.contains("withAnimation(.easeInOut(duration: 0.18))") &&
        !pluginCatalogRow.contains(".animation(.easeInOut(duration: 0.18), value: isHovered)") &&
        !pluginInstalledRow.contains(".animation(.easeInOut(duration: 0.18), value: isHovered)"),
    "Plugin row hover should avoid per-row animation churn while scrolling."
)
require(
    !skillCatalogRow.contains("withAnimation(.easeInOut(duration: 0.18))") &&
        !skillInstalledRow.contains("withAnimation(.easeInOut(duration: 0.18))") &&
        !skillCatalogRow.contains(".animation(.easeInOut(duration: 0.18), value: isHovered)") &&
        !skillInstalledRow.contains(".animation(.easeInOut(duration: 0.18), value: isHovered)"),
    "Skill row hover should avoid per-row animation churn while scrolling."
)

print("Marketplace scroll render performance verification passed")

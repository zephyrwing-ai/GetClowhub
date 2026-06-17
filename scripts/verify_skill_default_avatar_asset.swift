import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetSet = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("SkillAvatarUnifiedDark.imageset")
let lightImage = assetSet.appendingPathComponent("skill-day.svg")
let darkImage = assetSet.appendingPathComponent("skill-night.svg")
let contents = assetSet.appendingPathComponent("Contents.json")
let agentAssetSet = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AgentAvatar.imageset")
let agentLightImage = agentAssetSet.appendingPathComponent("agent-day.svg")
let agentDarkImage = agentAssetSet.appendingPathComponent("agent-night.svg")
let skillsView = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("SkillsTabView.swift")

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(FileManager.default.fileExists(atPath: lightImage.path), "SkillAvatarUnifiedDark light SVG asset is missing")
expect(FileManager.default.fileExists(atPath: darkImage.path), "SkillAvatarUnifiedDark dark SVG asset is missing")

let contentsText = (try? String(contentsOf: contents, encoding: .utf8)) ?? ""
expect(contentsText.contains("skill-day.svg"), "asset catalog does not reference skill-day.svg")
expect(contentsText.contains("skill-night.svg"), "asset catalog does not reference skill-night.svg")
expect(contentsText.contains(#""appearance" : "luminosity""#), "asset catalog does not use luminosity appearance variants")
expect(!contentsText.contains("skill-avatar-unified-dark.png"), "asset catalog still references the replaced PNG")

let lightSVG = (try? String(contentsOf: lightImage, encoding: .utf8)) ?? ""
let darkSVG = (try? String(contentsOf: darkImage, encoding: .utf8)) ?? ""
let agentLightSVG = (try? String(contentsOf: agentLightImage, encoding: .utf8)) ?? ""
let agentDarkSVG = (try? String(contentsOf: agentDarkImage, encoding: .utf8)) ?? ""
expect(lightSVG.contains(#"viewBox="0 0 24 24""#), "skill light SVG should use the compact 24x24 viewBox")
expect(darkSVG.contains(#"viewBox="0 0 24 24""#), "skill dark SVG should use the compact 24x24 viewBox")
expect(lightSVG.contains(#"stroke-width="1.8""#), "skill light SVG ring stroke changed unexpectedly")
expect(darkSVG.contains(#"stroke-width="1.8""#), "skill dark SVG ring stroke changed unexpectedly")
for radius in ["9", "6", "3"] {
    expect(lightSVG.contains(#"r="\#(radius)""#), "skill light SVG \(radius)pt ring is missing")
    expect(darkSVG.contains(#"r="\#(radius)""#), "skill dark SVG \(radius)pt ring is missing")
    expect(agentLightSVG.contains(#"r="\#(radius)""#), "agent light SVG \(radius)pt ring is missing")
    expect(agentDarkSVG.contains(#"r="\#(radius)""#), "agent dark SVG \(radius)pt ring is missing")
}
expect(lightSVG.contains(##"r="1" fill="#151515""##), "skill light SVG must include a small filled center dot")
expect(darkSVG.contains(##"r="1" fill="#ffffff""##), "skill dark SVG must include a small filled center dot")
expect(!lightSVG.contains(##"r="11" fill="#151515""##), "skill light SVG must not use a filled black disk")
expect(!agentLightSVG.contains(##"r="11" fill="#151515""##), "agent light SVG must not use a filled black disk")
expect(!agentLightSVG.contains(##"r="1" fill="#151515""##), "agent light SVG must not include the skill center dot")
expect(!agentDarkSVG.contains(##"r="1" fill="#ffffff""##), "agent dark SVG must not include the skill center dot")
expect(!lightSVG.contains(#"width="1254""#), "skill light SVG still uses the oversized generated canvas")
expect(!darkSVG.contains(#"width="1254""#), "skill dark SVG still uses the oversized generated canvas")

let viewText = (try? String(contentsOf: skillsView, encoding: .utf8)) ?? ""
expect(viewText.contains(#"Image("SkillAvatarUnifiedDark")"#), "SkillsTabView does not use SkillAvatarUnifiedDark as fallback")
expect(viewText.contains("isUsingDefaultIcon"), "SkillCatalogIcon should distinguish default icons from custom icons")
expect(viewText.contains("skillDefaultIconBackground"), "SkillCatalogIcon should give the default icon its own contrast background")

print("Skill default avatar keeps the center dot while agent avatar stays hollow")

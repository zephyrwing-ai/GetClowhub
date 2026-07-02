import Foundation
import Combine

@MainActor
final class SkillsTabModel: ObservableObject {
    @Published var skills: [SkillInfo] = []
    @Published var skillsSummary: SkillsSummary = SkillsSummary()
    @Published var isLoadingSkills = false
    @Published var skillCatalog: [SkillCatalogItem] = []
    @Published var isLoadingSkillCatalog = false
    @Published var installingCatalogSkillName: String?
    @Published var removingSkillName: String?
    @Published var isInstallingManualSkill = false
    @Published var skillCatalogError: String?

    private let openclawService: OpenClawService
    private let notifySuccess: (String) -> Void
    private let notifyError: (String) -> Void
    private var hasLoadedSkillCatalog = false

    init(
        openclawService: OpenClawService,
        notifySuccess: @escaping (String) -> Void,
        notifyError: @escaping (String) -> Void
    ) {
        self.openclawService = openclawService
        self.notifySuccess = notifySuccess
        self.notifyError = notifyError
    }

    func loadSkills() async {
        isLoadingSkills = true
        let output = await openclawService.runCommand(
            "openclaw skills list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        let (parsed, summary) = DashboardViewModel.parseSkillsList(output: output)
        let trustedNames = DashboardViewModel.loadTrustedSkillNames()
        let decorated = parsed.map { skill in
            guard trustedNames.contains(skill.name),
                  SkillSourcePresentation(source: skill.source).kind != .builtIn else {
                return skill
            }
            return SkillInfo(
                name: skill.name,
                status: skill.status,
                description: skill.description,
                source: "getclawhub-trusted"
            )
        }
        skills = decorated.sorted { a, b in
            if a.status != b.status {
                return a.status == .ready
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        skillsSummary = summary
        isLoadingSkills = false
    }

    func loadSkillMarket(forceSync: Bool = false) async {
        if hasLoadedSkillCatalog && !forceSync {
            await loadSkills()
            return
        }

        guard !isLoadingSkillCatalog else { return }

        isLoadingSkillCatalog = true
        skillCatalogError = nil

        let cacheGitURL = SkillCatalogService.defaultCacheURL.appendingPathComponent(".git")
        let shouldSync = forceSync || !FileManager.default.fileExists(atPath: cacheGitURL.path)
        let syncOutput: String?
        if shouldSync {
            syncOutput = await openclawService.runCommand(
                "(\(SkillCatalogService.syncCommand()) && echo __OPENCLAW_SKILL_SYNC_OK__) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 120
            )
            if syncOutput?.contains("__OPENCLAW_SKILL_SYNC_OK__") != true {
                let detail = syncOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
                skillCatalogError = detail?.isEmpty == false ? detail : I18n.t("skills.error.refreshFailed")
                await loadSkills()
                isLoadingSkillCatalog = false
                return
            }
        } else {
            syncOutput = nil
        }

        do {
            skillCatalog = try SkillCatalogService.parseCatalog(rootURL: SkillCatalogService.defaultCacheURL)
            hasLoadedSkillCatalog = true
        } catch {
            let detail = syncOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
            skillCatalogError = detail?.isEmpty == false ? detail : error.localizedDescription
            skillCatalog = []
            hasLoadedSkillCatalog = false
        }

        await loadSkills()
        isLoadingSkillCatalog = false

        if forceSync && skillCatalogError == nil {
            notifySuccess(I18n.t("skills.toast.updated"))
        }
    }

    func installCatalogSkill(_ item: SkillCatalogItem) async {
        guard installingCatalogSkillName == nil else { return }

        installingCatalogSkillName = item.name
        let command = SkillCatalogService.installCommand(for: item)
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_SKILL_INSTALL_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 180
        )
        installingCatalogSkillName = nil

        if output?.contains("__OPENCLAW_SKILL_INSTALL_OK__") == true {
            DashboardViewModel.markTrustedSkill(item.name)
            await loadSkills()
            notifySuccess(I18n.format("skills.toast.installed", item.name))
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError(I18n.format("skills.toast.installFailed", item.name, trimmed?.isEmpty == false ? trimmed! : I18n.t("common.error.unknown")))
        }
    }

    @discardableResult
    func installManualSkill(repository: String) async -> Bool {
        guard !isInstallingManualSkill else { return false }

        let command: String
        do {
            command = try SkillCatalogService.manualInstallCommand(for: repository)
        } catch {
            notifyError(error.localizedDescription)
            return false
        }

        isInstallingManualSkill = true
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_MANUAL_SKILL_INSTALL_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 180
        )
        isInstallingManualSkill = false

        if output?.contains("__OPENCLAW_MANUAL_SKILL_INSTALL_OK__") == true {
            await loadSkills()
            notifySuccess(I18n.t("skills.toast.manualInstalled"))
            return true
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError(I18n.format("skills.toast.manualInstallFailed", trimmed?.isEmpty == false ? trimmed! : I18n.t("common.error.unknown")))
            return false
        }
    }

    static func canRemoveSkill(_ skill: SkillInfo) -> Bool {
        SkillSourcePresentation(source: skill.source).isRemovable
    }

    func removeSkill(_ skill: SkillInfo) async {
        guard Self.canRemoveSkill(skill) else {
            notifyError(I18n.t("skills.error.builtInRemove"))
            return
        }

        removingSkillName = skill.name
        let scopeFlag = skill.source == "openclaw-workspace" ? "" : " -g"
        let command = "npx skills remove \(Self.shellQuote(skill.name))\(scopeFlag) -y"
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_SKILL_REMOVE_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 120
        )
        removingSkillName = nil

        if output?.contains("__OPENCLAW_SKILL_REMOVE_OK__") == true {
            DashboardViewModel.unmarkTrustedSkill(skill.name)
            await loadSkills()
            notifySuccess(I18n.format("skills.toast.removed", skill.name))
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError(I18n.format("skills.toast.removeFailed", skill.name, trimmed?.isEmpty == false ? trimmed! : I18n.t("common.error.unknown")))
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGE_MANAGER = ROOT / "OpenClawInstaller" / "Services" / "LanguageManager.swift"
LOCALIZABLE = ROOT / "OpenClawInstaller" / "Localizable.xcstrings"
RESOURCES = ROOT / "OpenClawInstaller" / "Resources"
I18N_ROOT = RESOURCES / "I18n"
SKILLS_ROOT = Path.home() / ".openclaw" / "getclowhub-skills-catalog"
PLUGINS_ROOT = Path.home() / ".openclaw" / "getclowhub-plugins-catalog"

COMMON = {
    "common.error.unknown": "unknown error",
    "common.value.unknown": "Unknown",
    "catalog.action.install": "Install",
    "catalog.action.installing": "Installing...",
    "catalog.action.uninstall": "Uninstall",
    "catalog.action.remove": "Remove",
    "catalog.action.removing": "Removing...",
    "catalog.action.cancel": "Cancel",
    "catalog.action.close": "Close",
    "catalog.action.refresh": "Refresh",
    "catalog.action.update": "Update",
    "catalog.action.enable": "Enable",
    "catalog.action.disable": "Disable",
    "catalog.status.installed": "Installed",
    "catalog.status.notInstalled": "Not installed",
    "catalog.status.ready": "Ready",
    "catalog.status.missing": "Missing",
    "catalog.status.loaded": "Loaded",
    "catalog.status.disabled": "Disabled",
    "catalog.status.unavailable": "Unavailable",
    "catalog.section.recommend": "Recommend",
    "catalog.section.catalog": "Catalog",
    "catalog.section.all": "All",
    "catalog.section.installed": "Installed",
    "catalog.section.builtIn": "Built-in",
    "catalog.section.custom": "Custom",
    "catalog.detail.description": "Description",
    "catalog.count.installed": "%lld installed"
}

COMMON_ZH_HANS = {
    "common.error.unknown": "未知错误",
    "common.value.unknown": "未知",
    "catalog.action.install": "安装",
    "catalog.action.installing": "安装中...",
    "catalog.action.uninstall": "卸载",
    "catalog.action.remove": "移除",
    "catalog.action.removing": "移除中...",
    "catalog.action.cancel": "取消",
    "catalog.action.close": "关闭",
    "catalog.action.refresh": "刷新",
    "catalog.action.update": "更新",
    "catalog.action.enable": "启用",
    "catalog.action.disable": "停用",
    "catalog.status.installed": "已安装",
    "catalog.status.notInstalled": "未安装",
    "catalog.status.ready": "就绪",
    "catalog.status.missing": "缺少依赖",
    "catalog.status.loaded": "已加载",
    "catalog.status.disabled": "已停用",
    "catalog.status.unavailable": "不可用",
    "catalog.section.recommend": "推荐",
    "catalog.section.catalog": "目录",
    "catalog.section.all": "全部",
    "catalog.section.installed": "已安装",
    "catalog.section.builtIn": "内置",
    "catalog.section.custom": "自定义",
    "catalog.detail.description": "描述",
    "catalog.count.installed": "已安装 %lld 个"
}

COMMON_ZH_HANT = {
    "common.error.unknown": "未知錯誤",
    "common.value.unknown": "未知",
    "catalog.action.install": "安裝",
    "catalog.action.installing": "安裝中...",
    "catalog.action.uninstall": "解除安裝",
    "catalog.action.remove": "移除",
    "catalog.action.removing": "移除中...",
    "catalog.action.cancel": "取消",
    "catalog.action.close": "關閉",
    "catalog.action.refresh": "重新整理",
    "catalog.action.update": "更新",
    "catalog.action.enable": "啟用",
    "catalog.action.disable": "停用",
    "catalog.status.installed": "已安裝",
    "catalog.status.notInstalled": "未安裝",
    "catalog.status.ready": "就緒",
    "catalog.status.missing": "缺少依賴",
    "catalog.status.loaded": "已載入",
    "catalog.status.disabled": "已停用",
    "catalog.status.unavailable": "不可用",
    "catalog.section.recommend": "推薦",
    "catalog.section.catalog": "目錄",
    "catalog.section.all": "全部",
    "catalog.section.installed": "已安裝",
    "catalog.section.builtIn": "內建",
    "catalog.section.custom": "自訂",
    "catalog.detail.description": "描述",
    "catalog.count.installed": "已安裝 %lld 個"
}

SKILLS_UI = {
    "skills.title": "Skills",
    "skills.subtitle": "Extend GetClowHub with task-specific skills",
    "skills.search.placeholder": "Search skills",
    "skills.help.installFromRepository": "Install skill from GitHub repository",
    "skills.help.refresh": "Refresh skills",
    "skills.loading.catalog": "Loading skill catalog...",
    "skills.loading.installed": "Loading installed skills...",
    "skills.empty.catalogLoadFailed": "Could not load skill catalog",
    "skills.empty.noRecommended": "No recommended skills",
    "skills.empty.noMatchingRecommended": "No matching recommended skills",
    "skills.empty.noSkills": "No skills found",
    "skills.empty.noMatchingSkills": "No matching skills",
    "skills.empty.noInstalled": "No installed skills",
    "skills.empty.noMatchingInstalled": "No matching installed skills",
    "skills.alert.removeTitle": "Remove Skill",
    "skills.alert.removeMessage": "Remove \"%@\" from installed skills?",
    "skills.manual.title": "Install Skill",
    "skills.manual.subtitle": "Install a GitHub skill repository globally.",
    "skills.manual.repository": "Repository",
    "skills.fallback.installedSkill": "Installed skill",
    "skills.toast.updated": "Skills updated successfully",
    "skills.toast.installed": "Installed skill %@",
    "skills.toast.installFailed": "Failed to install %@: %@",
    "skills.toast.manualInstalled": "Installed skill from repository",
    "skills.toast.manualInstallFailed": "Failed to install skill: %@",
    "skills.toast.removed": "Removed skill %@",
    "skills.toast.removeFailed": "Failed to remove %@: %@",
    "skills.error.refreshFailed": "Failed to refresh skills",
    "skills.error.builtInRemove": "Built-in skills cannot be removed"
}

SKILLS_UI_ZH_HANS = {
    "skills.title": "技能",
    "skills.subtitle": "使用面向任务的技能扩展 GetClowHub",
    "skills.search.placeholder": "搜索技能",
    "skills.help.installFromRepository": "从 GitHub 仓库安装技能",
    "skills.help.refresh": "刷新技能",
    "skills.loading.catalog": "正在加载技能目录...",
    "skills.loading.installed": "正在加载已安装技能...",
    "skills.empty.catalogLoadFailed": "无法加载技能目录",
    "skills.empty.noRecommended": "暂无推荐技能",
    "skills.empty.noMatchingRecommended": "没有匹配的推荐技能",
    "skills.empty.noSkills": "没有找到技能",
    "skills.empty.noMatchingSkills": "没有匹配的技能",
    "skills.empty.noInstalled": "暂无已安装技能",
    "skills.empty.noMatchingInstalled": "没有匹配的已安装技能",
    "skills.alert.removeTitle": "移除技能",
    "skills.alert.removeMessage": "要从已安装技能中移除“%@”吗？",
    "skills.manual.title": "安装技能",
    "skills.manual.subtitle": "全局安装一个 GitHub 技能仓库。",
    "skills.manual.repository": "仓库",
    "skills.fallback.installedSkill": "已安装技能",
    "skills.toast.updated": "技能已更新",
    "skills.toast.installed": "已安装技能 %@",
    "skills.toast.installFailed": "安装 %@ 失败：%@",
    "skills.toast.manualInstalled": "已从仓库安装技能",
    "skills.toast.manualInstallFailed": "安装技能失败：%@",
    "skills.toast.removed": "已移除技能 %@",
    "skills.toast.removeFailed": "移除 %@ 失败：%@",
    "skills.error.refreshFailed": "刷新技能失败",
    "skills.error.builtInRemove": "内置技能不能移除"
}

SKILLS_UI_ZH_HANT = {
    "skills.title": "技能",
    "skills.subtitle": "使用面向任務的技能擴充 GetClowHub",
    "skills.search.placeholder": "搜尋技能",
    "skills.help.installFromRepository": "從 GitHub 倉庫安裝技能",
    "skills.help.refresh": "重新整理技能",
    "skills.loading.catalog": "正在載入技能目錄...",
    "skills.loading.installed": "正在載入已安裝技能...",
    "skills.empty.catalogLoadFailed": "無法載入技能目錄",
    "skills.empty.noRecommended": "暫無推薦技能",
    "skills.empty.noMatchingRecommended": "沒有符合的推薦技能",
    "skills.empty.noSkills": "沒有找到技能",
    "skills.empty.noMatchingSkills": "沒有符合的技能",
    "skills.empty.noInstalled": "暫無已安裝技能",
    "skills.empty.noMatchingInstalled": "沒有符合的已安裝技能",
    "skills.alert.removeTitle": "移除技能",
    "skills.alert.removeMessage": "要從已安裝技能中移除「%@」嗎？",
    "skills.manual.title": "安裝技能",
    "skills.manual.subtitle": "全域安裝一個 GitHub 技能倉庫。",
    "skills.manual.repository": "倉庫",
    "skills.fallback.installedSkill": "已安裝技能",
    "skills.toast.updated": "技能已更新",
    "skills.toast.installed": "已安裝技能 %@",
    "skills.toast.installFailed": "安裝 %@ 失敗：%@",
    "skills.toast.manualInstalled": "已從倉庫安裝技能",
    "skills.toast.manualInstallFailed": "安裝技能失敗：%@",
    "skills.toast.removed": "已移除技能 %@",
    "skills.toast.removeFailed": "移除 %@ 失敗：%@",
    "skills.error.refreshFailed": "重新整理技能失敗",
    "skills.error.builtInRemove": "內建技能不能移除"
}

PLUGINS_UI = {
    "plugins.title": "Plugins",
    "plugins.subtitle": "Install curated OpenClaw plugins from the GetClowHub catalog",
    "plugins.search.placeholder": "Search plugins",
    "plugins.help.updateInstalled": "Update installed plugins",
    "plugins.help.installCustom": "Install custom plugin",
    "plugins.help.refresh": "Refresh plugins",
    "plugins.loading.catalog": "Loading plugin catalog...",
    "plugins.loading.installed": "Loading installed plugins...",
    "plugins.empty.catalogLoadFailed": "Could not load plugin catalog",
    "plugins.empty.noRecommended": "No recommended plugins",
    "plugins.empty.noMatchingRecommended": "No matching recommended plugins",
    "plugins.empty.noPlugins": "No plugins found",
    "plugins.empty.noMatchingPlugins": "No matching plugins",
    "plugins.empty.noInstalled": "No installed plugins",
    "plugins.empty.noMatchingInstalled": "No matching installed plugins",
    "plugins.alert.uninstallTitle": "Uninstall Plugin",
    "plugins.alert.uninstallMessage": "Are you sure you want to uninstall '%@'?",
    "plugins.install.title": "Install Plugin",
    "plugins.install.method": "Install Method",
    "plugins.install.method.npm": "npm",
    "plugins.install.method.file": "File",
    "plugins.install.method.link": "Link",
    "plugins.install.quickSelect": "Quick Select",
    "plugins.install.preset.custom": "Custom",
    "plugins.install.packageName": "Package Name",
    "plugins.install.packagePlaceholder": "e.g. @openclaw/discord",
    "plugins.install.presetAlreadyInstalled": "%@ plugin is already installed",
    "plugins.install.pluginFile": "Plugin File",
    "plugins.install.filePlaceholder": "Select a plugin file...",
    "plugins.install.browse": "Browse",
    "plugins.install.supportedFileTypes": "Supported: .ts .js .zip .tgz .tar.gz",
    "plugins.install.pluginLink": "Plugin Link",
    "plugins.install.linkPlaceholder": "https://github.com/owner/repo",
    "plugins.install.linkHelp": "Enter a plugin URL, GitHub repository, archive URL, or remote package spec",
    "plugins.install.installing": "Installing...",
    "plugins.toast.notInstallable": "%@ is not installable by OpenClaw.",
    "plugins.toast.installed": "Installed plugin %@",
    "plugins.toast.installFailed": "Failed to install %@: %@",
    "plugins.toast.enableFailed": "Failed to enable %@: %@",
    "plugins.toast.enabled": "%@ enabled",
    "plugins.toast.disableFailed": "Failed to disable %@: %@",
    "plugins.toast.disabled": "%@ disabled",
    "plugins.toast.customInstallFailed": "Failed to install plugin: %@",
    "plugins.toast.customInstalled": "Plugin installed successfully",
    "plugins.toast.weixinInstallFailed": "Failed to install Weixin plugin: %@",
    "plugins.toast.weixinInstalled": "Weixin plugin installed successfully",
    "plugins.toast.builtInUninstall": "Built-in plugins cannot be uninstalled. Use Disable instead.",
    "plugins.toast.uninstallFailed": "Failed to uninstall %@: %@",
    "plugins.toast.uninstalled": "%@ uninstalled",
    "plugins.toast.removeFilesFailed": "Failed to remove %@ files: %@",
    "plugins.toast.updateFailed": "Failed to update %@: %@",
    "plugins.toast.updated": "%@ updated",
    "plugins.toast.updateAllFailed": "Failed to update plugins: %@",
    "plugins.toast.allUpdated": "All plugins updated",
    "plugins.fallback.installedPlugin": "Installed OpenClaw plugin",
    "plugins.fallback.openClawPlugin": "OpenClaw plugin"
}

PLUGINS_UI_ZH_HANS = {
    "plugins.title": "插件",
    "plugins.subtitle": "从 GetClowHub 目录安装精选 OpenClaw 插件",
    "plugins.search.placeholder": "搜索插件",
    "plugins.help.updateInstalled": "更新已安装插件",
    "plugins.help.installCustom": "安装自定义插件",
    "plugins.help.refresh": "刷新插件",
    "plugins.loading.catalog": "正在加载插件目录...",
    "plugins.loading.installed": "正在加载已安装插件...",
    "plugins.empty.catalogLoadFailed": "无法加载插件目录",
    "plugins.empty.noRecommended": "暂无推荐插件",
    "plugins.empty.noMatchingRecommended": "没有匹配的推荐插件",
    "plugins.empty.noPlugins": "没有找到插件",
    "plugins.empty.noMatchingPlugins": "没有匹配的插件",
    "plugins.empty.noInstalled": "暂无已安装插件",
    "plugins.empty.noMatchingInstalled": "没有匹配的已安装插件",
    "plugins.alert.uninstallTitle": "卸载插件",
    "plugins.alert.uninstallMessage": "确定要卸载“%@”吗？",
    "plugins.install.title": "安装插件",
    "plugins.install.method": "安装方式",
    "plugins.install.method.npm": "npm",
    "plugins.install.method.file": "文件",
    "plugins.install.method.link": "链接",
    "plugins.install.quickSelect": "快速选择",
    "plugins.install.preset.custom": "自定义",
    "plugins.install.packageName": "包名",
    "plugins.install.packagePlaceholder": "例如 @openclaw/discord",
    "plugins.install.presetAlreadyInstalled": "%@ 插件已安装",
    "plugins.install.pluginFile": "插件文件",
    "plugins.install.filePlaceholder": "选择插件文件...",
    "plugins.install.browse": "浏览",
    "plugins.install.supportedFileTypes": "支持：.ts .js .zip .tgz .tar.gz",
    "plugins.install.pluginLink": "插件链接",
    "plugins.install.linkPlaceholder": "https://github.com/owner/repo",
    "plugins.install.linkHelp": "输入插件 URL、GitHub 仓库、归档地址或远程包规格",
    "plugins.install.installing": "安装中...",
    "plugins.toast.notInstallable": "%@ 不能由 OpenClaw 安装。",
    "plugins.toast.installed": "已安装插件 %@",
    "plugins.toast.installFailed": "安装 %@ 失败：%@",
    "plugins.toast.enableFailed": "启用 %@ 失败：%@",
    "plugins.toast.enabled": "%@ 已启用",
    "plugins.toast.disableFailed": "停用 %@ 失败：%@",
    "plugins.toast.disabled": "%@ 已停用",
    "plugins.toast.customInstallFailed": "安装插件失败：%@",
    "plugins.toast.customInstalled": "插件安装成功",
    "plugins.toast.weixinInstallFailed": "安装微信插件失败：%@",
    "plugins.toast.weixinInstalled": "微信插件安装成功",
    "plugins.toast.builtInUninstall": "内置插件不能卸载，请使用停用。",
    "plugins.toast.uninstallFailed": "卸载 %@ 失败：%@",
    "plugins.toast.uninstalled": "%@ 已卸载",
    "plugins.toast.removeFilesFailed": "移除 %@ 文件失败：%@",
    "plugins.toast.updateFailed": "更新 %@ 失败：%@",
    "plugins.toast.updated": "%@ 已更新",
    "plugins.toast.updateAllFailed": "更新插件失败：%@",
    "plugins.toast.allUpdated": "全部插件已更新",
    "plugins.fallback.installedPlugin": "已安装 OpenClaw 插件",
    "plugins.fallback.openClawPlugin": "OpenClaw 插件"
}

PLUGINS_UI_ZH_HANT = {
    "plugins.title": "外掛",
    "plugins.subtitle": "從 GetClowHub 目錄安裝精選 OpenClaw 外掛",
    "plugins.search.placeholder": "搜尋外掛",
    "plugins.help.updateInstalled": "更新已安裝外掛",
    "plugins.help.installCustom": "安裝自訂外掛",
    "plugins.help.refresh": "重新整理外掛",
    "plugins.loading.catalog": "正在載入外掛目錄...",
    "plugins.loading.installed": "正在載入已安裝外掛...",
    "plugins.empty.catalogLoadFailed": "無法載入外掛目錄",
    "plugins.empty.noRecommended": "暫無推薦外掛",
    "plugins.empty.noMatchingRecommended": "沒有符合的推薦外掛",
    "plugins.empty.noPlugins": "沒有找到外掛",
    "plugins.empty.noMatchingPlugins": "沒有符合的外掛",
    "plugins.empty.noInstalled": "暫無已安裝外掛",
    "plugins.empty.noMatchingInstalled": "沒有符合的已安裝外掛",
    "plugins.alert.uninstallTitle": "解除安裝外掛",
    "plugins.alert.uninstallMessage": "確定要解除安裝「%@」嗎？",
    "plugins.install.title": "安裝外掛",
    "plugins.install.method": "安裝方式",
    "plugins.install.method.npm": "npm",
    "plugins.install.method.file": "檔案",
    "plugins.install.method.link": "連結",
    "plugins.install.quickSelect": "快速選擇",
    "plugins.install.preset.custom": "自訂",
    "plugins.install.packageName": "套件名稱",
    "plugins.install.packagePlaceholder": "例如 @openclaw/discord",
    "plugins.install.presetAlreadyInstalled": "%@ 外掛已安裝",
    "plugins.install.pluginFile": "外掛檔案",
    "plugins.install.filePlaceholder": "選擇外掛檔案...",
    "plugins.install.browse": "瀏覽",
    "plugins.install.supportedFileTypes": "支援：.ts .js .zip .tgz .tar.gz",
    "plugins.install.pluginLink": "外掛連結",
    "plugins.install.linkPlaceholder": "https://github.com/owner/repo",
    "plugins.install.linkHelp": "輸入外掛 URL、GitHub 倉庫、封存檔地址或遠端套件規格",
    "plugins.install.installing": "安裝中...",
    "plugins.toast.notInstallable": "%@ 不能由 OpenClaw 安裝。",
    "plugins.toast.installed": "已安裝外掛 %@",
    "plugins.toast.installFailed": "安裝 %@ 失敗：%@",
    "plugins.toast.enableFailed": "啟用 %@ 失敗：%@",
    "plugins.toast.enabled": "%@ 已啟用",
    "plugins.toast.disableFailed": "停用 %@ 失敗：%@",
    "plugins.toast.disabled": "%@ 已停用",
    "plugins.toast.customInstallFailed": "安裝外掛失敗：%@",
    "plugins.toast.customInstalled": "外掛安裝成功",
    "plugins.toast.weixinInstallFailed": "安裝微信外掛失敗：%@",
    "plugins.toast.weixinInstalled": "微信外掛安裝成功",
    "plugins.toast.builtInUninstall": "內建外掛不能解除安裝，請使用停用。",
    "plugins.toast.uninstallFailed": "解除安裝 %@ 失敗：%@",
    "plugins.toast.uninstalled": "%@ 已解除安裝",
    "plugins.toast.removeFilesFailed": "移除 %@ 檔案失敗：%@",
    "plugins.toast.updateFailed": "更新 %@ 失敗：%@",
    "plugins.toast.updated": "%@ 已更新",
    "plugins.toast.updateAllFailed": "更新外掛失敗：%@",
    "plugins.toast.allUpdated": "全部外掛已更新",
    "plugins.fallback.installedPlugin": "已安裝 OpenClaw 外掛",
    "plugins.fallback.openClawPlugin": "OpenClaw 外掛"
}

SETTINGS = {
    "settings.i18n.placeholder": "Settings translations are provided by Localizable.xcstrings.",
    "All settings": "All settings",
    "Local user": "Local user",
}
SETTINGS_ZH_HANS = {
    "settings.i18n.placeholder": "设置翻译由 Localizable.xcstrings 提供。",
    "All settings": "全部设置",
    "Local user": "本地用户",
}
SETTINGS_ZH_HANT = {
    "settings.i18n.placeholder": "設定翻譯由 Localizable.xcstrings 提供。",
    "All settings": "全部設定",
    "Local user": "本機使用者",
}

AGENTS_UI = {
    "agents.search.placeholder": "Search agents...",
    "agents.empty.noMatching": "No matching agents",
    "agents.detail.vibe": "Vibe",
    "agents.detail.personaContent": "Persona Content",
    "agents.action.recruit": "Recruit",
    "agents.action.recruiting": "Recruiting...",
    "agents.action.recruited": "Recruited",
    "agents.alert.recruitFailed": "Recruit Failed",
    "agents.alert.ok": "OK",
}

AGENTS_UI_ZH_HANS = {
    "agents.search.placeholder": "搜索助手...",
    "agents.empty.noMatching": "没有匹配的助手",
    "agents.detail.vibe": "风格",
    "agents.detail.personaContent": "人设内容",
    "agents.action.recruit": "招募",
    "agents.action.recruiting": "招募中...",
    "agents.action.recruited": "已招募",
    "agents.alert.recruitFailed": "招募失败",
    "agents.alert.ok": "确定",
}

AGENTS_UI_ZH_HANT = {
    "agents.search.placeholder": "搜尋助手...",
    "agents.empty.noMatching": "沒有符合的助手",
    "agents.detail.vibe": "風格",
    "agents.detail.personaContent": "人設內容",
    "agents.action.recruit": "招募",
    "agents.action.recruiting": "招募中...",
    "agents.action.recruited": "已招募",
    "agents.alert.recruitFailed": "招募失敗",
    "agents.alert.ok": "確定",
}


def supported_languages():
    text = LANGUAGE_MANAGER.read_text(encoding="utf-8")
    return [m.group(1) for m in re.finditer(r'Language\(id:\s*"([^"]+)"', text) if m.group(1) != "system"]


def slug(value):
    return re.sub(r"[^a-z0-9]+", ".", value.lower()).strip(".") or "item"


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def frontmatter_and_body(markdown):
    text = markdown.replace("\r\n", "\n")
    if not text.startswith("---\n"):
        return {}, text.strip()
    end = text.find("\n---", 4)
    if end < 0:
        return {}, text.strip()
    fm = {}
    for line in text[4:end].splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        fm[k.strip()] = v.strip().strip('"\'')
    return fm, text[end + 4:].strip()


def first_paragraph(body):
    for line in body.splitlines():
        t = line.strip()
        if t and not t.startswith("#") and not t.startswith("```"):
            return t
    return ""


def display_name(identifier):
    return " ".join(part[:1].upper() + part[1:] for part in re.split(r"[-_]+", identifier) if part)


def zh_skill_name(name):
    mapping = {
        "playwright": "Playwright 浏览器自动化",
        "openai-docs": "OpenAI 文档",
        "agent-reach": "互联网调研",
        "skill-creator": "技能创建器",
        "plugin-creator": "插件创建器",
        "imagegen": "图像生成",
        "pdf": "PDF 处理",
        "dws": "钉钉工作台",
        "figma": "Figma",
    }
    return mapping.get(name, display_name(name))


def zh_skill_description(name, english):
    return f"{zh_skill_name(name)}技能：{english}" if english else f"{zh_skill_name(name)}技能，适合处理相关任务。"


def zh_plugin_name(name, display):
    mapping = {
        "dingtalk": "钉钉",
        "wechat": "微信",
        "weixin": "微信",
        "telegram": "Telegram",
        "discord": "Discord",
        "slack": "Slack",
        "context-mode": "Context Mode",
    }
    key = name.lower()
    return mapping.get(key, display)


def zh_plugin_description(name, english):
    return f"{zh_plugin_name(name, display_name(name))}插件：{english}" if english else f"{zh_plugin_name(name, display_name(name))}插件，用于扩展 OpenClaw 能力。"


def build_agents_base():
    agents = read_json(RESOURCES / "marketplace_agents.json", [])
    old_i18n = read_json(RESOURCES / "marketplace_agents.i18n.json", {})
    result = {}
    localized = {lang: {} for lang in supported_languages()}
    for agent in agents:
        aid = agent.get("id", "")
        if not aid:
            continue
        prefix = f"agents.{slug(aid)}"
        fields = {
            f"{prefix}.name": agent.get("name", ""),
            f"{prefix}.division": agent.get("division", ""),
            f"{prefix}.description": agent.get("description", ""),
            f"{prefix}.vibe": agent.get("vibe", ""),
            f"{prefix}.specialty": agent.get("specialty") or "",
            f"{prefix}.whenToUse": agent.get("whenToUse") or "",
            f"{prefix}.content": agent.get("content") or "",
        }
        result.update(fields)
        for lang in localized:
            localized[lang].update(fields)
        for lang, entry in old_i18n.get(aid, {}).items():
            if lang not in localized:
                continue
            for field in ["name", "division", "description", "vibe", "specialty", "whenToUse"]:
                if entry.get(field):
                    localized[lang][f"{prefix}.{field}"] = entry[field]
            # Content intentionally defaults to canonical English until explicitly translated.
    localized["en"] = result.copy()
    return localized


def build_skills_base():
    skills_dir = SKILLS_ROOT / "skills"
    entries = {}
    if skills_dir.exists():
        for path in sorted(skills_dir.iterdir(), key=lambda p: p.name.lower()):
            skill_file = path / "SKILL.md"
            if not skill_file.exists():
                continue
            markdown = skill_file.read_text(encoding="utf-8", errors="replace")
            fm, body = frontmatter_and_body(markdown)
            name = fm.get("name") or path.name
            desc = fm.get("description") or first_paragraph(body)
            prefix = f"skills.catalog.{slug(name)}"
            entries[f"{prefix}.displayName"] = display_name(name)
            entries[f"{prefix}.description"] = desc
            entries[f"{prefix}.content"] = body or desc
    localized = {lang: entries.copy() for lang in supported_languages()}
    for lang in ["zh-Hans", "zh-Hant"]:
        if lang in localized:
            for key, value in list(entries.items()):
                m = re.match(r"skills\.catalog\.([^.].*)\.(displayName|description|content)$", key)
                if not m:
                    continue
                item_slug, field = m.groups()
                raw_name = item_slug.replace(".", "-")
                if field == "displayName":
                    localized[lang][key] = zh_skill_name(raw_name)
                elif field == "description":
                    localized[lang][key] = zh_skill_description(raw_name, value)
                else:
                    localized[lang][key] = value
    localized["en"] = entries.copy()
    return localized


def plugin_catalog_paths():
    marketplace = PLUGINS_ROOT / ".agents" / "plugins" / "marketplace.json"
    data = read_json(marketplace, {})
    plugins = data.get("plugins", [])
    paths = []
    for item in plugins:
        rel = item.get("path") or (item.get("source") or {}).get("path") or ("plugins/" + (item.get("name") or item.get("id") or ""))
        if rel:
            paths.append(PLUGINS_ROOT / rel)
    if not paths and (PLUGINS_ROOT / "plugins").exists():
        paths = [p for p in (PLUGINS_ROOT / "plugins").iterdir() if p.is_dir()]
    return paths


def build_plugins_base():
    entries = {}
    for plugin_dir in sorted(plugin_catalog_paths(), key=lambda p: p.name.lower()):
        openclaw = read_json(plugin_dir / "openclaw.plugin.json", {})
        package = read_json(plugin_dir / "package.json", {})
        package_name = package.get("name") or ""
        unscoped = package_name.split("/")[-1] if package_name else ""
        name = openclaw.get("id") or unscoped or plugin_dir.name
        display = openclaw.get("displayName") or openclaw.get("name") or display_name(name)
        desc = openclaw.get("description") or package.get("description") or "OpenClaw plugin"
        readme = ""
        for candidate in ["README.md", "readme.md"]:
            p = plugin_dir / candidate
            if p.exists():
                readme = p.read_text(encoding="utf-8", errors="replace").strip()
                break
        long_desc = openclaw.get("longDescription") or readme or desc
        category = openclaw.get("category") or ("Communication" if openclaw.get("channels") else "Productivity")
        prefix = f"plugins.catalog.{slug(name)}"
        entries[f"{prefix}.displayName"] = display
        entries[f"{prefix}.description"] = desc
        entries[f"{prefix}.longDescription"] = long_desc
        entries[f"{prefix}.category"] = category
        caps = openclaw.get("capabilities") or []
        for idx, cap in enumerate(caps):
            entries[f"{prefix}.capabilities.{idx}"] = cap
    localized = {lang: entries.copy() for lang in supported_languages()}
    for lang in ["zh-Hans", "zh-Hant"]:
        if lang in localized:
            for key, value in list(entries.items()):
                m = re.match(r"plugins\.catalog\.([^.].*)\.(displayName|description|longDescription|category|capabilities\.\d+)$", key)
                if not m:
                    continue
                item_slug, field = m.groups()
                raw_name = item_slug.replace(".", "-")
                if field == "displayName":
                    localized[lang][key] = zh_plugin_name(raw_name, value)
                elif field == "description":
                    localized[lang][key] = zh_plugin_description(raw_name, value)
                elif field == "category":
                    localized[lang][key] = {"Communication":"通信", "Productivity":"效率", "Memory":"记忆"}.get(value, value)
                else:
                    localized[lang][key] = value
    localized["en"] = entries.copy()
    return localized


def build_settings_base():
    catalog = read_json(LOCALIZABLE, {})
    strings = catalog.get("strings", {})
    localized = {lang: {} for lang in supported_languages()}
    for key, entry in strings.items():
        if not isinstance(key, str):
            continue
        localized["en"][key] = key
        localizations = entry.get("localizations", {}) if isinstance(entry, dict) else {}
        for lang in localized:
            if lang == "en":
                continue
            value = (
                localizations.get(lang, {})
                .get("stringUnit", {})
                .get("value")
            )
            localized[lang][key] = value if isinstance(value, str) and value.strip() else key
    return localized


def write_namespace(language, namespace, values):
    directory = I18N_ROOT / language
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{namespace}.json"
    path.write_text(json.dumps(dict(sorted(values.items())), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    langs = supported_languages()
    agents = build_agents_base()
    skills_catalog = build_skills_base()
    plugins_catalog = build_plugins_base()
    settings_catalog = build_settings_base()
    for lang in langs:
        common = COMMON.copy()
        skills = SKILLS_UI.copy()
        plugins = PLUGINS_UI.copy()
        settings = SETTINGS.copy()
        agent_ui = AGENTS_UI.copy()
        if lang == "zh-Hans":
            common.update(COMMON_ZH_HANS); skills.update(SKILLS_UI_ZH_HANS); plugins.update(PLUGINS_UI_ZH_HANS); settings.update(SETTINGS_ZH_HANS); agent_ui.update(AGENTS_UI_ZH_HANS)
        elif lang == "zh-Hant":
            common.update(COMMON_ZH_HANT); skills.update(SKILLS_UI_ZH_HANT); plugins.update(PLUGINS_UI_ZH_HANT); settings.update(SETTINGS_ZH_HANT); agent_ui.update(AGENTS_UI_ZH_HANT)
        settings.update(settings_catalog.get(lang, settings_catalog.get("en", {})))
        skills.update(skills_catalog.get(lang, {}))
        plugins.update(plugins_catalog.get(lang, {}))
        write_namespace(lang, "common", common)
        write_namespace(lang, "settings", settings)
        agent_ui.update(agents.get(lang, agents.get("en", {})))
        write_namespace(lang, "agents", agent_ui)
        write_namespace(lang, "skills", skills)
        write_namespace(lang, "plugins", plugins)
    print(f"Generated unified i18n resources for {len(langs)} languages")

if __name__ == "__main__":
    main()

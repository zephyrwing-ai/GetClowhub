import Foundation
import Combine
import Sparkle

@MainActor
final class SparkleUpdater: ObservableObject {
    private let feedDelegate = LocaleAwareFeedDelegate()
    private let updaterController: SPUStandardUpdaterController
    private var hasCheckedLatestVersionThisLaunch = false

    @Published var isCheckingVersion = false
    @Published var updateAvailable = false
    @Published var latestVersion: String = ""
    @Published var checkSucceeded = false

    /// Same URL Sparkle uses for the actual update flow. Computed at access
    /// time so locale changes between launches (e.g. user moved region) take
    /// effect on next check.
    private var appcastURL: String {
        return LocaleAwareFeedDelegate.resolveAppcastURL()
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        print("[SparkleUpdater] checkForUpdates called, canCheck=\(updaterController.updater.canCheckForUpdates)")
        print("[SparkleUpdater] feedURL=\(updaterController.updater.feedURL?.absoluteString ?? "nil")")
        updaterController.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    func checkLatestVersionOnLaunch() async {
        guard !hasCheckedLatestVersionThisLaunch else { return }
        hasCheckedLatestVersionThisLaunch = true
        await checkLatestVersion(showSuccessPulse: false)
    }

    /// Fetch appcast.xml and compare versions.
    func checkLatestVersion(showSuccessPulse: Bool = true) async {
        guard !isCheckingVersion else { return }
        isCheckingVersion = true
        updateAvailable = false
        checkSucceeded = false

        defer { isCheckingVersion = false }

        guard let url = URL(string: appcastURL) else { return }

        do {
            // Use a no-cache request to avoid stale responses
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let parser = AppcastParser()
            if let remoteVersion = parser.parseVersion(from: data) {
                latestVersion = remoteVersion
                if compareVersions(remoteVersion, isNewerThan: currentVersion) {
                    updateAvailable = true
                } else if showSuccessPulse {
                    checkSucceeded = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        checkSucceeded = false
                    }
                }
            }
        } catch {
            print("[SparkleUpdater] checkLatestVersion error: \(error)")
        }
    }

    /// Simple version comparison: "1.2.0" > "1.1.0"
    private func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }
}

// MARK: - Locale-aware Sparkle feed-URL delegate

/// Returns a different appcast URL based on the user's region:
///   - Mainland China (`region == "CN"`) → `appcast-cn.xml` whose
///     `<enclosure url>` points to Aliyun OSS Hangzhou. ~5MB/s+ vs
///     GitHub Releases' frequent <100 KB/s for a 264 MB DMG.
///   - Otherwise → standard `appcast.xml` whose enclosure points to
///     GitHub Releases.
///
/// We pick by *region* not language: a Chinese user living in HK/TW/SG/US
/// has region != CN and routes through GitHub fine; an English-system user
/// physically in mainland China has region=CN and benefits from the OSS
/// mirror. The DMG itself is byte-identical with one EdDSA signature, so
/// the choice of mirror doesn't affect signature verification.
private final class LocaleAwareFeedDelegate: NSObject, SPUUpdaterDelegate {
    static func resolveAppcastURL() -> String {
        let region = Locale.current.region?.identifier.uppercased() ?? ""
        if region == "CN" {
            return "https://firewolf189.github.io/GetClowhub/appcast-cn.xml"
        }
        return "https://firewolf189.github.io/GetClowhub/appcast.xml"
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        return Self.resolveAppcastURL()
    }
}

// MARK: - Appcast XML Parser

/// Minimal parser that extracts sparkle:shortVersionString from appcast.xml.
private class AppcastParser: NSObject, XMLParserDelegate {
    private var foundVersion: String?
    private var isReadingVersion = false
    private var versionBuffer = ""

    func parseVersion(from data: Data) -> String? {
        let parser = XMLParser(data: data)
        // Disable namespace processing so "sparkle:shortVersionString"
        // appears as the raw element name rather than being split.
        parser.shouldProcessNamespaces = false
        parser.delegate = self
        parser.parse()
        return foundVersion
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "sparkle:shortVersionString" && foundVersion == nil {
            isReadingVersion = true
            versionBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isReadingVersion {
            versionBuffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "sparkle:shortVersionString" && isReadingVersion {
            isReadingVersion = false
            let version = versionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty {
                foundVersion = version
            }
        }
    }
}

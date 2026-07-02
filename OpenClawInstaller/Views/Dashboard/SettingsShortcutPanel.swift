import SwiftUI
import AppKit

private enum SettingsShortcutPanelMetrics {
    static let width: CGFloat = 320
    static let minHeight: CGFloat = 120
    static let maxHeight: CGFloat = 560
    static let cornerRadius: CGFloat = 22
    static let horizontalWindowInset: CGFloat = 12
    static let verticalWindowInset: CGFloat = 10
    static let sidebarTrailingInset: CGFloat = 12

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private enum SettingsShortcutColors {
    static let primaryText = SwiftUI.Color(red: 0.10, green: 0.12, blue: 0.16)
    static let secondaryText = SwiftUI.Color(red: 0.36, green: 0.40, blue: 0.48)
    static let tertiaryText = SwiftUI.Color(red: 0.55, green: 0.59, blue: 0.66)
    static let glassBase = SwiftUI.Color.white.opacity(0.74)
    static let glassHighlight = SwiftUI.Color.white.opacity(0.48)
    static let glassEdge = SwiftUI.Color.white.opacity(0.66)
    static let glassShadow = SwiftUI.Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.18)
    static let cardFill = SwiftUI.Color.white.opacity(0.50)
    static let cardStroke = SwiftUI.Color.white.opacity(0.58)
}

struct SettingsShortcutPanelButton: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isActive: Bool
    let highlightColor: (Bool) -> SwiftUI.Color
    let onBeforeToggle: () -> Void
    let onOpenSettingsSection: (SettingsPageSection) -> Void
    @State private var isPanelPresented = false

    var body: some View {
        Button {
            onBeforeToggle()
            isPanelPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
                Text(I18n.t("Settings"))
                    .lineLimit(1)
                Spacer()
            }
            .font(DashboardTypography.sidebarRow)
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlightColor(isPanelPresented || isActive))
            )
        }
        .buttonStyle(.plain)
        .background(alignment: .trailing) {
            SettingsShortcutPanelHost(
                isPresented: $isPanelPresented,
                viewModel: viewModel,
                onOpenSettingsSection: onOpenSettingsSection
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
    }
}

private struct SettingsShortcutPanelHost: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenSettingsSection: (SettingsPageSection) -> Void
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let presentation = $isPresented
        let menu = SettingsShortcutMenu(
            viewModel: viewModel,
            onSizeChange: { size in
                context.coordinator.updateContentSize(size)
            },
            onDismiss: {
                presentation.wrappedValue = false
            },
            onOpenSettingsSection: { section in
                presentation.wrappedValue = false
                onOpenSettingsSection(section)
            }
        )
        .frame(width: 320)

        #if REQUIRE_LOGIN
        let rootView = AnyView(
            menu
                .environmentObject(authManager)
                .environmentObject(membershipManager)
        )
        #else
        let rootView = AnyView(menu)
        #endif

        context.coordinator.update(
            rootView: rootView,
            isPresented: isPresented,
            onClose: {
                presentation.wrappedValue = false
            },
            relativeTo: nsView
        )
    }

    func makeCoordinator() -> SettingsShortcutPanelCoordinator {
        SettingsShortcutPanelCoordinator()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: SettingsShortcutPanelCoordinator) {
        coordinator.closeImmediately(updateBinding: false)
    }
}

private final class SettingsShortcutPanelCoordinator {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var pendingPresentWork: DispatchWorkItem?
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var onClose: () -> Void = {}
    private weak var sourceView: NSView?
    private var lastContentSize: CGSize = .zero

    func update(
        rootView: AnyView,
        isPresented: Bool,
        onClose: @escaping () -> Void,
        relativeTo sourceView: NSView
    ) {
        self.onClose = onClose
        self.sourceView = sourceView

        if isPresented {
            let panel = ensurePanel(rootView: rootView)
            hostingController?.rootView = rootView
            resizePanel(panel)
            schedulePresent(relativeTo: sourceView)
        } else {
            if let hostingController {
                hostingController.rootView = rootView
            }
            closeImmediately(updateBinding: false)
        }
    }

    func updateContentSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard abs(size.width - lastContentSize.width) > 0.5 ||
                abs(size.height - lastContentSize.height) > 0.5 else { return }
        lastContentSize = size

        guard let panel else { return }
        let height = constrainedPanelHeight(for: size.height)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        panel.setContentSize(NSSize(width: SettingsShortcutPanelMetrics.width, height: height))
        if let sourceView, panel.isVisible {
            panel.setFrame(panelFrame(relativeTo: sourceView), display: true)
        }
    }

    func closeImmediately(updateBinding: Bool = true) {
        pendingPresentWork?.cancel()
        pendingPresentWork = nil
        removeEventMonitors()
        panel?.orderOut(nil)
        if updateBinding {
            onClose()
        }
    }

    private func ensurePanel(rootView: AnyView) -> NSPanel {
        if let panel {
            return panel
        }

        let controller = NSHostingController(rootView: rootView)
        hostingController = controller

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: SettingsShortcutPanelMetrics.width, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = controller
        self.panel = panel
        return panel
    }

    private func resizePanel(_ panel: NSPanel) {
        guard let hostingController else { return }
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: SettingsShortcutPanelMetrics.width, height: CGFloat.greatestFiniteMagnitude)
        )
        let height = constrainedPanelHeight(for: fittingSize.height)
        panel.setContentSize(NSSize(width: SettingsShortcutPanelMetrics.width, height: height))
    }

    private func schedulePresent(relativeTo sourceView: NSView) {
        pendingPresentWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView, let panel = self.panel else { return }
            guard sourceView.window != nil, !sourceView.bounds.isEmpty else { return }
            self.resizePanel(panel)
            panel.setFrame(self.panelFrame(relativeTo: sourceView), display: true)
            panel.orderFrontRegardless()
            self.installEventMonitors()
        }
        pendingPresentWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func panelFrame(relativeTo sourceView: NSView) -> NSRect {
        guard let window = sourceView.window, let panel else {
            return NSRect(x: 0, y: 0, width: SettingsShortcutPanelMetrics.width, height: 360)
        }

        let sourceFrameInWindow = sourceView.convert(sourceView.bounds, to: nil)
        let sourceFrameOnScreen = window.convertToScreen(sourceFrameInWindow)
        let sidebarMaxX = sourceFrameOnScreen.maxX + SettingsShortcutPanelMetrics.sidebarTrailingInset
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let windowFrameOnScreen = window.frame.intersection(screenFrame)
        let constraintFrame = windowFrameOnScreen.isEmpty ? screenFrame : windowFrameOnScreen
        let availableHeight = max(
            SettingsShortcutPanelMetrics.minHeight,
            constraintFrame.height - (SettingsShortcutPanelMetrics.verticalWindowInset * 2)
        )
        let panelHeight = min(panel.frame.height, availableHeight)
        if abs(panel.frame.height - panelHeight) > 0.5 {
            panel.setContentSize(NSSize(width: SettingsShortcutPanelMetrics.width, height: panelHeight))
        }
        let desiredY = sourceFrameOnScreen.maxY - panelHeight
        let y = max(
            constraintFrame.minY + SettingsShortcutPanelMetrics.verticalWindowInset,
            min(desiredY, constraintFrame.maxY - panelHeight - SettingsShortcutPanelMetrics.verticalWindowInset)
        )

        return NSRect(x: sidebarMaxX, y: y, width: SettingsShortcutPanelMetrics.width, height: panelHeight)
    }

    private func constrainedPanelHeight(for contentHeight: CGFloat) -> CGFloat {
        let availableHeight: CGFloat
        if let sourceView, let window = sourceView.window {
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let windowFrameOnScreen = window.frame.intersection(screenFrame)
            let constraintFrame = windowFrameOnScreen.isEmpty ? screenFrame : windowFrameOnScreen
            availableHeight = constraintFrame.height - (SettingsShortcutPanelMetrics.verticalWindowInset * 2)
        } else {
            availableHeight = SettingsShortcutPanelMetrics.maxHeight
        }
        return min(
            max(contentHeight, SettingsShortcutPanelMetrics.minHeight),
            min(SettingsShortcutPanelMetrics.maxHeight, max(SettingsShortcutPanelMetrics.minHeight, availableHeight))
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) && !self.sourceFrameOnScreen.contains(mouseLocation) {
                self.closeImmediately()
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeImmediately()
        }
    }

    private func removeEventMonitors() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private var sourceFrameOnScreen: NSRect {
        guard let sourceView, let window = sourceView.window else { return .zero }
        return window.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
    }
}

private struct SettingsShortcutMenu: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onSizeChange: (CGSize) -> Void
    let onDismiss: () -> Void
    let onOpenSettingsSection: (SettingsPageSection) -> Void
    @State private var isBillingExpanded = false
    @State private var isBudgetExpanded = false
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                accountHeader

                SettingsShortcutActionRow(title: I18n.t("Profile"), systemImage: "person.crop.circle") {
                    onOpenSettingsSection(.profile)
                }

                Divider()

                DefaultModelShortcutPicker(viewModel: viewModel) {
                    onOpenSettingsSection(.provider)
                }

                #if REQUIRE_LOGIN
                BillingShortcutSummary(
                    isExpanded: $isBillingExpanded,
                    membershipManager: membershipManager
                )
                #endif

                BudgetShortcutSummary(
                    isExpanded: $isBudgetExpanded,
                    viewModel: viewModel,
                    onOpenBudget: { onOpenSettingsSection(.budget) }
                )

                Divider()

                SettingsShortcutActionRow(title: I18n.t("All settings"), systemImage: "gearshape") {
                    onOpenSettingsSection(.profile)
                }

                #if REQUIRE_LOGIN
                Button {
                    if authManager.isLoggedIn {
                        authManager.logout()
                    } else {
                        authManager.login()
                    }
                    onDismiss()
                } label: {
                    SettingsShortcutRowContent(
                        title: authManager.isLoggedIn ? I18n.t("Log out") : I18n.t("Log in"),
                        systemImage: authManager.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.badge.plus",
                        showsTrailingChevron: false,
                        role: authManager.isLoggedIn ? .destructive : .normal
                    )
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(14)
        }
        .scrollIndicators(.automatic)
        .frame(width: SettingsShortcutPanelMetrics.width, alignment: .leading)
        .frame(maxHeight: SettingsShortcutPanelMetrics.maxHeight)
        .clipShape(SettingsShortcutPanelMetrics.panelShape)
        .background(SettingsShortcutLiquidDropBackground(cornerRadius: SettingsShortcutPanelMetrics.cornerRadius))
        .foregroundStyle(SettingsShortcutColors.primaryText)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SettingsShortcutSizeKey.self, value: proxy.size)
            }
            .allowsHitTesting(false)
        )
        .onPreferenceChange(SettingsShortcutSizeKey.self) { size in
            onSizeChange(size)
        }
        .task {
            if viewModel.models.isEmpty {
                await viewModel.loadModels()
            }
            if viewModel.budgetSnapshots.isEmpty {
                await viewModel.loadBudgets()
            }
            #if REQUIRE_LOGIN
            if membershipManager.keysBilling.isEmpty {
                await viewModel.loadKeysBilling()
            }
            #endif
        }
    }

    @ViewBuilder
    private var accountHeader: some View {
        #if REQUIRE_LOGIN
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(SettingsShortcutColors.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsShortcutColors.primaryText)
                        .lineLimit(1)
                    Text(authManager.isLoggedIn ? I18n.t("Signed in") : I18n.t("Not signed in"))
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsShortcutColors.secondaryText)
                }

            Spacer()

            if let membership = membershipManager.membership {
                Text(membership.level.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(membershipBadgeColor(membership.level))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(membershipBadgeColor(membership.level).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        #else
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(SettingsShortcutColors.secondaryText)
                Text(I18n.t("Local user"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsShortcutColors.primaryText)
                Spacer()
            }
        #endif
    }

    #if REQUIRE_LOGIN
    private var accountDisplayName: String {
        if let email = authManager.userEmail, !email.isEmpty {
            return email
        }
        if case .loggedIn(let nickname) = authManager.state, !nickname.isEmpty {
            return nickname
        }
        if let userId = authManager.userId, !userId.isEmpty {
            return userId
        }
        return I18n.t("User")
    }

    private func membershipBadgeColor(_ level: MembershipLevel) -> SwiftUI.Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .purple
        }
    }
    #endif
}

private struct SettingsShortcutActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsShortcutRowContent(
                title: title,
                systemImage: systemImage,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsShortcutSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private enum SettingsShortcutRowRole {
    case normal
    case destructive
}

private struct SettingsShortcutRowContent: View {
    let title: String
    let systemImage: String
    var showsChevron = false
    var showsTrailingChevron = true
    var isExpanded = false
    var role: SettingsShortcutRowRole = .normal

    var body: some View {
        HStack(spacing: 10) {
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SettingsShortcutColors.secondaryText)
                        .frame(width: 10)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }

            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundStyle(rowForegroundStyle)

            Text(title)
                .foregroundStyle(rowForegroundStyle)

            Spacer()

                if !showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SettingsShortcutColors.tertiaryText)
                        .opacity(showsTrailingChevron ? 1 : 0)
                }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

        private var rowForegroundStyle: SwiftUI.Color {
            switch role {
            case .normal: return SettingsShortcutColors.primaryText
            case .destructive: return .red
            }
        }
}

private struct DefaultModelShortcutPicker: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenProvider: () -> Void

    private var selectedModelID: String {
        if let current = viewModel.models.first(where: \.isDefault)?.modelId {
            return current
        }
        return viewModel.modelOverview.defaultModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(I18n.t("Model"), systemImage: "cube")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsShortcutColors.primaryText)
                Spacer()
                Button(I18n.t("Configure")) {
                    onOpenProvider()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(SettingsShortcutColors.secondaryText)
            }

            if viewModel.models.isEmpty {
                Text(I18n.t("No models loaded"))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsShortcutColors.secondaryText)
            } else {
                Picker("", selection: Binding<String>(
                    get: { selectedModelID },
                    set: { modelID in
                        guard let model = viewModel.models.first(where: { $0.modelId == modelID }) else { return }
                        Task { await viewModel.setDefaultModel(model) }
                    }
                )) {
                    ForEach(viewModel.models, id: \.modelId) { model in
                        Text(model.modelId).tag(model.modelId)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsShortcutColors.cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.36),
                                    Color.white.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(SettingsShortcutColors.cardStroke, lineWidth: 1)
                }
        )
    }
}

#if REQUIRE_LOGIN
private struct BillingShortcutSummary: View {
    @Binding var isExpanded: Bool
    @ObservedObject var membershipManager: MembershipManager

    private var totalSpend: Double {
        membershipManager.keysBilling.reduce(0) { $0 + $1.spend }
    }

    private var totalBudget: Double? {
        let budgets = membershipManager.keysBilling.compactMap(\.maxBudget)
        guard !budgets.isEmpty else { return nil }
        return budgets.reduce(0, +)
    }

    private var percent: Double {
        guard let totalBudget, totalBudget > 0 else { return 0 }
        return min(totalSpend / totalBudget, 1)
    }

    var body: some View {
        SettingsShortcutExpandableRow(
            title: I18n.t("Billing"),
            systemImage: "creditcard",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(String(format: "$%.2f", totalSpend))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    if let totalBudget {
                        Text("/ $\(String(format: "%.2f", totalBudget))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SettingsShortcutColors.secondaryText)
                    }
                    Spacer()
                }

                if totalBudget != nil {
                    ProgressView(value: percent)
                }

                    if membershipManager.keysBilling.isEmpty {
                        Text(I18n.t("No billing data yet"))
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsShortcutColors.secondaryText)
                    }
            }
        }
    }
}
#endif

private struct BudgetShortcutSummary: View {
    @Binding var isExpanded: Bool
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenBudget: () -> Void

    private var globalSnapshot: BudgetSnapshot? {
        viewModel.budgetSnapshots.first(where: { $0.scope == .global })
    }

    var body: some View {
        SettingsShortcutExpandableRow(
            title: I18n.t("Budget"),
            systemImage: "dollarsign.gauge.chart.lefthalf.righthalf",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 7) {
                if let snapshot = globalSnapshot {
                    HStack {
                        Text(formatTokenCount(snapshot.tokensUsed))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        if snapshot.tokenLimit > 0 {
                            Text("/ \(formatTokenCount(snapshot.tokenLimit))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(SettingsShortcutColors.secondaryText)
                        }
                        Spacer()
                    }
                    if snapshot.tokenLimit > 0 {
                        ProgressView(value: min(snapshot.tokenPercent, 1))
                    }
                } else {
                    Text(I18n.t("No local budget rule"))
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsShortcutColors.secondaryText)
                }

                Button(I18n.t("Edit budget rules")) {
                    onOpenBudget()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(SettingsShortcutColors.secondaryText)
            }
        }
    }

    private func formatTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

private struct SettingsShortcutExpandableRow<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                SettingsShortcutRowContent(
                    title: title,
                    systemImage: systemImage,
                    showsChevron: true,
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    content()
                        .padding(.leading, 34)
                        .padding(.trailing, 8)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
    }
}

private struct SettingsShortcutLiquidDropBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(SettingsShortcutColors.glassBase)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SettingsShortcutColors.glassHighlight,
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.60),
                                Color.white.opacity(0.20),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.18, y: 0.12),
                            startRadius: 4,
                            endRadius: 190
                        )
                    )
                    .blendMode(.plusLighter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.82, y: 0.18),
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                SettingsShortcutColors.glassEdge,
                                Color.white.opacity(0.28),
                                Color(red: 0.30, green: 0.34, blue: 0.42).opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: SettingsShortcutColors.glassShadow, radius: 22, x: 0, y: 12)
            .shadow(color: Color.white.opacity(0.34), radius: 1, x: 0, y: 1)
    }
}

#if REQUIRE_LOGIN
import SwiftUI

struct BillingTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var membershipManager: MembershipManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                OfficialServiceBillingSection(viewModel: viewModel, membershipManager: membershipManager)
            }
            .padding(24)
        }
        .task {
            await viewModel.loadKeysBilling()
        }
    }
}

// MARK: - Official Service Billing Section

struct OfficialServiceBillingSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var membershipManager: MembershipManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack {
                Label(String(localized: "billing.title", defaultValue: "GetClawHub Official Service", bundle: LanguageManager.shared.localizedBundle), systemImage: "cloud.fill")
                    .font(.headline)

                Spacer()

                Button(action: {
                    Task { await viewModel.loadKeysBilling() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(String(localized: "billing.refresh", defaultValue: "Refresh Billing", bundle: LanguageManager.shared.localizedBundle))
            }

            // Membership info
            if let membership = membershipManager.membership {
                HStack(spacing: 12) {
                    Text(membership.level.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(membershipBadgeColor(membership.level).opacity(0.15))
                        .foregroundColor(membershipBadgeColor(membership.level))
                        .cornerRadius(6)

                    if let expiresAt = membership.expiresAt {
                        Text("Expires \(expiresAt, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }

            Divider()

            // Key billing cards
            if membershipManager.isBillingLoading {
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(0.8)
                    Text(String(localized: "billing.loading", defaultValue: "Loading billing data...", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(minHeight: 60)
            } else if !membershipManager.keysBilling.isEmpty {
                VStack(spacing: 10) {
                    ForEach(membershipManager.keysBilling) { billing in
                        KeyBillingCard(billing: billing, membershipModels: membershipManager.membership?.models ?? [])
                    }
                }
            } else {
                Text(String(localized: "billing.empty", defaultValue: "No active API keys. Create one from the membership panel to see billing info here.", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func membershipBadgeColor(_ level: MembershipLevel) -> Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .red
        }
    }
}

// MARK: - Key Billing Card

struct KeyBillingCard: View {
    let billing: KeyBillingInfo
    let membershipModels: [String]

    private var displayModels: [String] {
        membershipModels.isEmpty ? billing.models : membershipModels
    }

    private var spendPercent: Double {
        guard let max = billing.maxBudget, max > 0 else { return 0 }
        return min(billing.spend / max, 1.0)
    }

    private var spendStatus: BudgetStatus {
        if spendPercent >= 1.0 { return .over }
        if spendPercent >= 0.8 { return .warn }
        return .ok
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header: alias + masked key ──
            HStack(alignment: .center) {
                Text(billing.displayName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                Text(billing.key)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.separatorColor).opacity(0.3))
                    .cornerRadius(4)
            }
            .padding(.bottom, 10)

            // ── Spend bar ──
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "$%.2f", billing.spend))
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)

                    if let max = billing.maxBudget {
                        Text("/ $\(String(format: "%.2f", max))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text("(\(Int(spendPercent * 100))%)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(spendStatusColor)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(spendStatusColor)
                            .frame(width: 8, height: 8)
                        Text(LocalizedStringKey(spendStatus.label))
                            .font(.caption)
                            .foregroundColor(spendStatusColor)
                    }
                }

                if billing.maxBudget != nil {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.separatorColor).opacity(0.4))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(spendStatusColor)
                                .frame(width: max(0, geo.size.width * spendPercent), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(.bottom, 10)

            Divider()
                .padding(.bottom, 8)

            // ── Info grid: 2 columns ──
            HStack(alignment: .top, spacing: 24) {
                // Left column: limits
                VStack(alignment: .leading, spacing: 6) {
                    billingInfoRow(icon: "speedometer", label: String(localized: "billing.rpm", defaultValue: "RPM", bundle: LanguageManager.shared.localizedBundle),
                                   value: billing.rpmLimit.map { "\($0)" } ?? "—")
                    if let duration = billing.budgetDuration {
                        billingInfoRow(icon: "arrow.trianglehead.2.clockwise", label: String(localized: "billing.period", defaultValue: "Period", bundle: LanguageManager.shared.localizedBundle),
                                       value: duration)
                    }
                }

                Divider()
                    .frame(height: 50)

                // Right column: dates
                VStack(alignment: .leading, spacing: 6) {
                    if let createdAt = billing.createdAt {
                        billingDateRow(icon: "calendar.badge.plus", label: String(localized: "billing.created", defaultValue: "Created", bundle: LanguageManager.shared.localizedBundle),
                                       date: createdAt)
                    }
                }

                Spacer()
            }
            .padding(.bottom, 10)

            // ── Models tags ──
            if !displayModels.isEmpty {
                Divider()
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "billing.models", defaultValue: "Models", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    FlowLayout(spacing: 4) {
                        ForEach(displayModels, id: \.self) { model in
                            Text(model)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(spendStatus != .ok ? spendStatusColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Row Helpers

    private func billingInfoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundColor(.secondary)
            Text(label)
                .foregroundColor(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }

    private func billingDateRow(icon: String, label: String, date: Date, color: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundColor(color)
            Text(label)
                .foregroundColor(.secondary)
            Text(date, style: .date)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .font(.caption)
    }

    private var spendStatusColor: Color {
        switch spendStatus {
        case .ok: return .green
        case .warn: return .orange
        case .over: return .red
        }
    }
}
#endif

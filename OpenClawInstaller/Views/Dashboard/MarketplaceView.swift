import SwiftUI

struct MarketplaceView: View {
    let selectedAgent: MarketplaceAgent?
    let installRefreshID: Int
    let onSelectAgent: (MarketplaceAgent) -> Void

    var body: some View {
        MarketplaceOverviewView(
            selectedAgent: selectedAgent,
            installRefreshID: installRefreshID,
            onSelect: onSelectAgent
        )
    }
}

## Why

The completed Codex-style chat changes still leave visible UI mismatches: the empty New chat composer remains bottom-aligned, chat bubble backgrounds are too subtle, divider/anchor lines visually cross the layout, and agent/model selection is not available from the composer in the requested form. This change turns the prior broad redesign into a stricter visual and interaction polish pass that matches the referenced Codex-like screenshots.

## What Changes

- Center the New chat empty-state title and composer in the main chat panel when the selected session has no messages.
- Keep scroll anchors and scroll affordances inside the chat panel only; they must not draw lines across or through the left sidebar.
- Remove unwanted standalone divider lines at the top of the chat area and near the lower-left input/sidebar boundary.
- Restore visible gray chat bubble backgrounds using a Codex-like rounded light-gray treatment for user and assistant messages.
- Tighten chat bubble corner radii so user and assistant bubbles read as lightly rounded panels instead of large pills.
- Add a compact composer agent/model selector that displays the selected agent and model as a combined label such as `UX · GPT-5.5 v`.
- Implement the selector as a custom nested panel: agent options in the primary panel and model options revealed directly through a `Model >` row in an adjacent panel.
- Add a fixed top-right panel control for Outputs/workspace-style panel access, matching the referenced icon placement, independent of scroll-anchor state.
- Animate the panel control's expand/collapse behavior smoothly instead of snapping open or closed.
- Expand Outputs from the fixed top-right control into a real right-sidebar layout column when open, but remove the right-side collapsed strip entirely when closed.
- Remove the trailing narrow Outputs toolbar/strip shown at the far-right edge; the closed state must leave no right-side column, divider, folder icon, or sidebar icon.
- Use the top-right Outputs button as the explicit click affordance; do not expand the Outputs sidebar on hover.
- Keep the chat message and composer width stable when the left sidebar changes or Outputs opens/closes; the chat column should recenter inside the remaining space instead of stretching wider.
- Remove the top-left sidebar brand icon so the header does not show the logo mark.
- Show the active chat session title near the left edge of the main chat panel whenever the selected session already has a non-empty name.
- Show a delete affordance on the right side of hovered chat-session rows instead of a hover state that implies expandable behavior.
- Keep the composer position stable when the user opens the agent/model selector; selector panels must float without changing the composer card's layout height.
- Localize sidebar and chrome labels according to the active app language, while preserving chat message content as originally authored.
- Remove the left-sidebar `Outputs` navigation entry and rely on the fixed top-right panel control for Outputs/workspace access.
- Add a localized `Market` navigation entry under `Automation` for the existing marketplace/expert-team surface.
- Remove the global top divider line that spans across the sidebar/main-panel boundary.
- Reduce the vertical gutter above the first visible chat message so the top anchor/header area feels more compact.
- Group provider settings into a single `Gateway` settings section with the Gateway heading at the top.
- Preserve existing chat sending, message persistence, model update, agent switching, attachments, and non-chat tab behavior.

## Capabilities

### New Capabilities
- `codex-chat-composer-polish`: Covers centered New chat composition, chat bubble gray styling, contained scroll anchors/divider removal, composer agent/model selection, fixed animated panel controls without a closed-state right strip, sidebar header icon removal, localized sidebar navigation, marketplace entry placement, and gateway settings grouping.

### Modified Capabilities

None. There are no existing archived OpenSpec capabilities in `openspec/specs/`; this change creates a new capability delta for the active project state.

## Impact

- Affects `OpenClawInstaller/Views/Dashboard/DashboardView.swift` for chat layout, bubble styling, session-row hover actions, chat header/title placement, scroll-anchor containment, stable centered chat width, right-sidebar Outputs column placement, and removal of the closed-state right strip.
- May affect `OpenClawInstaller/ViewModels/DashboardViewModel.swift` if a narrow helper is needed for composer-driven model switching or panel state.
- May affect `OpenClawInstaller/Localizable.xcstrings` if new visible labels or accessibility/help strings are introduced.
- Affects `OpenClawInstaller/Views/Dashboard/ConfigTabView.swift` for the grouped Gateway settings layout.
- Does not change backend chat/session APIs, stored conversation format, or OpenClaw service behavior.

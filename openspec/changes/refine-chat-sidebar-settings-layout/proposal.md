## Why

The chat UI still exposes too much configuration chrome in the main navigation and uses strong blue message bubbles that compete with the content. The next pass should make the sidebar, chat messages, Outputs entry, and Settings page quieter and more focused.

## What Changes

- Change chat message bubbles to use gray backgrounds instead of blue user bubbles.
- Make selected left-sidebar rows use a gray selected background.
- Reorder the App Sidebar to: New chat, Search, Skills, Plugins, Automation, Outputs, conversation history, Status, Budget, Billing, Settings.
- Remove the top-level Chat section/header and avoid exposing Persona as a primary sidebar item.
- Move Outputs into the App Sidebar as a navigation entry.
- Remove Help from the lower-left sidebar controls.
- Remove the top chat Workspace-only header and its divider line.
- Keep Settings as a single page with card/grid sections, not a nested settings sidebar.
- Move profile, language, logout, and persona entry points into Settings.
- Remove provider model-list display from Settings.

## Capabilities

### New Capabilities
- `sidebar-chat-settings-refinement`: Defines the refined sidebar order, Outputs navigation placement, gray chat/selection styling, and Settings page content grouping.

### Modified Capabilities

None.

## Impact

- Affects `OpenClawInstaller/Views/Dashboard/DashboardView.swift` for sidebar layout, chat header removal, Outputs navigation, and message bubble styling.
- Affects `OpenClawInstaller/Views/Dashboard/ConfigTabView.swift` for Settings page structure and provider model list removal.
- May affect `OpenClawInstaller/ViewModels/DashboardViewModel.swift` if a dedicated Outputs tab is needed.
- No backend, storage, or dependency changes are expected.

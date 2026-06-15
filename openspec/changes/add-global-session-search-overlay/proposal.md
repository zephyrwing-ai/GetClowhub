## Why

The current sidebar search behavior is unclear and the attempted global search overlay is split between `DashboardView` and `SidebarView`, causing Swift scope build failures. Users need one obvious search entry that opens a centered modal-style panel for searching chats across all agents and sessions, matching the referenced Codex search experience.

## What Changes

- Make the left-sidebar `Search` row open a centered global chat-search overlay instead of navigating to a page or performing sidebar-local search.
- Keep the overlay owned by `DashboardView` so it can cover the full split view and dim the entire window behind it.
- Show an input at the top of the overlay and list recent chats when the query is empty.
- Filter all unarchived chat sessions across agents as the user types, with newest matching sessions first.
- Selecting a result switches to that chat session, switches the main tab to chat, and dismisses the overlay.
- Remove duplicate overlay/search state from `SidebarView` so the build has a single source of truth for global search state.

## Capabilities

### New Capabilities
- `global-session-search-overlay`: Covers a centered full-window overlay for global chat-session search, including sidebar entry behavior, result filtering, selection behavior, and ownership boundaries.

### Modified Capabilities

None. There are no existing archived OpenSpec capabilities in `openspec/specs/`; this change creates a new capability for the active project state.

## Impact

- Affects `OpenClawInstaller/Views/Dashboard/DashboardView.swift` for overlay ownership, sidebar trigger wiring, modal layout, focus, dismissal, and result-row rendering.
- Uses existing `DashboardViewModel.switchSessionGlobally(to:)` and `ChatSessionStore.searchSessions(query:)` behavior for selection and filtering.
- May affect `OpenClawInstaller/Localizable.xcstrings` only if new visible labels are introduced.
- Affects verification scripts under `scripts/` for overlay ownership and global session search behavior.
- Does not change chat persistence format, backend APIs, gateway behavior, or non-chat tab behavior.

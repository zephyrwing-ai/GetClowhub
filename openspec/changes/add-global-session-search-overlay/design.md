## Context

The app already has the data path needed for global chat search: `ChatSessionStore.searchSessions(query:)` returns sessions across agents and `DashboardViewModel.switchSessionGlobally(to:)` can switch to a selected session. The current implementation attempt places the same global-search overlay code in both `DashboardView` and `SidebarView`. `DashboardView` owns the required `@State` and `@FocusState`, while `SidebarView` does not, so Xcode fails with `Cannot find 'globalSessionSearchText' in scope` and related errors.

The requested interaction matches the provided Codex screenshot: clicking `Search` in the left sidebar opens a centered, modal-style panel over the whole window. The panel has a search field at the top, recent chats or filtered results below, shortcut hints on rows, and a dimmed background behind it.

## Goals / Non-Goals

**Goals:**
- Make the sidebar `Search` row open a centered global session-search overlay.
- Keep all global-search presentation, query text, and focus state owned by `DashboardView`.
- Keep `SidebarView` as a trigger-only component that calls `onOpenGlobalSessionSearch`.
- Search unarchived sessions across all agents using the existing store.
- Switch to the selected chat and dismiss the overlay when a result row is selected.
- Remove duplicate `SidebarView` overlay code that causes the current Xcode build failure.
- Verify the behavior with the existing global-search and overlay-placement scripts plus an Xcode build.

**Non-Goals:**
- Do not change chat-session persistence format.
- Do not add a new search backend or ranking system.
- Do not redesign the entire sidebar or chat composer.
- Do not add global keyboard shortcuts unless a later change explicitly requests them.

## Decisions

1. **Make `DashboardView` the only overlay owner.**
   - Rationale: `DashboardView` wraps the full `NavigationSplitView`, so an overlay attached there can cover both sidebar and detail content. It also already owns the `@State` and `@FocusState` needed by the search field.
   - Alternative considered: add duplicate state to `SidebarView`. Rejected because the overlay would be clipped to the sidebar column and would create a second source of truth.

2. **Keep `SidebarView` trigger-only.**
   - Rationale: The sidebar row should describe navigation chrome, not own modal state. Passing `onOpenGlobalSessionSearch` keeps the boundary simple and avoids scope leaks.
   - Alternative considered: pass bindings for all search state into `SidebarView`. Rejected because it couples the sidebar to modal internals without improving behavior.

3. **Use the existing session store and view-model switching APIs.**
   - Rationale: The current data model already supports cross-agent session search and global session switching. Reusing these APIs keeps the change UI-scoped.
   - Alternative considered: create a separate search view model. Rejected because the current feature only needs presentation state and existing store queries.

4. **Render the overlay as a centered SwiftUI panel.**
   - Rationale: The referenced UI is a modal search panel centered over dimmed content. A full-window overlay with a centered panel is the narrowest implementation that matches the requested behavior.
   - Alternative considered: keep the current top-aligned panel. Rejected because the user explicitly wants the screenshot-like centered popup.

## Risks / Trade-offs

- **Risk:** `DashboardView.swift` is large, and duplicate code can be easy to miss. -> Mitigation: use a verification script that fails if `SidebarView` still contains `globalSessionSearchOverlay`.
- **Risk:** A fixed panel width can overflow smaller windows. -> Mitigation: constrain the panel to the available geometry with horizontal padding.
- **Risk:** Build failures may be hidden by Xcode's issue list grouping. -> Mitigation: run command-line `xcodebuild` after the edit and report the first real compiler blocker if any remains.

## Migration Plan

1. Add/confirm failing verification for overlay ownership and placement.
2. Remove duplicate global-search computed views from `SidebarView`.
3. Center and constrain the `DashboardView` global-search overlay.
4. Run the global-search verification scripts.
5. Run an Xcode Debug build for the `OpenClawInstaller` scheme.

Rollback is limited to reverting the `DashboardView.swift` edits and this OpenSpec change if the UI direction changes.

## Open Questions

None. The user provided the visual target and confirmed the intended interaction.

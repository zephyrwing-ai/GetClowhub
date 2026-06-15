## Context

The active chat UI is partway through a Codex-style redesign. The prior OpenSpec changes marked the broad chat/sidebar cleanup complete, but the current app still shows several visual and interaction regressions:

- Empty `New chat` sessions show only the title in the center while the composer remains pinned to the bottom.
- Scroll-anchor or divider artifacts can appear as horizontal lines that visually continue through the left sidebar or lower-left boundary.
- Message bubbles use `controlBackgroundColor`, which is too close to the window background and makes the gray bubble treatment effectively disappear.
- The current bubble radius is too pill-shaped for the desired quieter desktop look.
- The former right-side model selector is no longer visible, but the requested composer-level agent/model switcher is not fully implemented.
- The Outputs/workspace-style panel control should be a stable top-right panel affordance, not a side effect of the chat scroll area or any scroll anchor.
- The current collapsed Outputs implementation leaves a narrow trailing toolbar/strip on the far-right edge. The requested closed state should have no right-side strip, icons, divider, or reserved width; only the fixed top-right panel button remains.
- The current right-side Outputs surface behaves like a floating overlay. It should participate in layout so the chat area moves horizontally instead of being covered.
- The chat message/composer column can become too wide and leave large visual dead zones. The desired behavior is a stable max-width chat column centered in the remaining space.
- Opening the composer agent/model selector can move the composer because selector panels participate in layout height instead of floating above it.
- Some visible chrome labels are hard-coded in one language and do not consistently follow the active app language.
- The marketplace/expert-team surface exists in the app but is not exposed through the requested left-sidebar `Market` entry under `Automation`.
- The left sidebar still exposes `Outputs`, even though Outputs should now be accessed through the top-right panel control.
- Chat sessions do not expose a direct hover-delete affordance in the sidebar, and the current hover affordance does not communicate a clear action.
- The active session title is not surfaced in the top-left area of the main chat panel after entering a named conversation.
- Provider settings are visually split into separate exposed cards instead of being grouped under a single `Gateway` settings section.
- A top-level divider/window chrome line can still span across the sidebar/main-panel boundary, separate from the chat scroll anchors.
- The top gutter above the first visible message still feels taller than necessary once the divider artifact is removed.
- The right workspace/sidebar behavior is still owned mostly inside `ChatView`, which makes it inconsistent with how the left sidebar participates in app-level layout and navigation state.
- The workspace browser still exposes agent configuration files such as `AGENTS.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md`, even though the requested workspace surface should focus on LLM output artifacts rather than agent authoring files.
- Agent creation already exists in the codebase, but it is not surfaced as a first-class left-sidebar category the way the user expects.
- Persisted chat sessions are still stored in one global app-support location rather than under each agent's own workspace directory.
- The UI currently has overlapping search affordances; the requested behavior is to keep only the session-search entry point and remove the redundant one.

The change should treat the reference screenshots as the visual target: quiet sidebar, contained main panel, centered empty composer, visible gray bubbles, fixed top-right panel control, smooth animated expansion/collapse, localized sidebar chrome, and grouped Gateway settings.

## Goals / Non-Goals

**Goals:**
- Render an empty `New chat` state with title and composer centered in the main chat panel.
- Keep all scroll-anchor behavior invisible and contained within the chat panel; no anchor/divider line may cross into the sidebar.
- Remove unwanted standalone horizontal lines at the top of chat and lower-left UI boundary.
- Make user and assistant message bubbles visibly gray with rounded Codex-like treatment.
- Tighten bubble corner radii so the message containers keep only a small amount of rounding.
- Add a composer-level combined agent/model control that reads like `UX · GPT-5.5 v`.
- Show agent options and model options through a custom adjacent nested panel using `Model >`, not a native system submenu.
- Add a fixed top-right panel control for Outputs/workspace panel access and animate its expansion/collapse smoothly.
- Use a right-sidebar Outputs surface only when Outputs is expanded; when Outputs is closed, remove the trailing strip entirely.
- Make the top-right Outputs control a click-only toggle; do not reveal the Outputs sidebar on hover.
- Keep message bubbles and the composer on a stable max-width chat column that recenters when the left sidebar changes or Outputs opens/closes.
- Remove the top-left sidebar logo/icon while preserving the sidebar header's spacing and text readability.
- Show the current session title near the left side of the chat panel header when the selected session has a non-empty title.
- Show a delete affordance on the right side of hovered chat-session rows.
- Keep the composer card fixed in place when agent/model selector panels open, close, or switch between agent and model lists.
- Ensure UI chrome follows the active app language, including sidebar labels and session-section labels; chat message content remains unchanged.
- Remove the left-sidebar `Outputs` entry and add a localized `Market` entry under `Automation`.
- Make the right-side Outputs/workspace panel expand from and collapse back toward the top-right control as a real layout column instead of a floating panel, returning to no visible right-side column when closed.
- Reduce the top gutter above the first chat message / anchor area so the timeline begins closer to the top chrome.
- Group provider configuration into one `Gateway` settings section with `Gateway` at the top.
- Remove the global top divider line that spans across the sidebar/main-panel boundary.
- Align the right workspace sidebar's state ownership and layout behavior with the left sidebar's app-shell treatment.
- Limit the workspace file browser to LLM output content and hide agent configuration markdown files from browse and search results.
- Add a left-sidebar `Agent` category that exposes existing agent selection and creation behavior directly in the primary navigation area.
- Store each agent's chat sessions under that agent's own workspace directory instead of one global chat-session directory.
- Keep only the session-search affordance in the chat sidebar and make clicking search focus the session search field for global session search.

**Non-Goals:**
- Do not change backend chat APIs, session storage, or gateway behavior.
- Do not redesign non-chat tabs.
- Do not add new image assets or decorative empty-state branding.
- Do not remove the underlying scroll-to-bottom behavior for active conversations.
- Do not replace the existing Outputs/workspace content implementation beyond the requested entry/control behavior.
- Do not expose agent persona/configuration markdown through the workspace output browser once dedicated agent-management surfaces already cover those files.

## Decisions

1. **Split empty-chat and timeline layouts inside `ChatView`.**
   - Rationale: `ChatView` already owns input text, attachments, sending, agent state, model state, terminal state, and file browser state. Keeping both layouts in the same view avoids duplicating send logic.
   - Empty sessions render a centered composition surface and do not instantiate the normal message `ScrollView` anchor structure.
   - Non-empty sessions keep the timeline and bottom composer.
   - Alternative considered: keep one layout and reposition the composer with spacers. Rejected because the normal timeline's scroll anchors and bottom composer behavior are the source of the current empty-state visual mismatch.

2. **Treat scroll anchors as invisible internal layout markers.**
   - Rationale: anchors are useful for auto-scroll and scroll-to-message behavior, but they must never become visible chrome.
   - Anchors stay inside the chat message content container and are only present when the message timeline is rendered.
   - Any visible line crossing into the sidebar is treated as a divider/background bug, not as an acceptable anchor representation.
   - Alternative considered: remove anchors entirely. Rejected because active conversations still need stable scroll-to-bottom behavior.

3. **Use explicit bubble styling instead of system control background color alone, with tighter corner radii.**
   - Rationale: `controlBackgroundColor` can visually merge with `windowBackgroundColor`, especially in light mode. The bubble background needs a deliberate gray value or dynamic color that remains visible in both light and dark appearances.
   - User bubbles and assistant bubbles can use the same family of gray treatment, with subtle role-specific contrast if needed.
   - The radius should read as a desktop panel corner, not as a mobile chat pill.
   - Markdown, code, media attachments, and plain text should all sit inside the same rounded bubble container.
   - Alternative considered: add only a border to the existing background. Rejected because the user's reference emphasizes a filled gray pill, not merely outlined text.

4. **Build the agent/model picker as a custom anchored overlay.**
   - Rationale: the requested interaction is visually nested but not a system pop-out menu. The `Model >` row should directly reveal an adjacent model panel while the primary agent panel remains open.
   - The composer trigger displays the current selection as a combined label: `Agent · Model v`.
   - Agent selection updates `selectedAgentId`; model selection uses existing model update behavior or a narrow ViewModel helper if needed.
   - Alternative considered: reuse native SwiftUI `Menu` with submenu. Rejected because native submenus pop out with system behavior and do not match the requested direct adjacent panel.

5. **Make the Outputs/workspace panel control fixed to the chat panel top-right and connect it to an open-only right layout column.**
   - Rationale: the reference places a panel icon in the top-right chrome of the main panel. It should be visible regardless of message scroll position, empty state, or scroll-anchor existence.
   - The control belongs to the main chat chrome, not to any single message row or scroll anchor.
   - Expand/collapse uses width interpolation between no visible right column and the expanded right sidebar column.
   - The closed state must not render a slim right strip, trailing toolbar, folder icon, sidebar icon, or divider at the far-right edge.
   - Hover must not expand the sidebar. The user explicitly requested click-driven behavior only.
   - Alternative considered: keep Outputs only as a sidebar navigation entry. Rejected because the user explicitly requested the fixed top-right panel affordance.

6. **Keep visual boundaries local and quiet.**
   - Rationale: the requested UI should not have orphan divider lines. Card borders are allowed only when they frame an actual component, such as the composer or a panel.
   - Top chat header dividers, stray lower-left lines, and lines that visually run through the sidebar are not acceptable.

7. **Remove the sidebar brand icon without changing navigation behavior.**
   - Rationale: the user wants the top-left icon gone. This is a visual simplification of the sidebar header, not a navigation or branding-data change.
   - Alternative considered: hide the entire header. Rejected because the sidebar still needs stable top spacing and the app title can remain useful.

8. **Make composer agent/model selector panels true overlays.**
   - Rationale: the composer card should not jump when the user chooses an agent or model. The selector's panels must be visually anchored to the composer control but excluded from the composer card's layout measurement.
   - Use overlay/z-index positioning with stable composer dimensions. Agent/model panels can animate opacity/scale, but they must not add vertical space above the composer card.
   - Alternative considered: reserve permanent space for selector panels. Rejected because it would make the empty state and bottom composer look unnecessarily tall even when no selector is open.

9. **Treat the top-right Outputs surface as a real right sidebar column when open, not an overlay or always-visible strip.**
   - Rationale: the requested interaction is that Outputs opens into the right sidebar area from the top-right button, but the closed state is visually clean. A left-sidebar `Outputs` route creates a second entry point with different semantics, a floating overlay covers the chat instead of moving it like a sidebar, and a collapsed trailing strip creates an unwanted extra column.
   - Remove the left-sidebar `Outputs` row. Keep the existing Outputs/workspace panel content available through the fixed top-right control.
   - The panel should not depend on scroll position or cover the chat content.
   - The right sidebar column width changes between zero/no visible column and the full workspace panel. The chat stage recenters in the remaining space.
   - Click toggles expanded/collapsed state; hover does not change sidebar state.

10. **Keep chat content width stable and centered across sidebar changes.**
   - Rationale: the reference keeps conversation content readable by constraining the message/composer column. When a sidebar collapses, the chat should move toward center instead of stretching to fill the newly available space.
   - Apply one stable max-width to the chat timeline, empty-state composer, and bottom composer.
   - Left or right sidebar expansion changes the available center region; it does not change the chat content's target width.

11. **Expose Marketplace as a localized `Market` sidebar item under `Automation`.**
    - Rationale: the existing marketplace/expert-team surface should be discoverable where the user expects it in the primary navigation.
    - The label follows the active language. In English it can display `Market`; in Chinese it should display the localized equivalent from the localization table.
    - The destination reuses the existing marketplace overview/detail views and selected-agent installation behavior.

12. **Localize chrome, not conversation content.**
    - Rationale: app navigation and controls should respect the selected language, but chat transcripts should remain the user/assistant-authored text.
    - Replace hard-coded sidebar/session labels with localized strings. Do not translate stored session titles or chat message bodies.

13. **Group provider settings under Gateway.**
    - Rationale: provider/API configuration is one conceptual Gateway area. Separate exposed cards read like unrelated surfaces.
    - The settings page should show `Gateway` as the section heading at the top, then contain the official service and custom API provider controls within one grouped container.

14. **Remove the global top divider and tighten the top timeline gutter.**
   - Rationale: the visible top line in the screenshot is likely produced by sidebar/window/split-view chrome or the sidebar header divider, not by chat scroll anchors. It must be handled at the outer layout level.
   - The app may keep subtle local dividers inside actual components, but no horizontal line should span across the sidebar/main-panel boundary.
   - Once the line is gone, the reserved top spacing above the first message should also shrink so the anchor/header region does not feel like a blank band.

15. **Add clear chat-session row hover actions.**
   - Rationale: hover should reveal a concrete action, not suggest that the row expands into something else. The requested action is delete on the right edge of the hovered session row.
   - Keep the existing row click behavior for opening a session, but reserve hover chrome for direct actions such as delete.

16. **Show the active session title in the main chat panel.**
   - Rationale: once the user enters a named chat session, the conversation title should remain visible in the chat surface near the left sidebar boundary so orientation is immediate.
   - Only render the title when the current session has a non-empty name; empty/new sessions keep the existing empty-state title behavior.

17. **Promote the right workspace panel to app-shell sidebar semantics.**
   - Rationale: the right panel should behave like a real sibling sidebar, not as chat-local state that happens to resize a column. Matching the left sidebar's ownership model makes the behavior more predictable and reduces one-off logic in `ChatView`.
   - The app shell should own the right-sidebar open/closed state, width behavior, and selected workspace item just as it already owns left-sidebar navigation and selected-tab state.
   - The top-right toggle remains the only chat-surface entry point, but it drives a layout-level sidebar rather than a view-local overlay controller.
   - Alternative considered: keep the current `ChatView`-local state and only restyle it. Rejected because the user explicitly asked to make the right sidebar implementation logic match the left sidebar.

18. **Treat workspace as an output browser, not an agent-config editor.**
   - Rationale: workspace in this flow is meant to surface artifacts produced by LLM runs. Agent identity/persona/config files belong to agent-management surfaces and should not pollute output browsing.
   - Hide `AGENTS.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md` from the workspace tree and workspace search results.
   - Apply the same rule to equivalent agent-config markdown files if they are part of the same authoring surface, so browse and search stay consistent.
   - Alternative considered: show these files but visually badge them. Rejected because the requirement is to avoid showing this class of file in workspace at all.

19. **Expose agents as a first-class sidebar category with inline creation.**
   - Rationale: the codebase already has agent listing and creation primitives. The missing piece is discoverability and placement in the primary navigation.
   - Add an `Agent` category to the left sidebar and render the existing agent list beneath it using the same quiet-sidebar visual language as the other sections.
   - Reuse the existing create-agent sheet from this category instead of creating a separate full-page flow.
   - Selecting an agent from this category should switch the chat context to that agent and surface that agent's sessions.

20. **Store sessions inside each agent workspace.**
   - Rationale: once sessions are agent-scoped in the UI, persistence should follow the same boundary so session files live with the agent they belong to.
   - Main-agent sessions should live under the main workspace; sub-agent sessions should live under that sub-agent's workspace directory.
   - The storage layer should either migrate or compat-read legacy globally stored sessions so existing history is not silently lost.
   - Alternative considered: keep global storage and only filter by `agentId`. Rejected because it does not satisfy the requirement that one agent's conversation content live under that agent directory.

21. **Keep only one sidebar search entry point and focus it on activation.**
   - Rationale: there are currently overlapping search affordances. The requested behavior is to preserve the actual session-search control and remove the redundant navigation-level entry.
   - The chat sidebar should keep the session search field above chat history and remove the separate top-level `Search` row.
   - Activating search should focus the session search field and filter sessions globally across all available chat history.
   - This change applies to chat-session search only; it does not remove the separate workspace-file search within the right sidebar.

## Risks / Trade-offs

- **Duplicating composer UI between empty and non-empty states** -> Extract small shared composer subviews and actions, but avoid a broad `DashboardView.swift` refactor.
- **Right sidebar width can squeeze the chat on small windows** -> Keep a reasonable minimum chat stage width, and let the right sidebar stay closed with no trailing strip when the window cannot fit the expanded panel cleanly.
- **Model selection behavior may currently be tied to the old settings/right-panel code** -> Reuse the existing model update path first; add only a narrow helper if needed.
- **Smooth panel animation can fight with SwiftUI layout in a large view file** -> Animate explicit sidebar width state and keep the transition localized to the right sidebar column.
- **Changing bubble backgrounds can affect code block contrast** -> Verify markdown/code rendering in light and dark mode and adjust nested code backgrounds if required.
- **Session-row hover delete can conflict with row-click navigation** -> Keep the delete button's hit target isolated and stop it from triggering `switchSession(to:)`.
- **Floating selector panels can escape small windows** -> Constrain widths and anchor to the composer control; if there is not enough horizontal room, stack the model panel above the primary panel without moving the composer card.
- **Removing the left-sidebar Outputs route can orphan existing tab state** -> Ensure any stale `.outputs` selection falls back to chat or opens the right-side panel instead of rendering an unreachable empty route.
- **The top divider may come from macOS NavigationSplitView/window chrome** -> If a local `Divider()` is not the source, adjust the container/window style or cover the separator within the main panel without breaking sidebar resizing.
- **Localization changes can create missing-string fallbacks** -> Add all new visible labels to `Localizable.xcstrings` and verify English/Chinese behavior at minimum.
- **Gateway grouping can disturb existing provider validation controls** -> Preserve current provider selection, API key visibility, sync/manage actions, and validation state while changing only the layout.
- **Moving session persistence into agent workspaces can strand legacy history** -> Add backward-compatible lookup or one-time migration before switching write targets.
- **Filtering workspace files too aggressively can hide genuinely useful artifacts** -> Limit the default hidden set to known agent-config markdown files and document the rule in code.
- **Promoting right-sidebar state upward can touch a large existing view file** -> Keep the state surface narrow and move only ownership/layout wiring, not unrelated chat behavior.
- **Removing the top-level Search row can reduce discoverability if focus behavior is weak** -> Ensure the remaining session-search control is easy to trigger and immediately focused when opened.

## Open Questions

- The fixed top-right control is assumed to open or collapse the Outputs/workspace-style panel. If it should instead control a different panel, update the implementation task before coding.
- The lower-left line is assumed to mean a stray divider or border near the bottom composer/sidebar boundary, not the sidebar's selected-row highlight.
- The top-left icon is assumed to mean the sidebar header logo next to `GetClawHub`.
- The `Market` label must follow the active language; English should show `Market`, and Chinese should use the existing or newly added localized value.
- The top-right Outputs control is click-only. Hover may show a normal tooltip, but it must not expand or reveal the right sidebar. When Outputs is closed, no separate right-side strip should remain visible.
- The search requirement is interpreted as keeping the session-search input and removing the redundant top-level sidebar `Search` row; clicking search should focus the session-search field and search all sessions globally.

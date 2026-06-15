## Context

The macOS app currently keeps chat composition at the bottom of the chat view and uses a right-side session details panel for agent, model, tool status, and session metadata. Recent cleanup already reduced the top chat toolbar and removed execution records, but starting a new chat still does not feel like a focused composition surface.

The desired direction is a Codex-style new-chat experience: no logo, no decorative branding, centered composer, and the agent/model controls attached directly to the composer. Skills should be discoverable from the left navigation instead of appearing as a secondary block in the removed right panel.

## Goals / Non-Goals

**Goals:**
- Show a clean centered empty-chat state when the active chat has no messages.
- Keep the empty-chat state visually minimal: title plus composer, with no logo.
- Put agent and model selection in the composer control row, aligned to the lower-right.
- Start the empty-chat composer in a collapsed state that shows only the compact control row until the user begins composing.
- Remove the chat right-side session details panel and its divider.
- Promote Skills to a left-sidebar navigation entry.
- Replace the separate Chat and New Session entries with a single New chat action.
- Preserve existing message sending, attachment, session persistence, and non-empty chat rendering.

**Non-Goals:**
- Do not change backend chat/session APIs.
- Do not redesign non-chat tabs.
- Do not delete historical sessions from disk.
- Do not introduce new image assets, logos, or decorative empty-state graphics.
- Do not replace the existing Skills page implementation.

## Decisions

1. **Use an empty-state branch inside `ChatView` instead of a separate page.**
   - Rationale: `ChatView` already owns input state, attachments, sending, file browser, and terminal-related state. Keeping the empty-state composer in `ChatView` avoids duplicating message-send plumbing.
   - Alternative considered: create a separate new-chat tab. Rejected because it would add navigation state and duplicate chat actions.

2. **Hide the right session details panel entirely in chat.**
   - Rationale: the requested target places agent/model controls in the composer and Skills in the left sidebar. Keeping an empty or collapsed right panel would preserve visual clutter and the unwanted divider.
   - Alternative considered: keep a collapsed panel for future details. Rejected because the user explicitly wants the right-side session detail removed.

3. **Add lightweight composer menus for Agent and Model.**
   - Rationale: the right panel's existing `ModelPickerRow` includes settings-panel behavior and full-width layout. A compact menu better matches the Codex reference and avoids bringing right-panel assumptions into the composer.
   - Visual treatment: the collapsed composer control row reads `[ +    Agent    Model ▼    ↑ ]`. The agent label uses stronger weight, while the model label uses a lighter gray style. The disclosure arrow opens a Codex-style menu whose title is `Agent`, whose main list contains created agents, and whose bottom row is `Models` with a trailing arrow. Opening `Models` shows available models in a secondary submenu.
   - Alternative considered: reuse `ModelPickerRow` inside the composer. Rejected because it is visually too large and coupled to session-detail layout.

4. **Start the empty composer collapsed.**
   - Rationale: the requested initial state is a low-profile action bar, not a large text box. The composer should expand only when the user clicks into the input area, starts typing, or otherwise begins composition.
   - Alternative considered: always show the full text box. Rejected because it does not match the requested initial collapsed state.

5. **Make New chat an action row, not a selectable persistent tab label.**
   - Rationale: clicking New chat should create/reset the active chat experience immediately. Existing sessions can still remain in the sidebar below it.
   - Alternative considered: keep both Chat and New Session. Rejected because the request is to merge them.

6. **Treat Skills as an existing page promoted in navigation.**
   - Rationale: `SkillsTabView` and `DashboardTab.skills` already exist. The change should move the entry point, not reimplement skill status.

## Risks / Trade-offs

- **Empty-state composer duplicates some bottom composer layout** → Keep shared send actions and bindings in `ChatView`; extract small subviews only where necessary.
- **Model switching from composer may need existing agent-settings helpers** → Use existing model list loading and update methods where possible; if no lightweight setter exists, add a narrow ViewModel helper.
- **Removing the right panel may hide session metadata users used** → This is intentional per request; session management remains available through sidebar context menus and chat history.
- **Large `DashboardView.swift` can become harder to maintain** → Keep additions small and localized; avoid broad refactors outside the requested UI flow.

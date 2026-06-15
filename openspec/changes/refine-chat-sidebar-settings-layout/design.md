## Context

The app sidebar currently mixes chat/session navigation, configuration navigation, account controls, language switching, and support actions. Chat messages also use an accent-colored user bubble that dominates the conversation. The Settings page exposes provider model tables that are not part of the desired day-to-day configuration flow.

## Decisions

1. **Flatten the App Sidebar order.**
   - Use a single primary list without a visible `Chat` group title.
   - Put utility/chat actions first: `New chat`, `Search`, `Skills`, `Plugins`, `Automation`, `Outputs`.
   - Keep conversation history below those actions.
   - Put account/business status entries below history: `Status`, `Budget`, `Billing`, `Settings`.

2. **Treat Outputs as a navigation entry.**
   - Add `Outputs` to `DashboardTab`.
   - Route it to the existing workspace/output browsing surface initially, but title/filter it as outputs rather than workspace/persona files.
   - The top chat toolbar no longer needs a workspace button, so it can be removed with its divider.

3. **Use quiet gray surfaces.**
   - User message bubbles switch from accent blue to gray.
   - Sidebar row selection should use a gray background. If SwiftUI `List(selection:)` uses the system selection color, use custom button rows for the rows in scope.

4. **Keep Settings as a card/grid page.**
   - Do not add an internal Settings sidebar.
   - Add card sections for Profile, Preferences, Persona, Model Provider, Gateway, and Advanced.
   - Move language, profile, and logout controls into Settings.
   - Remove model tables under provider sections.

## Risks / Trade-offs

- A fully custom sidebar row implementation gives better selection color control but touches more code than default `List` labels. Keep it scoped to the primary config sidebar.
- Outputs filtering may need a follow-up if generated artifacts do not have a reliable directory convention. For this pass, exclude known persona/config markdown files and show workspace outputs.
- Settings page restructuring should preserve existing save behavior and provider editing state.

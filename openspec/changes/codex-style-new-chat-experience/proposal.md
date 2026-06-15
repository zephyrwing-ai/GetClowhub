## Why

The chat experience currently spreads new-message composition, agent/model selection, session metadata, and skill status across separate areas, which makes a new conversation feel heavier than necessary. A Codex-style empty chat state will make starting work cleaner, with the composer centered and the most relevant controls attached to it.

## What Changes

- Add a clean new-chat empty state with no logo or decorative branding.
- Center the new-chat composer in the main conversation area before any messages exist.
- Move agent and model selection into the composer controls, positioned at the lower-right of the input area.
- Remove the right-side session details panel from the chat view, including Session Info and the right divider line.
- Remove Tool Status from the right-side panel and expose Skills through a left-sidebar navigation entry.
- Merge the left-sidebar Chat and New Session entries into a single New chat entry.
- Preserve existing chat sending behavior after the first message is sent.

## Capabilities

### New Capabilities
- `chat-composition-experience`: Defines the empty chat state, composer placement, composer controls, and sidebar navigation behavior for starting conversations.

### Modified Capabilities

None.

## Impact

- Affects `OpenClawInstaller/Views/Dashboard/DashboardView.swift` for chat layout, sidebar entries, right panel removal, and composer controls.
- May affect `OpenClawInstaller/ViewModels/DashboardViewModel.swift` if lightweight helper state or model-selection helpers are needed.
- Affects `OpenClawInstaller/Localizable.xcstrings` for New chat and empty-state copy.
- No backend API, storage format, or dependency changes are expected.

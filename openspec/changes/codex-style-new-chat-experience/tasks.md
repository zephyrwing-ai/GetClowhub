## 1. Sidebar Navigation

- [x] 1.1 Replace the separate Chat and New Session entries in `SidebarView.sidebarMainList` with a single `New chat` action.
- [x] 1.2 Ensure `New chat` calls `viewModel.createNewSession()` and selects `DashboardTab.chat`.
- [x] 1.3 Promote the existing Skills tab into the left sidebar as a visible navigation entry.
- [x] 1.4 Confirm existing session history rows remain available below the new-chat action.

## 2. Remove Right Session Details

- [x] 2.1 Remove `SessionDetailsPanel(viewModel:)` from the chat layout in `DetailContentView`.
- [x] 2.2 Remove any chat-only right-panel divider that remains after the panel is no longer rendered.
- [x] 2.3 Remove or leave unreferenced right-panel-only session info and tool-status UI without affecting build output.

## 3. Centered Empty Chat State

- [x] 3.1 Add an empty-chat branch in `ChatView` for `viewModel.chatMessages.isEmpty`.
- [x] 3.2 Render a minimal centered empty state with no logo, no brand image, and no decorative illustration.
- [x] 3.3 Place the chat prompt/composer in the center of the main chat area for empty sessions.
- [x] 3.4 Start the empty-chat composer in a collapsed state that shows only the compact control row.
- [x] 3.5 Expand the composer text area when the user begins composing.
- [x] 3.6 Preserve the existing timeline layout for sessions with one or more messages.

## 4. Composer Controls

- [x] 4.1 Extract or add a compact composer control row that can be used in the empty-chat composer.
- [x] 4.2 Lay out the collapsed row as add control, strong Agent label, lighter gray Model label, disclosure arrow, and send button.
- [x] 4.3 Add an Agent menu opened from the disclosure arrow, titled `Agent`, listing created agents and updating `viewModel.selectedAgentId`.
- [x] 4.4 Add a bottom `Models` menu row with a trailing arrow inside the Agent menu.
- [x] 4.5 Add the Models submenu using existing model data and update behavior.
- [x] 4.6 Ensure send, attachment, and message text behavior continue to use existing `ChatView` state and send paths.
- [x] 4.7 Confirm sending the first message switches from centered empty state to the normal chat timeline.

## 5. Localization

- [x] 5.1 Add localized strings for `New chat`.
- [x] 5.2 Add localized strings for the empty-chat prompt text.
- [x] 5.3 Add or reuse localized strings for `Agent`, `Model`, and composer control labels.
- [x] 5.4 Keep `Localizable.xcstrings` edits minimal and avoid full-file JSON reformatting.

## 6. Verification

- [x] 6.1 Run a source check to confirm removed right-panel entries are no longer referenced from the chat layout.
- [x] 6.2 Build the app with `xcodebuild -project OpenClawInstaller.xcodeproj -scheme OpenClawInstaller -configuration Debug -destination 'platform=macOS' build`.
- [x] 6.3 Launch the Debug app and visually verify the empty-chat centered composer, New chat sidebar action, Skills sidebar entry, and absence of the right session details panel.

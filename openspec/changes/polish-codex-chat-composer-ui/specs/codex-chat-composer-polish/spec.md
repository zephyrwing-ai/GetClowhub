## ADDED Requirements

### Requirement: Empty New chat centers the composer
The system SHALL show a centered Codex-style composition surface when the selected chat session has no messages.

#### Scenario: New chat opens empty
- **WHEN** the user clicks `New chat` and the selected session has no messages
- **THEN** the main chat panel displays a centered title and composer
- **AND** the composer is not pinned to the bottom of the window
- **AND** the empty state does not render the normal message timeline scroll anchors

#### Scenario: First message starts the timeline
- **WHEN** the user sends the first message from the centered composer
- **THEN** the sent message appears in the normal chat timeline
- **AND** the composer moves to the bottom timeline layout
- **AND** existing message sending, attachment, and session persistence behavior continues to work

### Requirement: Scroll anchors stay invisible and panel-contained
The system SHALL keep chat scroll anchors invisible and visually contained inside the main chat panel.

#### Scenario: Active conversation has scroll anchors
- **WHEN** a conversation contains messages and the timeline renders scroll anchors
- **THEN** the anchors do not render as visible horizontal lines
- **AND** no anchor-related line crosses into or through the left sidebar
- **AND** no anchor-related line appears above the first visible message as standalone chrome

#### Scenario: Empty conversation has no anchor artifact
- **WHEN** the selected chat session has no messages
- **THEN** no scroll-anchor placeholder, divider, or horizontal line appears in the empty-state main panel

### Requirement: Chat bubbles use visible gray backgrounds
The system SHALL render user and assistant messages inside visible gray rounded bubbles.

#### Scenario: User message bubble
- **WHEN** a user chat message is rendered
- **THEN** the message content appears inside a rounded gray bubble
- **AND** the bubble remains visibly distinct from the page background in light and dark appearance
- **AND** the bubble uses only a small desktop-style corner radius instead of a large pill radius

#### Scenario: Assistant message bubble
- **WHEN** an assistant chat message is rendered
- **THEN** the message content appears inside a rounded gray bubble
- **AND** markdown, code, and long text remain readable inside the bubble
- **AND** the assistant bubble uses the same tightened corner-radius family as the user bubble

### Requirement: Composer shows combined agent and model selector
The system SHALL expose agent and model selection from the composer as a combined control.

#### Scenario: Current selection is visible
- **WHEN** the composer is visible
- **THEN** the lower-right composer control displays the current agent and model as a combined label such as `UX · GPT-5.5 v`

#### Scenario: Agent selection updates composer
- **WHEN** the user opens the composer agent/model selector and chooses an agent
- **THEN** the selected agent changes for the current chat context
- **AND** the combined composer label updates to show the chosen agent

#### Scenario: Model selection uses adjacent nested panel
- **WHEN** the user opens the composer agent/model selector and activates the `Model >` row
- **THEN** a model list appears directly in an adjacent panel while the primary selector remains visible
- **AND** selecting a model updates the current model according to existing model behavior
- **AND** the combined composer label updates to show the chosen model

#### Scenario: Selector does not move composer
- **WHEN** the user opens the composer agent/model selector, reveals the adjacent model panel, selects an agent, or selects a model
- **THEN** the composer card remains in the same screen position
- **AND** the selector panels float above or beside the composer without contributing to composer layout height
- **AND** the chat timeline, empty-state title, and bottom composer do not jump because of selector state

### Requirement: Fixed top-right panel control
The system SHALL provide a fixed top-right panel control for Outputs/workspace-style panel access.

#### Scenario: Panel control is always visible in chat
- **WHEN** the chat view is visible
- **THEN** the panel control appears in the top-right of the main chat panel
- **AND** the control remains visible whether the chat is empty or contains messages
- **AND** the control position does not depend on scroll-anchor state

#### Scenario: Panel expands and collapses smoothly
- **WHEN** the user clicks the fixed top-right panel control
- **THEN** the related panel expands or collapses with a smooth animated resize or scale transition
- **AND** the panel does not snap open or closed abruptly

#### Scenario: Panel grows from the control
- **WHEN** the user opens the Outputs/workspace panel from the top-right control
- **THEN** the right sidebar column expands from a hidden zero-width closed state into the workspace panel width
- **AND** closing the panel collapses it back toward the same control
- **AND** the closed state leaves no trailing right-side strip, toolbar, icon stack, or divider
- **AND** the panel does not appear as a floating sheet over the chat content

#### Scenario: Closed Outputs leaves no trailing strip
- **WHEN** the Outputs/workspace surface is collapsed
- **THEN** no slim right-sidebar strip remains docked on the chat view's trailing edge
- **AND** the far-right edge does not show a folder icon, sidebar icon, icon stack, narrow toolbar, or standalone divider
- **AND** the fixed top-right panel control remains the only visible Outputs entry point while closed
- **AND** the expanded Outputs content still opens in a right-sidebar layout column rather than appearing as an unrelated floating sheet

#### Scenario: Click toggles Outputs
- **WHEN** the user clicks the top-right Outputs control
- **THEN** the right sidebar toggles between a hidden zero-width closed state and the expanded workspace width
- **AND** the width change is animated smoothly
- **AND** hovering the control does not expand or reveal the Outputs sidebar

#### Scenario: Chat column remains stable across right-sidebar changes
- **WHEN** the right sidebar expands or collapses
- **THEN** the chat message and composer column keeps the same target maximum width
- **AND** the chat column recenters within the remaining space instead of stretching wider
- **AND** the right sidebar does not cover chat messages or the composer

#### Scenario: Left sidebar Outputs route is absent
- **WHEN** the left sidebar navigation is visible
- **THEN** there is no `Outputs` navigation row in the sidebar
- **AND** Outputs/workspace access remains available through the fixed top-right control

### Requirement: Chat content width stays stable while sidebars change
The system SHALL keep conversation content on a stable centered column as sidebars expand or collapse.

#### Scenario: Left sidebar collapses or expands
- **WHEN** the left app sidebar collapses or expands
- **THEN** the chat timeline and composer keep the same target maximum width
- **AND** the chat stage moves horizontally to remain centered in the available content area

#### Scenario: Right sidebar hides or expands
- **WHEN** the right Outputs/workspace sidebar closes or expands
- **THEN** the chat timeline and composer keep the same target maximum width
- **AND** the chat stage moves horizontally to remain centered in the available content area

#### Scenario: Large windows do not create oversized chat blanks
- **WHEN** the app window is wide
- **THEN** the chat message column does not stretch to fill the whole center area
- **AND** message bubbles, code blocks, and the composer remain inside the stable centered column

### Requirement: Stray divider lines are removed
The system SHALL avoid orphan horizontal divider lines in the refined chat layout.

#### Scenario: Top chat divider is absent
- **WHEN** the chat view is visible
- **THEN** no standalone top divider line spans the chat area or sidebar boundary

#### Scenario: Top gutter is compact
- **WHEN** the chat timeline is visible
- **THEN** the blank vertical gutter above the first visible message is kept compact
- **AND** the area previously associated with the top anchor/divider does not remain as a tall empty band

#### Scenario: Global top divider is absent
- **WHEN** the main app shell is visible
- **THEN** no horizontal divider line spans from the sidebar into the main content area at the top of the window
- **AND** any remaining separators are local to an actual component such as a card, panel, or sidebar group

#### Scenario: Lower-left divider is absent
- **WHEN** the bottom composer or sidebar bottom area is visible
- **THEN** no stray lower-left horizontal line appears outside a real component boundary

### Requirement: Sidebar header omits top-left brand icon
The system SHALL remove the top-left sidebar brand icon while preserving usable sidebar header layout.

#### Scenario: Sidebar header is visible
- **WHEN** the sidebar header is rendered
- **THEN** the logo/icon mark next to the app title is not displayed
- **AND** sidebar navigation remains usable

### Requirement: Sidebar navigation is localized and reorganized
The system SHALL present localized sidebar chrome with the marketplace entry in the requested location.

#### Scenario: Sidebar labels follow active language
- **WHEN** the app language is English
- **THEN** sidebar chrome labels use English labels such as `New chat`, `Search`, `Skills`, `Plugins`, `Automation`, `Market`, and `Chat History`
- **AND** hard-coded Chinese labels are not shown in app chrome

#### Scenario: Sidebar labels follow Chinese language
- **WHEN** the app language is Chinese
- **THEN** sidebar chrome labels use Chinese localized values
- **AND** the localization change does not translate stored chat messages or stored session titles

#### Scenario: Market entry appears under Automation
- **WHEN** the left sidebar navigation is visible
- **THEN** a localized `Market` navigation row appears directly under `Automation`
- **AND** selecting it opens the existing marketplace/expert-team overview and detail flow

### Requirement: Session rows expose a direct hover delete action
The system SHALL show a concrete delete affordance on hovered chat-session rows.

#### Scenario: Hovered session shows delete button
- **WHEN** the user hovers a chat-session row in the left sidebar
- **THEN** the right edge of that row shows a delete affordance
- **AND** the hover state does not imply that the row can expand into another panel

#### Scenario: Delete action stays separate from row navigation
- **WHEN** the user clicks the hover delete affordance
- **THEN** the current session-delete confirmation flow opens for that session
- **AND** the row click action for opening the session is not triggered by the delete control

### Requirement: Named conversations show their title in the main chat surface
The system SHALL surface the active conversation title near the left side of the main chat panel when the current session already has a name.

#### Scenario: Named session shows title in chat header area
- **WHEN** the user opens a chat session whose title is non-empty
- **THEN** the main chat surface shows that session title near the left-sidebar side of the content area
- **AND** the title remains visible while the user reads or continues the conversation

#### Scenario: Empty new chat does not duplicate the title
- **WHEN** the selected session has no saved name yet or is still the empty `New chat` state
- **THEN** the chat surface does not render an extra session-title header above the existing empty-state composition title

### Requirement: Gateway settings are grouped
The system SHALL group provider configuration into a single Gateway section.

#### Scenario: Gateway settings section renders
- **WHEN** the user opens the settings/configuration page that contains provider configuration
- **THEN** a `Gateway` section heading appears at the top of the provider settings area
- **AND** the official GetClawHub service controls and custom API provider controls are contained within one grouped Gateway container

#### Scenario: Provider controls remain functional
- **WHEN** the Gateway settings are grouped
- **THEN** existing provider selection, API base URL, API key visibility, sync/manage actions, and selected-provider state remain available
- **AND** the grouping changes visual layout without changing gateway backend behavior

### Requirement: Right workspace sidebar follows app-shell sidebar semantics
The system SHALL manage the right workspace sidebar with the same app-shell sidebar semantics used for the left sidebar.

#### Scenario: Right sidebar state is layout-owned
- **WHEN** the chat shell renders the right workspace sidebar
- **THEN** the open or closed state is owned by the app-shell layout rather than only by chat-local overlay state
- **AND** the right sidebar participates in layout as a real sibling column
- **AND** the top-right chat control remains the only visible entry point for opening it

#### Scenario: Right sidebar selection survives chat redraws
- **WHEN** chat content rerenders because of message updates, agent switching, or session switching
- **THEN** the right sidebar's open state and selected workspace item remain stable according to app-shell sidebar state
- **AND** the panel does not reset simply because the chat timeline subtree rerendered

### Requirement: Workspace only shows LLM output artifacts
The system SHALL treat workspace browsing as an LLM output surface rather than an agent-config document browser.

#### Scenario: Agent config markdown files are hidden from workspace tree
- **WHEN** the workspace file tree is rendered
- **THEN** files such as `AGENTS.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md` are not shown in the visible tree
- **AND** the user only sees output-oriented files and directories in the workspace browser

#### Scenario: Agent config markdown files are hidden from workspace search
- **WHEN** the user searches files inside the workspace panel
- **THEN** files such as `AGENTS.md`, `IDENTITY.md`, `SOUL.md`, and `MEMORY.md` are excluded from search results
- **AND** the search results stay consistent with the visible workspace tree

### Requirement: Sidebar exposes an Agent category with create action
The system SHALL expose agent selection and creation from a dedicated Agent category in the left sidebar.

#### Scenario: Agent category appears in primary sidebar
- **WHEN** the left sidebar is visible
- **THEN** a localized `Agent` category appears in the sidebar navigation area
- **AND** that category lists available agents using the same quiet sidebar interaction style as adjacent sections

#### Scenario: Agent category can create agents
- **WHEN** the user activates the add-agent affordance from the sidebar `Agent` category
- **THEN** the existing create-agent flow opens
- **AND** successfully creating an agent refreshes the sidebar list and makes the new agent selectable

#### Scenario: Selecting an agent switches chat context
- **WHEN** the user selects an agent from the sidebar `Agent` category
- **THEN** the current chat context switches to that agent
- **AND** the sidebar session history updates to show that agent's sessions
- **AND** the main chat surface reflects that selected agent context

### Requirement: Agent sessions live under the agent workspace directory
The system SHALL persist each agent's chat sessions under that agent's own workspace directory.

#### Scenario: Main agent stores sessions in main workspace
- **WHEN** the main agent creates or updates a chat session
- **THEN** that session is persisted under the main workspace session directory
- **AND** the app does not write that session only to the legacy global chat-session directory

#### Scenario: Sub-agent stores sessions in its own workspace
- **WHEN** a non-main agent creates or updates a chat session
- **THEN** that session is persisted under that agent's workspace session directory
- **AND** one agent's session files are kept separate from another agent's workspace files

#### Scenario: Legacy sessions remain available
- **WHEN** the app loads chat history after the session-storage layout changes
- **THEN** previously saved sessions remain readable through migration or backward-compatible lookup
- **AND** the user does not lose existing chat history because of the new per-agent storage layout

### Requirement: Sidebar search keeps only the session-search entry point
The system SHALL keep only the session-search entry point in the chat sidebar and remove the redundant top-level search entry.

#### Scenario: Top-level Search row is absent
- **WHEN** the chat sidebar navigation is rendered
- **THEN** the redundant top-level `Search` row is not shown
- **AND** the sidebar still provides session search through the chat-history search control

#### Scenario: Clicking search focuses session search
- **WHEN** the user activates the remaining session-search entry point
- **THEN** focus moves to the session search input
- **AND** typing filters chat sessions globally across all available history
- **AND** this behavior does not affect workspace-file search in the right sidebar

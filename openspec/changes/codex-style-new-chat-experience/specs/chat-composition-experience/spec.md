## ADDED Requirements

### Requirement: Empty chat shows centered composer
The system SHALL show a minimal centered composition state when the selected chat session has no messages.

#### Scenario: New chat has no messages
- **WHEN** the user creates or selects an empty chat session
- **THEN** the chat area displays a centered prompt and composer
- **AND** the empty state does not display a logo, brand image, or decorative illustration

#### Scenario: First message is sent
- **WHEN** the user sends a message from the centered composer
- **THEN** the chat area switches to the normal message timeline layout
- **AND** the sent message appears in the conversation

### Requirement: Composer exposes agent and model controls
The system SHALL place agent and model selection controls in the composer control row for chat composition.

#### Scenario: Empty composer starts collapsed
- **WHEN** the user creates or selects an empty chat session
- **THEN** the composer initially shows a compact control row with add, agent, model, disclosure, and send controls
- **AND** the full text input area is not expanded until the user begins composing

#### Scenario: Composer control row visual hierarchy
- **WHEN** the empty composer is collapsed
- **THEN** the agent label is visually stronger than the model label
- **AND** the model label uses a lighter gray treatment

#### Scenario: Agent selection from empty composer
- **WHEN** the user opens the agent control in the empty-chat composer and selects an agent
- **THEN** the selected agent changes for the current chat context
- **AND** the composer continues to target the selected agent when sending

#### Scenario: Agent menu includes models submenu
- **WHEN** the user opens the composer disclosure menu
- **THEN** the menu title is Agent
- **AND** the menu lists created agents
- **AND** the menu includes a bottom Models row with a trailing arrow

#### Scenario: Model selection from empty composer
- **WHEN** the user opens the Models submenu from the composer menu and selects a model
- **THEN** the selected model changes for the current agent or chat context according to existing model behavior
- **AND** the selected model is reflected in the composer control

### Requirement: Chat view omits right session details panel
The system SHALL not show the right-side session details panel in the chat view.

#### Scenario: Chat page is visible
- **WHEN** the selected tab is Chat
- **THEN** no right-side Session Details panel is rendered
- **AND** no right-side divider line remains from that panel

### Requirement: Skills is available from left navigation
The system SHALL expose Skills as a left-sidebar navigation entry for skill status and management.

#### Scenario: User opens Skills
- **WHEN** the user clicks the Skills entry in the left sidebar
- **THEN** the main content area displays the existing Skills page

### Requirement: Sidebar uses New chat action
The system SHALL replace separate Chat and New Session sidebar entries with a single New chat action.

#### Scenario: User starts new chat from sidebar
- **WHEN** the user clicks New chat in the sidebar
- **THEN** the app creates a new chat session
- **AND** the selected tab becomes Chat
- **AND** the empty-chat centered composer is shown when the new session has no messages

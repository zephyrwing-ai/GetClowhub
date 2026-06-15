## ADDED Requirements

### Requirement: Sidebar uses refined order and gray selection
The system SHALL show the App Sidebar entries in the requested order and use a gray selected-row background.

#### Scenario: Sidebar is visible
- **WHEN** the main config sidebar is displayed
- **THEN** the top-level Chat section title is not shown
- **AND** the visible rows are ordered as New chat, Search, Skills, Plugins, Automation, Outputs, conversation history, Status, Budget, Billing, Settings
- **AND** the selected row uses a gray background treatment

### Requirement: Chat messages use gray bubbles
The system SHALL avoid accent-colored user message bubbles in the chat timeline.

#### Scenario: User message is shown
- **WHEN** a user chat message is rendered
- **THEN** the message bubble uses a gray background
- **AND** the message text remains readable in the current appearance mode

### Requirement: Outputs is available from App Sidebar
The system SHALL expose Outputs as a left App Sidebar navigation entry.

#### Scenario: User opens Outputs
- **WHEN** the user clicks Outputs
- **THEN** the main content area displays generated output files or results
- **AND** agent/persona configuration markdown documents are not presented as primary output content

### Requirement: Settings contains account, language, persona, and provider configuration
The system SHALL consolidate secondary account and preference controls into Settings.

#### Scenario: Settings is opened
- **WHEN** the user opens Settings
- **THEN** profile, language, logout, persona, provider, gateway, and advanced configuration areas are available on the Settings page
- **AND** the Settings page does not add a nested left-side settings navigation
- **AND** provider model lists are not displayed under provider configuration

### Requirement: Chat header removes workspace-only chrome
The system SHALL not show a workspace-only top header in chat.

#### Scenario: Chat page is visible
- **WHEN** the user is on the Chat page
- **THEN** the top workspace-only header button is absent
- **AND** divider lines that only existed for that header are absent

## ADDED Requirements

### Requirement: Sidebar search opens global overlay
The system SHALL open a centered full-window global chat-search overlay when the user activates the sidebar `Search` row.

#### Scenario: Search row opens modal overlay
- **WHEN** the user clicks the left-sidebar `Search` row
- **THEN** a search panel appears centered over the main window
- **AND** the window content behind the panel is dimmed
- **AND** the user remains in the current app context instead of navigating to a separate search page

#### Scenario: Search field receives focus
- **WHEN** the global search overlay opens
- **THEN** the search field is ready for text entry
- **AND** the search query starts empty for the new overlay session

### Requirement: Global overlay is owned by DashboardView
The system SHALL keep global chat-search overlay presentation state and rendering owned by `DashboardView`.

#### Scenario: Overlay covers full split view
- **WHEN** the global search overlay is visible
- **THEN** it covers the full `NavigationSplitView` area, including sidebar and detail content
- **AND** the panel is not clipped to the sidebar column

#### Scenario: Sidebar only triggers overlay
- **WHEN** `SidebarView` renders the `Search` row
- **THEN** `SidebarView` uses a callback to request the overlay
- **AND** `SidebarView` does not define duplicate global-search overlay state, result queries, or overlay row rendering

### Requirement: Overlay searches all chat sessions
The system SHALL search unarchived chat sessions across all agents from the centered overlay.

#### Scenario: Empty query shows recent chats
- **WHEN** the global search overlay is open and the query is empty
- **THEN** the result list shows recent unarchived chats across agents
- **AND** the newest matching sessions appear before older sessions

#### Scenario: Query filters sessions globally
- **WHEN** the user types a search query
- **THEN** the result list filters unarchived chats across all agents
- **AND** matches are not limited to the currently selected agent

#### Scenario: No results state
- **WHEN** the user types a query that matches no chat sessions
- **THEN** the overlay shows a no-matches state inside the panel

### Requirement: Selecting a result switches chat
The system SHALL switch to the selected chat session and dismiss the overlay when the user selects a global search result.

#### Scenario: Result row selected
- **WHEN** the user selects a result row in the global search overlay
- **THEN** the app switches to that chat session
- **AND** the selected tab becomes chat
- **AND** the global search overlay closes

#### Scenario: Dismiss without selection
- **WHEN** the user clicks outside the panel
- **THEN** the global search overlay closes
- **AND** the current selected chat session remains unchanged

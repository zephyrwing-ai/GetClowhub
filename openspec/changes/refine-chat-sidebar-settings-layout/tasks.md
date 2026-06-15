## 1. Sidebar

- [x] 1.1 Reorder config sidebar entries to match the requested order.
- [x] 1.2 Remove the visible top-level Chat section title and primary Persona row.
- [x] 1.3 Add Outputs as a sidebar navigation entry.
- [x] 1.4 Use gray selected-row styling for sidebar rows.
- [x] 1.5 Remove Help and Logout from the lower-left sidebar controls.

## 2. Chat

- [x] 2.1 Change user message bubbles from accent blue to gray with readable text.
- [x] 2.2 Remove the top workspace-only chat header and divider.
- [x] 2.3 Keep file upload buttons as plus controls.

## 3. Outputs

- [x] 3.1 Add an Outputs tab or route.
- [x] 3.2 Show generated output/workspace content while excluding agent/persona markdown configuration files.

## 4. Settings

- [x] 4.1 Restructure Settings into card/grid sections without nested Settings navigation.
- [x] 4.2 Move profile, language, logout, and persona entry points into Settings.
- [x] 4.3 Remove provider model-list display from Settings.
- [x] 4.4 Preserve existing provider/gateway save behavior.

## 5. Verification

- [x] 5.1 Run source checks for removed sidebar/header strings and new Outputs route.
- [x] 5.2 Build the app with `xcodebuild -project OpenClawInstaller.xcodeproj -scheme OpenClawInstaller -configuration Debug -destination 'platform=macOS' build`.

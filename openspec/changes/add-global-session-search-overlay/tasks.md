## 1. Verification Setup

- [x] 1.1 Run the overlay-placement verification script and confirm it currently fails because `SidebarView` still owns duplicate global-search overlay code.
- [x] 1.2 Run the global-session search verification script and confirm existing cross-agent search behavior remains available.

## 2. Overlay Ownership Cleanup

- [x] 2.1 Remove duplicate `globalSearchResults`, `globalSessionSearchOverlay`, `globalSessionSearchRow`, and helper search code from `SidebarView`.
- [x] 2.2 Keep the sidebar `Search` row wired only through `onOpenGlobalSessionSearch`.
- [x] 2.3 Ensure `DashboardView` remains the only owner of `isGlobalSessionSearchPresented`, `globalSessionSearchText`, and `isGlobalSessionSearchFocused`.

## 3. Centered Overlay UI

- [x] 3.1 Update `DashboardView.globalSessionSearchOverlay` so the search panel is centered over the full window with a dimmed background.
- [x] 3.2 Constrain the panel width for smaller windows while keeping the desktop popup style from the reference screenshot.
- [x] 3.3 Preserve recent-chat, filtered-result, no-match, row-selection, and outside-click dismissal behavior.

## 4. Final Verification

- [x] 4.1 Re-run the overlay-placement verification script and confirm it passes.
- [x] 4.2 Re-run the global-session search verification script and confirm it passes.
- [x] 4.3 Run `openspec validate --all --strict`.
- [x] 4.4 Run `git diff --check`.
- [x] 4.5 Build the macOS app with `xcodebuild -project OpenClawInstaller.xcodeproj -scheme OpenClawInstaller -configuration Debug -derivedDataPath /private/tmp/GetclowhubDerivedData -quiet build`.

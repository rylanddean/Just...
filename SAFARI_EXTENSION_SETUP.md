# Safari Extension — Xcode Setup

All source files are written. Two new Xcode targets need to be created manually
(adding targets via `project.pbxproj` is error-prone; the GUI is faster and safer).

---

## 1. Companion macOS App — `JustEllipsisMac`

**File → New → Target → macOS → App**

| Setting | Value |
|---------|-------|
| Product Name | `JustEllipsisMac` |
| Bundle Identifier | `com.rylandean.justellipsis.mac` |
| Interface | SwiftUI |
| Language | Swift |
| Minimum Deployment | macOS 13.0 |

After creation:
1. Delete the generated `ContentView.swift` and `Assets.xcassets` — they are not needed.
2. Delete the generated `JustEllipsisMacApp.swift` and replace with `JustEllipsisMac/JustEllipsisMacApp.swift` from this repo (drag into the target in Xcode).
3. Under **Signing & Capabilities**, add:
   - **iCloud** → enable CloudKit → container `iCloud.com.rylandean.justellipsis`
   - **App Sandbox** → check **Outgoing Connections (Client)**
4. Set the entitlements file to `JustEllipsisMac/JustEllipsisMac.entitlements`.
5. Under **Info**, set `Application is agent (UIElement)` → `YES`  
   (Prevents a dock icon without requiring LSUIElement in a separate Info.plist key — but also add `LSUIElement = YES` to the Info.plist directly for belt-and-suspenders.)

---

## 2. Safari Web Extension — `JustEllipsisSafariExtension`

**File → New → Target → macOS → Safari Extension**

When the dialog appears, choose **Safari Web Extension** (not Safari App Extension).

| Setting | Value |
|---------|-------|
| Product Name | `JustEllipsisSafariExtension` |
| Bundle Identifier | `com.rylandean.justellipsis.mac.safari-extension` |
| Language | Swift |
| Containing App | `JustEllipsisMac` |
| Minimum Deployment | macOS 13.0 |

After creation:
1. Delete every generated file inside the extension target except the `Info.plist`.
2. Add these files to the target (drag from Finder or File → Add Files):
   - `JustEllipsisSafariExtension/SafariWebExtensionHandler.swift`
   - `JustEllipsisSafariExtension/CloudKitLinkWriter.swift`
3. Add the entire `JustEllipsisSafariExtension/Resources/` folder as a **folder reference**
   (blue folder icon, not a group) so Xcode copies it as-is into the extension bundle.
4. Under **Signing & Capabilities**, add:
   - **iCloud** → enable CloudKit → container `iCloud.com.rylandean.justellipsis`
   - **App Sandbox** → check **Outgoing Connections (Client)**
5. Set the entitlements file to `JustEllipsisSafariExtension/JustEllipsisSafariExtension.entitlements`.
6. In `Info.plist`, ensure `NSExtension → NSExtensionPrincipalClass` is set to  
   `$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler`.

---

## 3. Toolbar Icon PNGs

`Resources/images/toolbar-icon.svg` is the reference glyph.

Export it as a **template PNG** (black fill, alpha only) at:
- `toolbar-icon-16.png` — 16 × 16 px
- `toolbar-icon-32.png` — 32 × 32 px

In Finder / Preview / Sketch / Figma:
1. Open `toolbar-icon.svg`
2. Export at 16 × 16, save as `toolbar-icon-16.png`
3. Export at 32 × 32, save as `toolbar-icon-32.png`

Safari automatically tints template images to match the toolbar (light/dark).

---

## 4. CloudKit Schema (auto-created)

The first time `CloudKitLinkWriter.save()` runs it writes a record of type
`JE_PendingLink` to the private database. CloudKit creates the schema on write —
no manual CloudKit Dashboard setup is required.

Fields created automatically:

| Field | Type |
|-------|------|
| `url` | String |
| `title` | String |
| `domain` | String |
| `addedAt` | Date/Time |

---

## 5. iOS App — no Xcode changes needed

`MacLinkReceiver.swift` is already added to the `JustEllipsis` target directory.
Add it to the target in Xcode by dragging `JustEllipsis/Services/MacLinkReceiver.swift`
into the Services group in the Project Navigator and ensuring **Target Membership**
includes `JustEllipsis`.

`RootView.swift` already calls `checkMacPendingLinks()` — no further edits needed.

---

## 6. Testing the end-to-end flow

1. Build and run `JustEllipsisMac` on your Mac.
2. Open Safari → Settings → Extensions → enable **Just…**.
3. Navigate to any article URL.
4. Click the `…` toolbar button → click **Add to Just…**.
5. Open Just… on your iPhone — the link should appear in the queue within ~10s.

For faster iteration, check CloudKit Dashboard (developer.apple.com) →
Containers → `iCloud.com.rylandean.justellipsis` → Private Database →
`JE_PendingLink` to confirm records are being written and deleted correctly.

<div align="center">
<img src="Photor%20logo.png" alt="Photor" width="140">

Photor

A fast, lightweight, native photo viewer for macOS.

Built with Swift, SwiftUI, AppKit, Core Image, and Metal.

</div>

⸻

Features

* Fast browsing — Smooth navigation through large JPEG and RAW (RAF) files.
* Smart RAM caching — Preloads nearby images for instant navigation.
* GPU acceleration — Hardware-accelerated rendering with Metal.
* Zoom & Pan — Native trackpad gestures, mouse controls, and pixel-perfect 100% zoom.
* Albums & Favorites — Organize photos across folders without duplicating files.
* Grid View — Quickly browse large photo collections.
* File Management — Copy, move, or delete photos directly from the app.

Getting Started

Open dist/Photor.app and select a folder with ⌘O, or drag a folder into the window.

To build from source:

bash scripts/build-app.sh
open dist/Photor.app

Requires macOS 14+ and Swift 6.

Keyboard Shortcuts

Shortcut	Action
← / →	Previous / Next photo
⌘O	Open folder
Space	Fit to window
1	Actual size (100%)
+ / −	Zoom in / out
⌘G	Toggle grid view
⌘S	Toggle favorite
⌘1–4	Toggle custom albums
⌘⌫	Move to Trash
⌃⌘F	Full screen

Performance

Photor uses intelligent RAM precaching to keep navigation responsive.

Setting	Default
RAM cache	16 GiB (configurable: 4–32 GiB)
Preload window	±100 photos
Full-resolution JPEG	±5 photos
Full-resolution RAW	±1 photo

Technical Details

* 100% native macOS application.
* No external dependencies.
* Supports JPEG and Fujifilm RAF.
* Non-destructive viewing and organization.
* Locally stored albums and favorites.

For implementation details, see Pipeline Documentation.

⸻

<div align="center">

Made with Swift & Metal.

</div>
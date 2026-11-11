# ROHD Schematic Viewer v{{VERSION}} — Help

<!-- markdownlint-disable MD060 -->
<!-- tooltip -->

Keybindings

Loading
  🔄  Reload current schematic

Settings
  ⚙️  Display widths  Show or hide blue multi-bit signal-width overlays

Zooming
  Scroll          Zoom in / out
  F               Fit to canvas
  Ctrl+Drag       Zoom to region

Search
  Ctrl+F          Open search overlay
  Enter / ↑ / ↓   Navigate results
  Tab             Expand common prefix
  Esc             Close search

Expansion
  Click +         Fully expand block
  Click −         Collapse block
  Click ⊞         Expand non-primitives only
  Click port ▶    Reveal connected neighbour
  Shift+Click ▶   Expand through trivial gates
  Shift+Click +   Recursively expand all
  Shift+Click −   Recursively collapse all
  Shift+Click ⊞   Recursive blocks-only

Hover
  Port interior   Show port name
  Port exterior   Show connected wire
  Block name      Show instance & parent path

Selection
  Double-click    Zoom to block or wire
  Drag            Pan canvas

<!-- details -->

## Loading

| Key     | Description                                              |
| ------- | -------------------------------------------------------- |
| 🔄 Reload | Re-read and re-layout the current schematic from disk |

## Settings

| Control | Description |
| ------- | ----------- |
| ⚙️ Settings → Display widths | Show or hide blue width annotations on multi-bit signals without re-layout. |

## Zooming

| Key                | Description                          |
| ------------------ | ------------------------------------ |
| Scroll wheel       | Zoom in / out at cursor              |
| F                  | Fit entire schematic to canvas       |
| Ctrl + Drag        | Draw a rectangle to zoom into        |
| Double-click block | Zoom to focus on that block          |

## Hover

| Key                | Description                                   |
| ------------------ | --------------------------------------------- |
| Port interior half | Tooltip shows port name                       |
| Port exterior half | Tooltip shows connected wire name & width     |
| Block name area    | Tooltip shows instance name & parent path     |

## Selection

| Key                | Description                                          |
| ------------------ | ---------------------------------------------------- |
| Click +            | Fully expand block (show all children)               |
| Click −            | Collapse block                                       |
| Click ⊞            | Expand non-primitive children only (blocks-only view) |
| Shift + Click +    | Recursively expand all descendants                   |
| Shift + Click −    | Recursively collapse all descendants                 |
| Shift + Click ⊞    | Recursive blocks-only on all descendants             |

## Incremental Expansion

| Key                           | Description                                                                                                                         |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Click port ▶                  | Reveal the block connected to that port                                                                                             |
| Shift + Click port            | Toggle expansion through trivial gates (buffers, NOT, SLICE, CONCAT). Expands to show connected gates and wires; click again to collapse and hide them. |
| Click port ◀ (collapse marker) | Hide the wire and trivial gates for that port                                                                                      |

## Search

| Key                | Description                              |
| ------------------ | ---------------------------------------- |
| Ctrl + F / ⌘F      | Open incremental search overlay          |
| Type query         | Search blocks and wires by name           |
| Enter / ↓          | Jump to next match (expands path if needed) |
| Shift + Enter / ↑  | Jump to previous match                   |
| Tab                | Expand to longest common prefix of matches |
| Esc                | Close search overlay                     |

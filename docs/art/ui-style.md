# UI style

Dark-navy panels with gold trim and serif headings, after the owner's fantasy MMORPG UI reference (2026-10-24). The reference sets the look only; screens and systems stay the ones the game has.

## Palette

| Token | Hex | Use |
|---|---|---|
| Panel | `#151922` | Panel base, bottom of panel gradients |
| PanelRaised | `#252D3A` | Headers, slots, top of panel gradients |
| Trough | `#0D1016` | Bar backgrounds, insets |
| Gold | `#D2B783` | Borders, headings, lozenges, cast fill |
| GoldDim | `#8C7853` | Secondary borders (bar troughs, inset panels) |
| GoldBright | `#F0DDB0` | Emphasis text, key badges |
| Text | `#E6DFCF` | Body text |
| Dim | `#AEB4BF` | Secondary text |
| Hp | `#A94D56` (bright `#D2707A`) | Health, harmful statuses, hard lock |
| Mp | `#4C91C6` | Mana, cost labels |
| Green | `#7EAF8A` | Stamina, beneficial statuses, slidecast window |
| Xp | `#5E9FD0` | Experience bar |

Screens carry these values in their `.model.json`. Colours a controller sets at runtime come from `Shared/Theme.luau`; no other script holds a colour literal for UI.

## Typography

- Headings, titles, names, level numbers: **Accanthis ADF** (`rbxasset://fonts/families/AccanthisADFStd.json`, Bold), the built-in face closest to the reference's Cinzel. Cinzel is not available on Roblox. Window titles are upper case.
- Body, numbers, labels: **Builder Sans** (Medium/Bold).
- Stat columns and the debug log: **Roboto Mono**.

All three ship with the client, so no font asset needs loading.

## Frames

Frames are built from layout objects only; no images are uploaded for UI yet.

- Panel: white background tinted by a `UIGradient` (PanelRaised to Panel, top to bottom), gold `UIStroke`.
- Ornate frame (windows, prompt card): panel plus an inner hairline border (`InnerBorder`) and four gold lozenges on the corners (`CornerTL`…`CornerBR`, a frame turned 45° with a dark core).
- Divider: 1 px gold rule with a transparency gradient that fades at both ends and a lozenge at the centre.
- Bars: trough with a GoldDim edge, fill coloured by `BackgroundColor3` and shaded by a white-to-grey `UIGradient` (so a controller can retint it), a faint sheen on the top half, tag on the left and value on the right.
- Buttons: primary is gold with dark text; secondary is PanelRaised with gold text and edge.
- A `UIGradient` also tints a `TextLabel`/`TextButton`'s own text. Only give one to text objects whose text should be shaded (the gold button); otherwise put the gradient on a frame.

## Floating UI

The owner wants UI to float in the world where it can: interacting with an object shows its UI beside that object, not in a fixed screen panel.

- World prompts: every `ProximityPrompt` is switched to `Custom` on the client by `PromptController` and drawn with the `InteractPrompt` BillboardGui, offset to the right of the object. It shows the key (keyboard key, gamepad button, or a lozenge on touch), action and object text, and a hold-progress fill; tapping or clicking the card holds the prompt.
- Nameplates, the target marker and damage numbers are BillboardGuis over their owner.
- Menus open in the world (owner's choice, 2026-10-25, after VR games): inventory, spellbook, character sheet and trainer appear as a panel standing in front of the character, fixed in place while open. The camera goes first person at the character's head (the character is hidden), movement and world prompts are held, and closing (the window's X or the menu's key) gives the camera back.
  - Readable text on every screen: the panel is placed at the distance where it fills a set share of the view (`ScreenFill`, 0.8 for menus), so its text appears at the same size on a phone, a monitor or an ultrawide. The trainer panel fills 0.5 and sits to the right so the trainer stays visible.
  - Screens stay authored as ScreenGuis with one root `Window` frame; `UIController` moves that frame into the `WorldPanel` SurfaceGui while it is open.
  - Each world screen has a rig in `ReplicatedStorage/UiRigs/<Screen>.model.json`: `Root` stands for the character's head looking ahead (for the trainer, looking at the NPC) and `Panel` gives the panel's direction from the head and its size in studs. Attributes on `Panel`: `ScreenFill` (share of the view, default 0.8) and `PixelsPerStud` (canvas density, default 150). Move or resize `Panel` in Studio to re-author a menu.
- XP and looted items float up over the character (`FloatingGain` BillboardGui, `GainController`) instead of screen toasts.
- The HUD (bars, hotbar, target frame, cast bar, toasts, Notices) stays on the screen.

## HUD layout

- Top left: player plate (level medallion, name, HP, MP, stamina, Focus, status chips) and, under it, the target frame (shown while there is an enemy target).
- Top right: zone plate and the Notices panel (unspent levels, spell picks; hidden when empty).
- Bottom centre: cast bar, hotbar (8 slots, hidden when all are empty unless the spellbook is open), experience bar, key hints.
- Toasts: top centre.

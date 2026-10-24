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
- Personal menus (inventory, spellbook, character sheet) stay as centred screen windows so they stay readable when the camera turns.

## HUD layout

- Top left: player plate (level medallion, name, HP, MP, stamina, Focus, status chips) and, under it, the target frame (shown while there is an enemy target).
- Top right: zone plate and the Notices panel (unspent levels, spell picks; hidden when empty).
- Bottom centre: cast bar, hotbar (hidden when empty), experience bar, key hints.
- Toasts: top centre.

# Character creation

Code: `Server/Services/AvatarService.luau`, `Shared/Avatar.luau`, client `CreatorController`; content `Heritages`, `Appearance`, `Names`; screen `StarterGui/Creator.model.json` with templates `CreatorOption` and `CreatorSwatch`; stage `CreationStage` in `Workspace/Map.rbxmx` (built by `tools/world/build.luau`).

## Flow

- Characters never auto-load (`Players.CharacterAutoLoads = false`, `StarterPlayer.LoadCharacterAppearance = false`). Every spawn goes through `AvatarService.Spawn` → `Player:LoadCharacterWithHumanoidDescriptionAsync`, so the player's Roblox avatar never shows. Respawn after death is `AvatarService` too, after `Players.RespawnTime`.
- A profile with `created = false` still gets a character (the engine copies StarterGui into PlayerGui only on spawn). It has the default look and is parked, anchored, 8 studs under the creation stage's pedestal, which also keeps streaming around the stage.
- The client opens the Creator screen while the snapshot says `created = false`, locks it (`UIController.SetLocked`: no other menu opens, it cannot be closed), hides the HUD and holds the camera on the stage.
- Steps: Race, Body, Hair, Facial Hair, Outfit, Class, Spell (shown only for a caster class). The name sits under the character with previous / next / random. **Begin your journey** sends `CreateCharacter(creation)`.
- The server checks it with `Avatar.ValidateCreation`, stores `name`, `heritage` and `appearance`, trains the starter class (the fresh level-1 profile has exactly one unspent level), learns the starter spell, sets `created = true` and respawns the character with the chosen look at the village. Refusals come back as `Notify` keys shown on the creator's status line.
- Studio and tests skip the screen with the dev command `/newchar [fighter|mage|healer]` (also through `ServerStorage.RunDevCommand`).
- Profiles are in memory until the persistent Data module lands, so the creator shows on every join.

## Rules

| Choice | Source | Rule |
|---|---|---|
| Race | `Content/Heritages` | Families Human, Demi-Human, Heteromorph. Only Human is playable; the rest are listed as locked (detail visible, cannot be picked). Stored in the existing `heritage` field. |
| Body | `Appearance.Genders` | Male / Female on the blocky R15 body: sets the classic face decal and small height/width/depth/head scales. Every hair, beard and outfit is open to both. |
| Skin tone | `Appearance.SkinTones` | Pale, Fair, Tan, Olive, Brown, Deep, picked from swatches on the Body step; colours every limb. Default Fair. |
| Hair | `Appearance.Hair` | 11 free Roblox styles plus Shaved. |
| Facial hair | `Appearance.FacialHair` | 4 styles plus Clean Shaven. |
| Hair colour | `Appearance.HairColors` | Black, Brown, Blonde, Red; one colour for hair and beard. |
| Outfit | `Appearance.Outfits` | 9 classic Shirt + Pants pairs. |
| Name | `Content/Names` | Placeholder list per gender until the name library exists; the server accepts only names in the list for the chosen gender. |
| Class | `Classes.Order` | Any starter class (Fighter, Mage, Healer); Fighter is first and the default. |
| Spell | `Avatar.StarterSpells` | Casters pick exactly one spell (the level-1 pick, §3.2): the class list filtered by `Formulas.CanLearnSpell` on a level-1 build path, so Tiers 0–1. Martial classes send `""`. |

## Preview

The preview is a client-only model from `Players:CreateHumanoidModelFromDescription` built from the same `Avatar.Build(look)` the server spawns, so what the player sees is what they get. Each change rebuilds it on a thread; a newer change discards an older result. It stands on the pedestal facing the camera and plays the stock R15 idle (`Assets.Stock.PreviewIdle`); dragging the centre of the screen turns it. Hair and Facial Hair steps move the camera to the head framing (`CameraHead` / `FocusHead`), the other steps use `CameraFull` / `FocusFull`.

## Roblox avatar API limits (tested in Studio 2026-10-28)

- `Humanoid:ApplyDescription` and `Player:LoadCharacterWithHumanoidDescriptionAsync` are server only ("can only be called by the backend server"). `Players:CreateHumanoidModelFromDescription` works on the client, which is why the preview is local.
- Applying a description yields about 0.4–0.5 s and can fail; overlapping applies on one humanoid are undefined, so the server applies once per spawn and the client only builds new preview models.
- Ownership is not checked: paid and off-sale Marketplace items apply to any player in the experience.
- Catalog hair and beards have baked textures and cannot be recoloured, so colour is a separate asset per colour. Own tintable hair needs uploaded MeshParts.
- Classic clothing is one `Shirt` and one `Pants`, both 2D 585×559 templates wrapped on the body. Layered clothing needs cages and is out of scope.
- Roblox has no gender: body shape comes from body-part meshes or scales. On blocky R15 the scales and the face are what is left.
- Third-party items can be taken off sale, moderated or deleted, and then disappear from characters. Free Roblox items cover only hair, faces and bodies; Roblox's free clothing is modern (jeans, tees).
- With `CharacterAutoLoads` off, StarterGui is not copied until the first spawn, so a player must have a character before any screen exists.
- `rojo serve` does not push service properties; set `Players.CharacterAutoLoads` and `StarterPlayer.LoadCharacterAppearance` in Studio once (the built place has them).

## Catalog audit

| Register row | Creator | Items | Price |
|---|---|---|---|
| `catalog:RobloxFaces` | Roblox | Man Face, Woman Face | free |
| `catalog:RobloxHair` | Roblox | 11 styles × 4 colours | free |
| `catalog:BeardsHairyBusiness` | Hairy Business | Stubble, Well Kept | paid UGC |
| `catalog:BeardsU8DEV` | U8DEV | Trimmed Full Beard, Great Beard | paid UGC |
| `catalog:OutfitsPoor` | po_or | 6 Medieval Tunic shirt + pants colours | paid UGC |
| `catalog:OutfitsATF` | [ATF] The Ravagers | Villager, Cloaked, Hunter shirt + pants | paid UGC |

Swap a set by replacing its ids in `Content/Appearance` and its register row; `Avatar.spec` checks every style has every colour. Replace with own assets when they exist.

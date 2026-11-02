# Economy: gold, shops and quests

Owner request, 2026-10-30. Code: `ShopService`, `QuestService`, `Content/Shop.luau`, `Content/Quests.luau`, `Profile` (schema 6), client `ShopController` and `QuestController`, screens `Shop` and `QuestBoard` (`StarterGui` and `UiRigs`).

## Gold

`Profile.gold` (new characters and migrated saves start with `Profile.StartingGold`, 25). The HUD shows it beside the Focus line (`Bind_GoldText`); the snapshot carries `gold` and `quest`. Quests pay it, shops spend it. There is no selling and no drop of gold from enemies yet.

## Shops

- A vendor is a part tagged `Trainer` with `TrainerType = "Vendor"` and a `ProximityPrompt`; `ShopId` picks the stock in `Content/Shop` (default `inn`). The prompt opens the **Shop** screen (`OpenShop`) instead of the trainer panel.
- `BuyItem(vendor, itemId, count)`: `ShopService.Buy` checks the vendor, reach (the prompt's distance plus slack), stock, price from content, count (at most `Shop.MaxPurchase`), gold and inventory room (`Profile.CanFit`), then pays and adds the item in one `DataService.Update`.
- The Harbor Inn sells bread, water, cooked meat, and minor health and mana potions.

## Quests

- A **board** is a part tagged `QuestBoard`; `QuestService` adds a `ProximityPrompt` to it when it has none. It opens the **QuestBoard** screen (`OpenQuestBoard`).
- `QuestAction(board, action, questId)`: `Accept`, `Turn` or `Abandon`, all range-checked at the board. One active quest per character, saved as `profile.quest = { id, kills }`.
- Quests are extermination only (`Content/Quests`). Accepting spawns the quest's goblin party as a station group (`GroupService`) at a dry, level spot outside safe zones, `Tuning.Quests.SpawnMin` to `SpawnMax` (150 to 300) studs from the board, within 80 degrees of north (the sea is south of the Harbor), so the party materializes at once and dematerializes with the usual rules. The spot search tries 24 random points, then 200 studs due north.
- A kill of an enemy id in the quest's `targets` by the player (a summon's kill credits its owner) adds one; the quest is done at `count`. Turn in at the board for gold and XP; the leftover party is removed. Abandoning removes it too.
- On join, a character holding an unfinished quest gets a fresh party for the remaining kills.

## Pylon and spawns

- Players arriving (joining) spawn at the **dock**: the `SpawnLocation` tagged `ArrivalSpawn`. After a death they respawn at the **inn**: the `SpawnLocation` tagged `RespawnPoint` (`AvatarService` switches `RespawnLocation` when the character dies; `ZoneService.UseRespawnPoint`).
- The **Pylon** is a model tagged `Pylon`. Only the Gate spell goes there (`Gate Pylon`, dev only for now); the Pylon is not interactable. Gate lands on the Pylon's `Arrival` part, else 10 studs south of it. Gate with no argument goes to the inn.

## Not done

- Selling, gold drops, a currency item economy, quest chains, more quest kinds, and Pylon unlocking as a fast-travel network.

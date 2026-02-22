# Ebonhold Bar Builder

**Automatic action bar management for leveling characters on Project Ebonhold.**

Ebonhold Bar Builder runs in the background while you play, saving your action bar layout at every level and restoring it when you return. It handles spell rank changes, spec switches, stance bars, and the full 1–80 leveling cycle without requiring any manual configuration.

---

## Table of Contents

- [What Does This Addon Do?](#what-does-this-addon-do)
- [Installation](#installation)
- [Per-Level Mode](#per-level-mode)
- [Breakpoint Mode](#breakpoint-mode)
- [Choosing a Mode](#choosing-a-mode)
- [The Explorer UI](#the-explorer-ui)
- [The Slot Editor](#the-slot-editor)
- [The Timeline](#the-timeline)
- [Templates](#templates)
- [Import & Export](#import--export)
- [Slash Commands](#slash-commands)
- [Gotchas](#gotchas)
- [How It Works — Under the Hood](#how-it-works--under-the-hood)
- [Technical Reference](#technical-reference)

---

## What Does This Addon Do?

The core functionality:

- **Saves** a snapshot of all action bars whenever they change or when a level-up occurs.
- **Restores** the correct bar layout when arriving at a previously visited level.
- **Tracks all 10 action bars**, including stance-specific bars for Warriors, Druids, and Rogues.
- **Supports all 5 Ebonhold specs** independently — each spec maintains its own complete set of saved layouts.
- **Handles spell rank changes** automatically — if a saved layout contains Frostbolt (Rank 7) but the character is at a level where only Frostbolt (Rank 3) is available, the addon places the appropriate rank.

---

## Installation

1. Download or clone this repository.
2. Place the `EbonholdBarBuilder` folder into the WoW `Interface/AddOns` directory.
3. Verify the folder structure:
   ```
   Interface/AddOns/EbonholdBarBuilder/EbonholdBarBuilder.toc
   Interface/AddOns/EbonholdBarBuilder/Core.lua
   Interface/AddOns/EbonholdBarBuilder/Settings.lua
   ... (all other .lua files)
   ```
4. Restart WoW or `/reload` if already logged in.

---

## Per-Level Mode

This is the default mode. It saves a complete copy of the action bars at every level the character passes through.

### Scenario: Leveling a fresh character

A new Mage begins leveling:

1. **Level 1** — Fireball is placed on slot 1. The addon detects the bar change and saves the layout.
2. **Level 4** — Frostbolt is learned and added to slot 2. The new layout is saved.
3. **Level 6** — Fire Blast is learned; several slots are rearranged. Saved after the changes settle.
4. **Level 10** — Frost Nova on slot 3, Polymorph on slot 4. Saved.

None of this requires any user action. The addon watches for bar changes and records them automatically.

### Scenario: Dying and returning to level 1

The character dies at level 30 and respawns at level 1. Bars are empty — standard Ebonhold behaviour.

The addon detects the return to level 1 and restores the layout it saved at that level. As the character levels back through 2, 3, 4, and onward, each level's saved layout is restored on arrival. By level 30, the bars match exactly what they were before death.

Changes can be made at any point during re-leveling. Moving a spell to a different slot updates that level's saved layout — the addon records the new arrangement over the old one.

### Scenario: Leveling a class for the second time

A player rolls a second Warrior. The first Warrior's leveling journey already populated layouts for levels 1 through 80. Because layouts are stored per-character, the second Warrior starts with no saved data — but the **spell cache** (which tracks which spells are available at which levels) is shared account-wide across all characters of the same class. This means breakpoint mode and spell rank adjustment work immediately on the second character, informed by what the first character observed.

In per-level mode, the second character builds its own layouts as it levels. Each character's bar preferences are independent.

---

## Breakpoint Mode

Per-Level mode stores up to 80 full bar snapshots per spec. Breakpoint mode takes a more targeted approach: the user defines a handful of breakpoint levels, and the addon derives everything in between.

### Scenario: Setting up a Priest with breakpoints

A Priest's bars change meaningfully at specific milestones — when they learn Power Word: Shield, Mind Blast, Shadow Form at 40, and so on. Rather than recording 80 individual layouts, the user defines breakpoints at the levels that matter.

1. Switch to breakpoint mode: `/ebb mode breakpoint`
2. Open the Explorer UI: `/ebb ui`
3. Define a breakpoint at **level 1** with starter spells arranged.
4. Define a breakpoint at **level 10** — Renew, SW:Pain, and the early rotation.
5. Define a breakpoint at **level 40** — Shadow Form changes the entire bar structure.
6. Define breakpoints at **level 60** and **level 70** for raid-ready layouts.

When the character reaches level 25 (which has no explicit breakpoint), the addon finds the nearest breakpoint at or below that level — level 10 — and uses it as the basis. It then adjusts spell ranks to match level 25. If the level 10 breakpoint has Smite (Rank 2), and by level 25 the character would know Smite (Rank 5), the addon places Smite (Rank 5) in that slot.

The result is the correct bar structure with level-appropriate spell ranks, derived from a single breakpoint definition.

### When breakpoints are the better choice

- The user prefers a curated, hand-crafted bar experience over an auto-recorded one.
- Bar setups are being shared with other players via import/export, and compact data is preferred.
- The user wants to define bars ahead of time in the Explorer UI rather than recording them during gameplay.

---

## Choosing a Mode

Switch between modes at any time with `/ebb mode` (toggles) or explicitly with `/ebb mode perlevel` and `/ebb mode breakpoint`.

Existing saved layouts are not deleted when switching modes. Per-level data and breakpoint data coexist — the mode setting only controls which system is used to decide what happens on level-up.

---

## The Explorer UI

The Explorer is the primary configuration interface. Open it with `/ebb ui` or by clicking the minimap button.

It provides a visual overview of all saved bar data and supports direct editing of layouts at any level.

### Layout

- **Spec selector** — A dropdown at the top allows viewing and editing layouts for any of the 5 specs, not just the currently active one. The active spec can also be switched directly from here via Project Ebonhold's spec system.
- **Level list** — The left panel displays levels 1 through 80. Levels with saved layouts are highlighted, breakpoint levels are distinctly marked, and the character's current level is indicated. Clicking a level loads its bar layout into the grid.
- **Bar grid** — The main area shows all 10 action bars (12 slots each, 120 total) for the selected level. Each slot displays its icon, name, and type. Empty slots are visually distinct. For stance-based classes, the stance bars are labelled with their actual stance names (e.g. "Battle Stance" rather than "Bar 7").
- **Bar toggles** — Each bar row has a checkbox to include or exclude it from capture and restore. This is useful for bars managed manually (such as a consumables bar) that should not be overwritten by the addon.
- **Edit mode** — Clicking a slot enters edit mode. Any slot can be assigned a spell, macro, item, mount, pet, or equipment set. Changes are staged — nothing is committed until Save is pressed. Closing the Explorer with unsaved changes triggers a confirmation prompt.

### Toolbar

The toolbar along the top of the Explorer provides additional operations:

- **Copy / Paste** — Copy an entire level's layout and paste it to a different level. Spell ranks are automatically adjusted to match the target level.
- **Push Up / Push Down** — Propagate the current level's layout to all saved levels above or below. In breakpoint mode, pushing stops at the next breakpoint boundary. This is useful for applying a bar rearrangement across many levels at once.
- **Undo** — Reverts the last change. The addon maintains a stack of up to 20 undo steps per session.
- **Save Template / Load Template** — Save a layout as a reusable named template, or apply an existing template to the current level.
- **Import / Export** — Share layouts with other players or create backups.
- **Backup / Restore** — Quickly capture or restore the current level's live bars.

---

## The Slot Editor

Clicking a slot in the Explorer during edit mode opens the Slot Editor — a categorised picker for assigning content to action bar slots.

The picker is organised into categories:

- **Spells** — All spells from the spellbook, grouped by tab. Each entry shows its icon, name, rank, and whether it is available at the selected level (based on the spell cache). A "Highest Rank Only" toggle collapses multi-rank spells down to the best available rank.
- **Macros** — Both character-specific and account-wide macros, displaying name, icon, and body text.
- **Items** — Items from bags and equipped gear.
- **Mounts** — Known mounts.
- **Pets** — Known companion pets.
- **Equipment Sets** — Saved equipment manager sets.

After selecting an entry and confirming, the Explorer immediately previews the change. Additional slots can be edited before committing all changes at once.

---

## The Timeline

The Timeline provides a condensed view of the entire leveling progression for the selected spec. Each level from 1 to 80 is represented as a row, colour-coded by state:

- **Breakpoint** — A level explicitly marked as a breakpoint.
- **Saved** — A level with a directly recorded layout.
- **Derived** — A level whose layout would be computed from the nearest breakpoint below.
- **Current** — The character's current level.
- **Empty** — No data exists for this level.

Between adjacent levels that have data, the Timeline displays a diff summary — which slots changed, what spells were added or removed, and the total number of occupied slots. This is useful for identifying where bars underwent major changes and whether additional breakpoints would be beneficial.

---

## Templates

Templates are named layout presets saved within a spec. Common uses include:

- Maintaining separate "PvP" and "PvE" bar layouts that can be applied at any level.
- Storing a curated arrangement for reuse across multiple breakpoints.
- Creating a backup of a layout before making experimental changes.

Templates are created and applied from the Explorer toolbar. When a template is applied to a level, spell ranks are automatically adjusted to match that level using the same derivation system as breakpoint mode.

Templates belong to a specific spec. They can be transferred between specs via the import/export system.

---

## Import & Export

The addon supports three levels of import/export:

- **Single Level** — Export one level's layout as a compact encoded string. Suitable for sharing a specific setup.
- **Breakpoints Only** — Export all breakpoint levels and their layouts. Ideal for breakpoint-mode users sharing curated milestone configurations.
- **Full Backup** — Export everything for the current spec: all levels, all breakpoints, enabled/disabled slot states, and spec name. This is a complete portable backup.

Export strings are Base64-encoded and prefixed with `EBB:v1:` for identification. They include the exporting character's class — importing a string from a different class triggers a mismatch warning. The import proceeds regardless (the user may have a reason), but spell-based slots will likely fail to restore.

To export: open the Explorer → click Import/Export on the toolbar → select the export type → copy the string.

To import: open the Explorer → click Import/Export → paste the string → preview the contents → confirm.

---

## Slash Commands

| Command | Description |
|---|---|
| `/ebb` | Display the command list |
| `/ebb ui` | Open the Explorer UI |
| `/ebb save` | Manually save current bars |
| `/ebb restore` | Manually restore bars for the current level |
| `/ebb status` | Display current spec, mode, slot count, and layout info |
| `/ebb list` | List all saved levels in the current spec |
| `/ebb specs` | List all 5 specs with their layout counts |
| `/ebb mode` | Toggle between Per-Level and Breakpoint recording modes |
| `/ebb mode perlevel` | Switch to Per-Level mode |
| `/ebb mode breakpoint` | Switch to Breakpoint mode |
| `/ebb minimap` | Toggle minimap button visibility |
| `/ebb label <bar#> <n>` | Rename a bar label (e.g. `/ebb label 7 Battle Stance`) |
| `/ebb resetlabels` | Reset all bar labels to defaults |
| `/ebb clear` | Delete all saved layouts for the current spec |
| `/ebb resetcache` | Clear and rebuild the spell level cache |
| `/ebb enable` | Re-display the enable/disable popup |
| `/ebb diagnose [bar\|all]` | Inspect live slot data (troubleshooting) |
| `/ebb debug` | Toggle debug message output |

---

## Gotchas

These are expected behaviours and design decisions that are worth being aware of during normal use.

### Bars cannot be restored during combat

WoW's API prohibits addons from modifying action bars while in combat. If a restore is triggered during combat (e.g. a level-up mid-fight), it is queued and applied the moment combat ends.

### The first character of a class builds the spell cache from scratch

The addon maintains a spell cache that records which spells become available at which levels. This cache is shared account-wide across all characters of the same class. The first character of a given class populates this cache as it levels and visits trainers. Subsequent characters of the same class benefit from the existing cache immediately.

If the cache becomes stale or incorrect, `/ebb resetcache` clears it and rescans the current spellbook.

### Macros are matched by name

When restoring a macro to a bar slot, the addon locates it by name using `GetMacroIndexByName`. If multiple macros share the same name (e.g. one character macro and one account macro), the addon may select the wrong one. A warning is printed to chat when duplicate macro names are detected during a save.

### Vehicle and possess bars are ignored

When the character is in a vehicle or under mind control, the addon does not capture or restore bars. These states use temporary bar overrides that are not relevant to the character's normal layout.

### Stance bars are tracked, with a caveat on bar 1

For Warriors, Druids, and Rogues, the addon tracks stance/form-specific bars (bars 7–10). These map to different stances depending on class — bar 7 is Battle Stance for Warriors but Stealth for Rogues.

However, bar 1 (the main action bar) visually swaps when entering a stance due to Blizzard's bonus bar system. The addon captures whatever is in slots 1–12 at the time of capture, regardless of the active stance. If a capture occurs while in a non-default stance, bar 1 will reflect the stance-swapped content.

### Undo is session-only

The undo stack (up to 20 entries) exists only for the current play session. Logging out clears the undo history. Saved layouts themselves are persistent — only the ability to reverse recent Explorer edits resets on logout.

### Session layouts vs. persistent layouts

Some layouts are stored only in the current session (e.g. auto-captured layouts during intermediate states). These appear in the Explorer and are used for restores, but they do not survive a logout. Explicitly saved layouts — via the Explorer, `/ebb save`, or the automatic save on level-up — are written to SavedVariables and persist across sessions.

### Derived layouts are not stored

In breakpoint mode, layouts derived from breakpoints are computed on the fly for each restore. They are not saved to disk. To persist a derived layout, copy or save it explicitly in the Explorer.

### Import strings are class-tagged

Importing a string exported by a different class produces a mismatch warning. The import will proceed, but spell-based slots will fail to restore since the spell names will not match the importing character's spellbook.

---

## How It Works — Under the Hood

This section covers the internal systems for readers who want to understand the addon's architecture. It is not required for normal use.

### Architecture Overview

The addon is organised into loosely coupled modules that communicate through a shared namespace (`EBB`). Each `.lua` file owns one system:

| Module | Responsibility |
|---|---|
| **Core** | Initialisation, event routing, level-up handling, slash commands |
| **Settings** | Constants, per-character configuration, recording mode |
| **Profile** | Spec management, per-slot enabled/disabled states |
| **Layout** | Per-level layout storage and retrieval (persistent + session) |
| **Capture** | Reading live action bar state into snapshots |
| **Restore** | Writing saved layouts back to live action bars |
| **ActionBar** | Low-level WoW API wrappers for slot reading and writing |
| **ClassBars** | Class-specific stance bar metadata and display mapping |
| **Spec** | Project Ebonhold spec detection, switching, and synchronisation |
| **Keyframe** | Breakpoint management and layout derivation (named `Keyframe` in code) |
| **SpellCache** | Account-wide spell rank/level availability tracking |
| **Clipboard** | Copy/paste, push up/down, diff computation, undo stack |
| **Template** | Named layout presets with rank-adjusted application |
| **Timeline** | Level-by-level diff summaries and timeline data model |
| **ImportExport** | Base64 serialisation and deserialisation of layout data |
| **Diagnose** | Live slot inspection and troubleshooting tools |
| **FirstRun** | Per-character opt-in dialog and enabled state management |
| **Explorer** | Main UI panel behaviour and event handling |
| **SlotEditor** | Spell/item/macro picker behaviour |
| **MinimapButton** | Minimap icon |

The UI modules are split into pairs — a `ui*.lua` file that creates the visual frames and a corresponding behaviour file that wires up the logic.

> **Note on terminology:** The codebase uses the term "keyframe" internally for what this documentation calls a "breakpoint." The module is `Keyframe.lua`, the storage key is `keyframes`, and the API methods use `Keyframe:Set()`, `Keyframe:GetAll()`, etc. Both terms refer to the same concept — milestone levels from which intermediate layouts are derived.

### Data Storage

Two SavedVariables are used:

- **`EBB_DB`** (account-wide) — Contains the spell cache, shared across all characters. Accumulates knowledge about which spells are available at which levels for each class.
- **`EBB_CharDB`** (per-character) — Contains the enabled state, active spec index, last known level, settings, and all spec data. Each of the 5 specs stores its own layouts, breakpoints, templates, and enabled-slot mask.

### The Capture/Restore Cycle

**Capture** reads all 120 action bar slots (10 bars × 12 slots) via WoW's action bar API. For each slot, it identifies the type (spell, macro, item, companion, equipment set, or empty) and records the relevant metadata — name, rank, icon, and ID. Only slots marked as "enabled" in the current spec's profile are captured; disabled slots are skipped.

Captures are triggered by the following events:

- `ACTIONBAR_SLOT_CHANGED` — any bar modification (drag, drop, remove).
- `LEARNED_SPELL_IN_TAB` — learning a new spell.
- `UPDATE_BONUS_ACTIONBAR` — stance changes.
- `PLAYER_LEVEL_UP` — level-ups (debounced to wait for the spellbook to update).
- Manual `/ebb save`.

A debounce timer (1.5 seconds) prevents rapid successive captures during multi-slot rearrangements.

**Restore** takes a saved layout and attempts to place each slot's content onto the live action bars. The process varies by type:

- **Spells** — placed via `PickupSpellByName` with the appropriate rank.
- **Macros** — located by name via `GetMacroIndexByName`, placed via `PickupMacro`.
- **Items** — placed via `PickupItem`.
- **Companions** (mounts/pets) — placed via `PickupCompanion`.
- **Equipment Sets** — placed via `PickupEquipmentSetByName`.
- **Empty slots** — cleared using `PickupAction` + `ClearCursor`.

All of these are protected functions that cannot be called during combat. The addon defers to `PLAYER_REGEN_ENABLED` (end of combat) when necessary.

### The Spell Cache

The spell cache addresses a fundamental limitation: WoW's API does not provide a way to query "what rank of Frostbolt should a Mage have at level 22?" The spellbook only reflects what the current character currently knows.

The cache works by observation. Each time the addon captures bars or scans the spellbook, it records every spell name, rank, and the level at which it was observed. It also scans the trainer window when a class trainer is visited, picking up spells that haven't been learned yet and recording their training level.

Over time and across multiple characters of the same class, the cache builds a complete picture: Frostbolt (Rank 1) at level 4, Frostbolt (Rank 2) at level 8, and so on. This data is stored account-wide in `EBB_DB`.

The cache stores the lowest observed level for each spell+rank combination, along with the icon and spellbook tab. If the addon later observes the same spell at a lower level (e.g. from an alt that trained earlier), the entry is updated downward.

### Breakpoint Derivation

When a layout is needed for a level that has no saved data (in breakpoint mode), the addon locates the nearest breakpoint at or below that level and derives a layout from it.

Derivation proceeds slot by slot:

1. If the slot is empty, it remains empty.
2. If the slot contains a spell, the addon looks up the spell name in the cache and selects the highest rank available at the target level. If no rank is available (the spell hasn't been learned at that level), the slot becomes empty with an internal note about the unavailable spell.
3. All other slot types (macro, item, companion, equipment set) are copied as-is.

The result mirrors the breakpoint's structure with level-appropriate spell ranks. Derived layouts are used for restores but are not persisted automatically.

### The Spec System

The addon integrates with Project Ebonhold's spec system, which supports up to 5 specialisations per character. It hooks into the spec API at multiple points:

- `SpecService.ApplySpec` — invoked when the server applies a spec change.
- `Spec.UpdateSelectedSpec` — invoked when the client UI updates the selected spec.
- Server event `SEND_PLAYER_SPEC_INDEX` — a fallback for when direct hooks are unavailable.

A cascading hook strategy is used: the most reliable hook is attempted first, with fallbacks tried in sequence. A 5-second timeout detects cases where a spec switch was requested but never confirmed by the server.

On spec switch, the addon saves the current bars to the outgoing spec, activates the incoming spec's profile, and restores the appropriate layout. If no layout exists for the current level in the new spec, the addon falls back to the most recently saved level or auto-captures the current bars as a starting point.

On clients without Project Ebonhold (which lack the multi-spec system), the spec system degrades gracefully — it confirms immediately and the addon operates on a single spec.

### Push Up / Push Down

The push system propagates a layout from one level to many. When pushing "up" from level 20, the addon iterates over every saved level above 20 (up to the next breakpoint boundary in breakpoint mode, or level 80) and computes a per-target diff.

For each target, the source layout is compared against that specific target. Slots where the source differs are updated; matching slots are left unchanged. Spell ranks are adjusted per-target using the breakpoint derivation system. By default, pushing is additive — it does not clear target slots that are empty in the source. An overwrite mode exists for full replacement.

This is not a simple "copy to all" — it is an intelligent merge that respects each target level's existing content.

---

## Technical Reference

### Action Bar Slot Numbering

WoW uses a flat slot numbering system from 1 to 120:

| Slots | Bar |
|---|---|
| 1–12 | Action Bar 1 (main bar, affected by stance/bonus bar) |
| 13–24 | Action Bar 2 |
| 25–36 | Action Bar 3 |
| 37–48 | Action Bar 4 |
| 49–60 | Action Bar 5 |
| 61–72 | Action Bar 6 |
| 73–84 | Stance Bar A (bar 7) |
| 85–96 | Stance Bar B (bar 8) |
| 97–108 | Stance Bar C (bar 9) |
| 109–120 | Stance Bar D (bar 10) |

Bars 7–10 are used by the bonus/stance bar system. Their meaning varies by class:

| Bar | Warrior | Druid | Rogue |
|---|---|---|---|
| 7 | Battle Stance | Cat Form | Stealth |
| 8 | Defensive Stance | — | — |
| 9 | Berserker Stance | Bear Form | — |
| 10 | — | Moonkin Form | — |

Classes without stances do not use bars 7–10 during normal gameplay, though the addon still tracks them.

### Slot Types

Each captured slot is stored as a table with a `type` field and type-specific metadata:

| Type | Fields | Notes |
|---|---|---|
| `spell` | `name`, `rank`, `icon` | Rank may be an empty string for rankless spells |
| `macro` | `name`, `id`, `body`, `icon` | `id` is the macro index at capture time |
| `item` | `name`, `id`, `icon` | `id` is the item ID |
| `companion` | `id`, `companionType`, `icon` | `companionType` is `"MOUNT"` or `"CRITTER"` |
| `equipmentset` | `setName`, `icon` | Matched by name on restore |
| `empty` | — | Slot contains nothing |

### Restore Priority and Failure Handling

When restoring a slot, the addon attempts placement in this order:

1. **Spells** — `PickupSpellByName(name, rank)`. If the spell or rank is not known at the current level, the slot is skipped with a verbose warning.
2. **Macros** — Located via `GetMacroIndexByName`. Account macros occupy indices 1–36; character macros are 37+. If no macro with the saved name exists, the slot is skipped.
3. **Items** — `PickupItem(name)`. If the item is not in the character's inventory, the slot is skipped.
4. **Companions** — `PickupCompanion(type, id)`. If the companion is not known, the slot is skipped.
5. **Equipment Sets** — `PickupEquipmentSetByName(name)`. If the set does not exist, the slot is skipped.

Slots that fail to restore are left as-is. The addon does not clear a slot on failure — it only modifies slots it can successfully place.

### Timing and Debounce

Several timing mechanisms prevent race conditions and redundant operations:

- **Capture debounce** (1.5s) — After the first `ACTIONBAR_SLOT_CHANGED` event, the addon waits 1.5 seconds before reading bars. This allows multi-slot rearrangements to complete before saving.
- **Restore delay** (0.5s) — A short delay after initialisation and level-up events before attempting a restore. This gives the client time to finish loading.
- **Level-up debounce** — On level-up, the addon waits for `LEARNED_SPELL_IN_TAB` (indicating the spellbook has updated with new spells) before processing the level change. A 3-second timeout ensures processing continues if no new spells are learned.
- **Restore-in-progress flag** — While a restore is running, capture events are suppressed. Without this, partially-restored bar states would be captured as the "real" layout.
- **Recently-finished window** — For a brief period after a restore completes, captures remain suppressed. This prevents delayed slot-change events (fired by the game after item placement) from triggering a new capture.

### What the Addon Cannot Do

- **Move abilities between bars automatically.** The addon records and restores layouts — it does not reorganise them. Changing which slot a spell occupies at a specific level requires either saving a new arrangement (per-level mode) or defining a breakpoint with the desired layout (breakpoint mode).
- **Restore spells the character has not learned.** If a saved layout contains a spell at a rank the character does not yet know, that slot is skipped.
- **Work across different classes.** Layouts are class-specific. Importing a Warrior export onto a Mage is technically possible but spell slots will fail to restore.
- **Modify bars during combat.** This is a WoW API restriction. The addon queues changes and applies them when combat ends.
- **Guarantee macro restoration if macros have been deleted or renamed.** Macros are identified by name. If the name changes or the macro no longer exists, the slot cannot be restored.

---

## License

This addon is provided as-is for use on Project Ebonhold.

---

*Ebonhold Bar Builder v0.2.0 — by supertuesday*

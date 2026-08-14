# MiniArenaDebuffs - Support Reference

Accurate as of addon version 5.0.0. Everything below is derived from the addon source.

## What the addon does

MiniArenaDebuffs shows the debuffs that YOU have applied to arena enemies as a row of
icons next to each arena frame. Each icon has a cooldown swipe and countdown text.
It always shows only the player's own harmful auras (the aura filter is fixed to
"HARMFUL|PLAYER"); there is no option to show other players' debuffs.

It is intended for tracking DoTs in arena, e.g. Flame Shock, Rake/Rip, Unstable
Affliction/Agony/Corruption/Wither, Moonfire/Sunfire, Shadow Priest and Unholy DK dots.

## Basic facts

| Item | Value |
|---|---|
| Addon version | 5.0.0 |
| Supported interface version | 120100 (12.1), i.e. WoW Midnight |
| Saved variables | MiniArenaDebuffsDB (account-wide, shared by all characters) |
| Optional dependencies | Masque, sArena_Reloaded |
| Slash commands | /miniarenadebuffs and /miniad |
| Options location | Game Menu -> Options -> AddOns -> MiniArenaDebuffs |
| Download | CurseForge (project "miniarenadebuffs") |
| Support | Discord: https://discord.gg/UruPTPHHxK |

## Slash commands

- `/miniarenadebuffs` or `/miniad` - opens the options panel.
- `/miniarenadebuffs test` or `/miniad test` - toggles test mode (same as the Test
  button in options).
- Any other argument just opens the options panel. There are no other subcommands.

## How the icons are drawn

The real arena icons are the game's AuraContainer system: the engine tracks and renders
the auras itself, because addons can no longer read aura data directly (it is "secret").
Test mode is the exception, since its icons are synthetic timers rather than real auras,
and the addon draws those itself.

One pair of options is feature-detected rather than always present: Glow on Pandemic and
Pandemic Color need the engine's refresh-window regions, which arrived after 12.1.0, so
on an early 12.1 build they are hidden.

## Where debuffs are anchored

For each arena slot 1, 2, 3, ... the addon picks an anchor frame in this order:

1. The Custom Anchor override for that slot, if set (a frame global name typed by the
   user). If the named frame does not exist, the addon prints
   `Bad anchor '<name>' for arena<N>.` in chat and falls through to the default.
2. `sArenaEnemyFrame<N>` if sArena is loaded.
3. `CompactArenaFrameMember<N>` (the default Blizzard arena frames), but only when
   sArena is NOT loaded. If sArena is loaded the addon never falls back to the Blizzard
   frames, because they would be invisible.

The icon row is placed relative to the anchor frame based on the Grow setting:

- Grow RIGHT: row starts at the frame's right edge and grows right.
- Grow LEFT: row starts at the frame's left edge and grows left (first icon nearest
  the frame).
- Grow CENTER: the row is centered on the frame. The addon anchors the row's center to
  the frame's center and lets the game lay the icons out inside it, so no width is
  measured.

Offset X / Offset Y shift the row from that anchor point.

## Test mode

- Toggled by the "Test" button in options or `/miniad test`.
- If real anchor frames are visible, test icons attach to them. Otherwise the addon
  shows 3 fake arena frames (colored boxes labeled arena1..arena3) near the right of
  the screen so you can configure position and size outside arena.
- Test icons use fixed sample spells: Moonfire (6s), Vampiric Touch (12s, 2 stacks),
  Flame Shock (20s), Rip (45s), Rake (75s). The durations are staggered so the Color
  Countdown bands (red/yellow/white) can all be previewed.
- Test mode automatically turns itself off when you enter combat. If you press Test
  while in combat, the addon prints "Can't test during combat, we'll test once combat
  drops."

## Options: main panel (MiniArenaDebuffs)

Header text: "Shows your debuffs on arena frames." Buttons at the top right: "Test"
(toggles test mode) and "Reset" (asks "Are you sure you wish to reset to factory
settings?" then resets all settings to defaults and prints "Settings reset to
default."; blocked in combat).

Checkboxes:

| Option | Default | What it does |
|---|---|---|
| Reverse Swipe | off | Reverses the cooldown swipe animation direction. |
| Hide Swipe | off | Hides the cooldown swipe animation on icons. |
| Hide Numbers | off | Hides the cooldown countdown numbers on icons. |
| Hide Unimportant | off | Hides player-cast debuffs that Blizzard flags as unimportant (nameplateShowPersonal = false). |
| Show Stacks | on | Shows the stack count in the icon corner on debuffs with more than one application. |
| Show Milliseconds | off | Shows tenths of a second on countdowns under 5 seconds, e.g. "4.3". |
| Color Countdown | off | Colors the countdown text by time remaining: red under 5 seconds, yellow under a minute, white above. |
| Zoom Icons | on | Crops Blizzard's silver border off the spell art so the icon sits flush. Turn it off to show the art exactly as Blizzard draws it. A Masque skin brings its own crop and ignores this, so with Masque installed the toggle only takes effect after a reload. |
| Glow on Pandemic | off | Glows an icon while its debuff is inside the refresh (pandemic) window, driven by the game engine. Only shown on clients that support pandemic regions (per source comments, 12.1.5+; feature-detected, so it can be absent on early 12.1 builds). |
| Pandemic Color | orange (R 1, G 0.6, B 0.1) | Color swatch for the pandemic glow. Only shown together with Glow on Pandemic. No opacity control. |

Sliders (always present):

| Option | Default | Range | Step |
|---|---|---|---|
| Icon Size | 36 | 10 to 200 | 1 |
| Icon Spacing | 0 | 0 to 50 | 1 |
| Max Icons | 6 | 1 to 10 | 1 |
| Font Scale | 1.0 | 0.5 to 1.5 | 0.05 |

Font Scale scales the countdown and stack text relative to the icon size.

## Options: Position & Sort sub-panel

Header: "Where the icon row sits relative to each arena frame, and the order icons
appear in."

| Option | Default | Values |
|---|---|---|
| Grow | RIGHT | RIGHT, LEFT, CENTER |
| Offset X | 0 | -250 to 250, step 1 |
| Offset Y | 0 | -250 to 250, step 1 |
| Sort Method | INDEX | INDEX, TIME |
| Sort Direction | + | "Ascending (+)", "Descending (-)" |

- Sort Method INDEX: icons appear roughly in application order (unsorted / by aura
  instance ID).
- Sort Method TIME: icons sorted by time remaining (expiration).
- Sort Direction reverses the chosen order.

## Options: Spell Filter sub-panel

Header: "Limits which of your debuffs are shown."

| Option | Default | Values |
|---|---|---|
| Mode | Off | Off, Only Listed Spells, All But Listed Spells |
| Add Spell | (empty) | Type a spell name or spell ID; a suggestion popup appears |

- "Only Listed Spells" shows just the spells in the list; "All But Listed Spells"
  hides them.
- If the Mode is "Only Listed Spells" but the list is empty, no filtering happens
  (an empty include list would hide everything, so it is treated as no filter).
- Adding a spell also adds every spell ID that applies an aura under the same name.
  This is deliberate: the aura the game applies often has a different ID than the one
  in the spellbook. The list shows one row per spell name; removing a row removes all
  of its ID variants.
- The spell-name search index is English-only (enUS names, about 7,870 names covering
  about 26,000 IDs). On a non-English client, name search will not match; typing an
  exact spell ID still works.
- Picker keys: type to see suggestions, Up/Down arrows walk the list, Enter accepts
  the highlighted (or best) suggestion, Escape clears and closes.

## Options: Custom Anchors sub-panel

Header: "Override which frame each arena slot anchors to. Useful for frame addons such
as ElvUI or GladiusEx. Leave blank to use the default arena frames."

| Option | Default | What to enter |
|---|---|---|
| Arena 1 Frame | (blank) | Exact global frame name to anchor arena1's icons to |
| Arena 2 Frame | (blank) | Exact global frame name for arena2 |
| Arena 3 Frame | (blank) | Exact global frame name for arena3 |

Blank means: use sArena frames if sArena is loaded, otherwise Blizzard's
CompactArenaFrameMember frames. If the typed frame name does not exist, the addon
prints `Bad anchor '<name>' for arena<N>.` in chat and uses the default instead.
Only slots 1-3 have override fields.

## Integrations

- sArena / sArena_Reloaded: auto-detected. When `sArenaEnemyFrame1` exists, icons
  anchor to sArena frames automatically, and the addon deliberately does not fall back
  to the (invisible) Blizzard frames.
- Masque: supported for icon skinning through the group name "MiniArenaDebuffs", on the
  real arena icons and the test-mode ones alike, so a skin looks the same in a match and
  in the preview. A skin is fitted to a button when that button is created, so changing
  skin wants a UI reload. Where Glow on Pandemic is available the button's size can no
  longer be read back either, so changing Icon Size re-lays the row but leaves the skin
  art at its old size until a reload.
- ElvUI / GladiusEx / other unit frame addons: no automatic detection; use the Custom
  Anchors panel and type the frame name.
- Edit Mode: while Blizzard's Edit Mode is open, the game feeds fake placeholder auras
  to all aura containers, so the addon hides its real displays for the duration and
  shows them again afterwards (this fixed placeholder icons appearing in edit mode in
  3.0.1).

## Combat and instance restrictions

- Settings cannot be applied during combat. Changing a setting in combat prints
  "Can't apply settings during combat."
- In Midnight the options panel cannot be opened during combat; trying prints
  "Can't do that during combat."
- Test mode exits automatically when combat starts.
- Icon styling (size, font, swipe settings, etc.) cannot be pushed to the live buttons
  while auras are "secret". That covers combat, but also
  out-of-combat time inside arenas, Mythic+ and encounters. Changes made then are
  stored and re-applied automatically once the restriction lifts (retried every second
  and on leaving combat), so a mid-arena change may not be visible until the
  restriction ends.
- Reset is blocked in combat.

## Version history highlights

- 5.0.0: 12.0 support dropped; Masque skinning for the real arena icons; Zoom Icons;
  pandemic border and glow merged into one glow.
- 4.0.0: 12.1 improvements.
- 3.0.0: 12.1 support (AuraContainer path).
- 2.3.0: pandemic glow and desaturate.
- 2.2.0: Font Scale option.
- 2.1.0: Hide Numbers ("hide cooldown text") and Hide Unimportant options.
- 2.0.0: Masque integration, major refactor.
- 1.5.0: sArena support.

## Troubleshooting by symptom

### "No icons show in arena at all"

- The addon only shows debuffs YOU applied. Someone else's DoTs never show.
- Check Max Icons is not set very low and Icon Size is reasonable (min 10).
- If you use a custom unit frame addon (ElvUI, GladiusEx, ...), the default anchors
  (sArena or Blizzard CompactArenaFrameMember frames) may be hidden or missing. Set
  the frame names in Options -> MiniArenaDebuffs -> Custom Anchors.
- If Spell Filter Mode is "Only Listed Spells", only the listed spells show. Set Mode
  to Off to rule this out.
- If Hide Unimportant is on, debuffs Blizzard flags as unimportant are hidden.
- Watch chat for `Bad anchor '...' for arena<N>.` which means a Custom Anchor frame
  name is wrong.

### "Icons show next to invisible/wrong frames"

- A Custom Anchor is set to a frame that exists but is not where you expect. Clear the
  Custom Anchor fields to go back to defaults.
- With sArena installed, icons always follow sArena frames, never the Blizzard ones.

### "A specific debuff is not showing / I want to show only certain debuffs"

- Use Options -> MiniArenaDebuffs -> Spell Filter. Add the spell by name (English
  clients) or by spell ID.
- When adding by name, all spell-ID variants of that name are added automatically,
  which is usually what you want.
- On non-English clients the name search finds nothing; enter the numeric spell ID
  instead.
- Filtering happens only when the list is non-empty; an empty "Only Listed Spells"
  list shows everything.

### "I changed a setting and nothing happened"

- Settings do not apply during combat ("Can't apply settings during combat."). Leave
  combat and change it again.
- Changes made while inside an arena/M+/raid encounter (even out of combat) can be
  deferred until the game lifts its aura-secrecy restriction; they apply automatically
  afterwards.

### "The Test button does nothing / test icons disappeared"

- Test mode automatically turns off when you enter combat. Pressing Test in combat
  queues it: "Can't test during combat, we'll test once combat drops."
- If real arena-style frames are visible, test icons attach to those instead of
  showing the fake arena1-3 boxes.

### "I don't have the Glow on Pandemic option"

- The glow and its color swatch only appear on clients that support engine-driven
  pandemic regions (per source comments, 12.1.5+). On earlier 12.1 builds the pair is
  hidden because the client cannot drive the reveal.

### "Masque skinned the icons but the skin looks the wrong size"

- Skins are fitted when a button is created. Reload the UI after changing skin, and
  after changing Icon Size while Glow on Pandemic is available, since the pandemic
  region makes the button's size unreadable and the art cannot be re-fitted in place.

### "Placeholder/fake debuff icons appear"

- In Blizzard Edit Mode the game injects fake auras into aura containers; the addon
  hides its displays while Edit Mode's preview is active (fixed in 3.0.1). If you see
  placeholder icons, make sure you are on 3.0.1 or later.

### "Icons eat my mouse clicks / no tooltips on icons"

- By design. The icons sit over arena frames and mouse interaction is disabled on
  them, so they can never intercept clicks. There are no tooltips on the debuff icons.

### "My settings are different on another character"

- They should not be: settings are account-wide (MiniArenaDebuffsDB). All characters
  share the same configuration.

### "Chat says: Bad anchor 'X' for arenaN"

- The Custom Anchor text for that arena slot names a frame that does not exist. Fix or
  clear the field in Options -> MiniArenaDebuffs -> Custom Anchors. The addon falls
  back to the default frame for that slot.

## Notes on limits and behavior

- The addon refreshes its displays on arena opponent updates and when entering the
  world; the aura contents themselves are updated by the game engine.
- Maximum of 10 icons per enemy (Max Icons slider cap).
- Custom anchor overrides exist for arena slots 1-3 only; default (sArena/Blizzard)
  anchoring follows however many enemy frames exist.
- The game engine computes the refresh (pandemic) window itself and the addon cannot
  read its bounds; all it says is whether the glow should be drawn there. Test mode has
  no real auras to ask about, so its preview treats the last 30% of each sample timer as
  the window.
- Sorting "INDEX" maps to sorting by aura instance ID, which approximates application
  order.
- Icons stop showing as soon as an arena opponent no longer exists, which is what clears
  them when a match ends.

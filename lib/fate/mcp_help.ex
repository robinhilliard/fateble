defmodule Fate.McpHelp do
  @moduledoc """
  Help content served as MCP resources.

  Each function returns a markdown string for a specific resource URI.
  Phase 1: concepts, ui, fate_rules.
  Phase 2 will add gm_workflows.
  """

  @concepts """
  # Fateble — Concepts

  Fateble is a virtual tabletop for the Fate RPG system. This resource defines the
  terminology used throughout the app and its MCP tools. For the full Fate RPG rules,
  see the `fate://rules/fate` resource.

  > The Fate RPG terminology below is based on Fate Core System and Fate Accelerated
  > Edition by Evil Hat Productions, licensed under CC-BY 3.0. See `fate://rules/fate`
  > for full attribution and links to the rulebooks.

  ---

  ## Part 1 — Fate RPG Terminology

  These terms match the Fate RPG rules and are used consistently across the app's UI
  and MCP tools.

  ### Entities

  An **entity** is anything on the table with a character sheet — not just people.
  Each entity has a **kind** that determines its role in the game:

  - **PC** (Player Character) — a protagonist controlled by a player
  - **NPC** (Non-Player Character) — a character controlled by the GM
  - **Mook Group** — a group of minor NPCs that share a single stress track and are
    eliminated individually (tracked by `mook_count`)
  - **Organization** — a faction, guild, or group treated as a single entity
  - **Vehicle** — a ship, car, mech, or other conveyance with its own sheet
  - **Item** — a significant object (weapon, artifact, tool) attached to a parent entity
    as a sub-entity
  - **Hazard** — an environmental threat (a fire, a trap, a magical ward) with aspects,
    skills, and stress of its own
  - **Custom** — anything else that needs a sheet

  Entities can be **hidden** by the GM (invisible to players until revealed) and can
  have a **controller** (the participant who operates them). Items and weapons are
  typically attached as **sub-entities** of a parent character.

  ### Aspects

  An **aspect** is a short phrase describing something important about a character,
  scene, or situation. Aspects are the core narrative currency in Fate — they can be
  **invoked** for a bonus or **compelled** for complications.

  Aspect **roles** in the app:

  - **High Concept** — the core identity of an entity ("Roguish Sky Pirate Captain")
  - **Trouble** — a recurring problem or vulnerability ("Wanted in Three Kingdoms")
  - **Additional** — any other permanent character aspect
  - **Situation** — a temporary aspect on a scene or zone ("Thick Smoke", "Slippery Floor")
  - **Boost** — a fragile, one-use advantage gained from succeeding with style; removed
    after one free invoke or at end of scene
  - **Consequence** — a lasting injury or setback taken to absorb stress (see Consequences)

  Aspects can have **free invokes** — uses that don't cost a fate point, typically
  granted when the aspect is first created or discovered.

  ### Skills

  **Skills** represent what an entity is good at. Each skill has a numeric **rating**
  on the Fate Ladder (see `fate://rules/ladder` or `fate://rules/fate`). The app
  supports two skill systems:

  - **Fate Core** — 18 skills (Athletics, Burglary, Contacts, Crafts, Deceive, Drive,
    Empathy, Fight, Investigate, Lore, Notice, Physique, Provoke, Rapport, Resources,
    Shoot, Stealth, Will)
  - **Fate Accelerated** — 6 approaches (Careful, Clever, Flashy, Forceful, Quick, Sneaky)
  - **Custom** — any user-defined skill list

  ### Stunts

  A **stunt** is a special ability that breaks the normal rules — granting a +2 bonus
  in narrow circumstances, letting you use one skill in place of another, or providing
  a unique narrative permission. Each stunt has a **name** and an **effect** description.

  ### Stress Tracks

  **Stress tracks** represent an entity's capacity to absorb harm in the short term.
  Each track has a **label** (typically "Physical" or "Mental") and a number of
  **boxes**. When hit, you check a box with a value equal to or greater than the shifts
  you need to absorb. Stress is cleared at the end of every scene.

  ### Consequences

  **Consequences** are lasting injuries or setbacks that absorb larger hits. Each has a
  **severity** that determines how many shifts it absorbs and how long it takes to recover:

  - **Mild** (2 shifts) — clears after one scene
  - **Moderate** (4 shifts) — clears after one session
  - **Severe** (6 shifts) — clears after one scenario
  - **Extreme** (8 shifts) — permanent; replaces one of your aspects

  A consequence is itself an aspect (e.g. "Broken Arm") that opponents can invoke.
  Recovery involves renaming the consequence to reflect healing, then clearing it after
  the appropriate time.

  ### Fate Points

  **Fate points** (FP) are the metagame currency. Each entity has a current FP count
  and a **refresh** value — the minimum they reset to at the start of a session.

  - **Spend** a fate point to **invoke** an aspect for +2 or a reroll
  - **Earn** a fate point when one of your aspects is **compelled** against you
  - **Refresh** resets FP to the refresh value (if current FP is lower)

  ### Scenes and Zones

  A **scene** is a discrete unit of play — a location, an encounter, a dramatic moment.
  Scenes have a **name**, **description**, **GM notes** (private), and can contain
  **zones** and **situation aspects**.

  A **zone** is a loosely defined area within a scene (e.g. "Rooftop", "Alley Below",
  "Bridge"). Entities can be placed in zones, and moving between zones may require an
  overcome action. Zones can be **hidden** from players until the GM reveals them.

  **Situation aspects** are aspects attached to a scene or zone that describe the
  environment ("Dim Lighting", "Crowd of Onlookers").

  ### Actions

  The four actions in Fate, all supported by the app:

  - **Overcome** — get past an obstacle (roll vs a fixed difficulty)
  - **Create Advantage** — create or discover an aspect, granting free invokes
  - **Attack** — try to harm another entity
  - **Defend** — oppose an attack or overcome attempt

  ### Shifts and Exchanges

  When an attack roll exceeds a defend roll, the difference is **shifts**. The defender
  must absorb those shifts using stress boxes and/or consequences, or be **taken out**.

  An **exchange** is a structured sequence of actions in a conflict — rolls, invokes,
  shift resolution, stress, consequences — built collaboratively and committed to the
  event log as a group.

  ---

  ## Part 2 — App Concepts

  ### The Event Chain

  Every game action — creating a character, rolling dice, taking stress, adding an
  aspect — is recorded as an **event** in a chain. Think of it like a giant undo/redo
  stack: the current game state is always derived by replaying the chain from the
  beginning.

  Nothing is stored separately. The event chain is the single source of truth.

  ### Editing Events

  Events after the last **bookmark boundary** can be carefully edited to correct the
  record — fix a typo in an aspect, adjust a skill rating, change a description.
  Events before a bookmark boundary are locked.

  **Editing must be done with care.** Later events depend on the effects of earlier ones.
  For example:

  - Deleting an entity creation event **permanently removes** that entity. Any subsequent
    events targeting it (adding aspects, rolling skills, taking stress) become **invalid**.
  - The app flags invalid events with a warning to help you spot problems.
  - Reordering events can also cause invalidation if dependencies are broken.

  ### Derived State

  The **derived state** is the current snapshot of the game: who has how many fate
  points, which stress boxes are checked, what the active scene looks like, which
  entities exist. It is computed fresh from the event chain every time — never stored
  independently.

  ### Bookmarks

  A **bookmark** is a save point in the event chain. Bookmarks enable:

  - **Save points** — mark milestones like "prep complete" or "before the big fight"
  - **What-if branching** — fork from any bookmark to explore alternate timelines without
    affecting the original
  - **Timeline switching** — switch between branches to compare outcomes or return to a
    previous state

  Events before a bookmark boundary are frozen. New events are appended after the
  bookmark's head event. Bookmarks can be **archived** when no longer needed.

  ### Participants and Roles

  A **participant** is a person at the table. On first visit, you choose a name, role,
  and color. Your identity is stored in the browser — no passwords, designed for a
  trusted LAN.

  - **GM** (Game Master) — full visibility: sees hidden entities, hidden zones, hidden
    aspects, GM notes, and the full event history. Can delete/undo/reorder events, manage
    bookmarks, and hide/reveal content. Multiple GMs are supported (e.g. a GM and an
    AI assistant).
  - **Player** — same gameplay actions as the GM (create entities, add aspects, roll dice,
    run conflicts). The differences are visibility (no hidden items or GM notes) and
    administration (no event deletion or bookmark management).
  - **Observer** — read-only view of the public game state. Can watch the table and browse
    the event log but cannot take any actions.
  """

  @ui """
  # Fateble — UI Guide

  This resource describes the user interface of Fateble. For terminology used here
  (aspects, skills, entities, stress, etc.) see `fate://help/concepts`.

  ---

  ## The Lobby

  On first visit, you are prompted to join the table:

  1. Enter your **name**
  2. Choose a **role**: GM, Player, or Observer
  3. Pick a **color** (free-form color picker, random default)
  4. Click **"Join Game"**

  If participants already exist, a **"Or rejoin as:"** section shows them with a
  **"Rejoin"** button. Returning users with a stored identity (in the browser's
  localStorage) are redirected straight to the table.

  When no game exists yet, the app creates a demo scenario ("The Iron Carnival")
  automatically on first join.

  ---

  ## The Table

  The table is a **full-screen canvas** with a felt-texture background. Everything
  floats in a spring-physics layout: entity cards, zones, scene aspects, and the
  GM notes card are all draggable elements that repel each other and settle into a
  readable arrangement.

  ### Entity Cards

  Each entity appears as a **color-coded card** on the table.

  **Collapsed view** (default, narrow):
  - Header: name, kind label, mook count (if applicable)
  - Aspects (with role indicators)
  - Consequences
  - Stress tracks (abbreviated: first letter of track label + numbered boxes)
  - Pending shifts banner (if any, shown as "N shifts!")
  - Fate point token (circular, with current FP count)

  **Expanded view** (wider, toggled by the chevron button):
  - Everything in the collapsed view, plus a right column showing:
  - Skills (sorted by rating, with a + button to add more)
  - Stunts (with a + button)
  - Refresh value

  Click a card to **select** it (highlighted with a yellow ring). Selections are
  per-user and filter the event log (see Selection and Filtering below).

  **Pinning**: double-click (or double-tap) a card to lock it in place. Pinned cards
  don't move when the spring layout shifts. Double-click/tap again to unpin. On touch
  devices, you can also **long-press** (500ms) to pin — the device will vibrate briefly
  to confirm.

  **Layout memory**: card positions are saved per-user in localStorage, keyed by
  bookmark and scene. Your arrangement persists across page reloads and is independent
  of other users' layouts.

  ### Ring Menus

  Hover over an entity's **fate point token** to reveal a **ring menu** — action
  buttons that fan out in a viewport-aware arc around the token. On touch devices,
  **tap** the token to toggle the ring open or closed; tapping anywhere else on the
  table closes it.

  **Entity ring menu actions** (varies by role and entity state):

  | Action | Who can use it | Notes |
  |--------|---------------|-------|
  | FP +1 | Everyone | Earn a fate point |
  | FP −1 | Everyone | Spend a fate point |
  | Concede | Everyone | Concede a conflict |
  | Taken Out | Everyone | Mark entity as taken out (requires confirmation) |
  | Clear Stress | Everyone | Clear all checked stress boxes (only if entity has stress tracks) |
  | Eliminate Mook | Everyone | Remove one mook from the group (only for mook groups) |
  | Add Aspect | Everyone | Add an aspect to this entity |
  | Add Note | Everyone | Add a freeform note attached to this entity |
  | Edit Entity | GM or controller | Edit name, kind, color, FP, refresh |
  | Hide / Reveal | GM only | Toggle entity visibility for players |
  | Remove | GM only | Remove entity from the game |

  ### GM Notes Card

  A special card on the table showing the current **scene name**, **description**, and
  **GM notes** (GM notes are only visible to GMs). Its ring menu provides scene
  management:

  | Action | When available |
  |--------|---------------|
  | New Scene | Always |
  | Switch Scene | When multiple scene templates exist and no scene is active |
  | Start Scene | When a scene template is selected but not active |
  | End Scene | When a scene is active (requires confirmation: clears stress, removes boosts) |
  | Add Zone | When a scene is active |
  | Add Aspect | When a scene is active (adds a situation aspect) |

  ### Zones

  Zones appear as **dashed-border regions** on the table. To move an entity into a
  zone, drag its fate point token into the zone area. Drag it out onto the open table
  to leave the zone.

  The GM can **hide** and **reveal** zones — hidden zones are invisible to players
  until the GM chooses to reveal them.

  ### Scene Aspects

  Scene-level situation aspects float as small cards near the scene title. They are
  styled by role: situation aspects in blue, boosts in yellow. The GM can hide/reveal
  individual aspects.

  ---

  ## The GM Panel

  URL: `/panel/gm/:bookmark_id`

  Docks on the **left side** of the table, or opens as a **standalone browser window**.
  Toggle docking via the dock/undock button.

  The GM Panel provides:

  - **Bookmark tree** — visualizes the bookmark hierarchy. Click any bookmark to navigate
    to its table view. The current bookmark is highlighted.
  - **Fork bookmark** — create a new branch from any bookmark for what-if exploration.
  - **Archive bookmark** — retire a bookmark (hides it from the active list).
  - **Search** — live search across entities and scenes. Results appear as you type.
    Recent searches are saved. Click a result to select it (filters the event log in the
    Player Panel). Multiple entities/scenes can be selected.
  - **Restore entity** — bring back a previously removed entity (re-creates it with
    its full sheet).

  ---

  ## The Player Panel

  URL: `/panel/player/:bookmark_id`

  Docks on the **right side** of the table, or opens as a **standalone browser window**.

  The Player Panel has three main sections:

  ### Event Log

  Displays the game's event history. Events are shown oldest-at-top, newest-at-bottom.

  - **GMs** see the full event chain (including events from parent bookmarks)
  - **Players** see only events from the current bookmark boundary onward

  Each event row shows the event type, description, and involved entities. Events
  flagged as **invalid** (e.g. targeting a deleted entity) show a warning icon with a
  tooltip explaining the problem.

  GMs can **edit**, **delete**, and **reorder** events directly from the log. Click the
  edit icon on any event row to open a modal pre-filled with that event's current data.

  ### Action Palette

  Two **create buttons** sit at the top of the palette:

  - **Create Entity** — add a new entity to the game (name, kind, color, FP, refresh)
  - **Create Aspect** — add an aspect to any entity, scene, or zone

  These are the actions that don't have a faster path elsewhere. Most other actions are
  accessible directly from the table: FP +/− and entity editing via **ring menus** on
  entity tokens, scene management via the **GM notes ring**, skill/stunt editing via
  **+** buttons on expanded entity cards, compels via buttons on aspect rows, and notes
  via the activity bar.

  Below the create buttons are the **Start Exchange** buttons (see below).

  ---

  ## The Exchange Builder

  The exchange builder handles multi-step conflicts. It is part of the Player Panel
  and is synchronized in real time across all connected participants.

  ### Starting an Exchange

  Choose one of four exchange types:

  - **Attack** — "Roll, defend, invoke, resolve, absorb"
  - **Overcome** — "Roll vs fixed difficulty"
  - **Create Advantage** — "Roll to create or discover an aspect"
  - **Defend** — "Oppose an attack or overcome"

  ### Available Steps by Exchange Type

  | Step | Attack | Overcome | Create Advantage | Defend |
  |------|:------:|:--------:|:----------------:|:------:|
  | Roll Attack | x | | | |
  | Roll Defend | x | | | x |
  | Roll Overcome | | x | | |
  | Roll Create Advantage | | | x | |
  | Invoke Aspect | x | x | x | x |
  | Shifts Resolved | x | x | x | |
  | Apply Stress | x | | | |
  | Take Consequence | x | | | |
  | Redirect Hit | x | | | |
  | Concede | x | | | |
  | Taken Out | x | | | |
  | Create Aspect | | | x | |

  ### Building an Exchange

  1. Click a step type button in the **"Add Step"** palette to add it to the
     **build lane**
  2. Fill in step fields: select actor, target, skill; set dice (click individual dice
     faces to cycle +/0/− or use the auto-roll button for random Fudge dice)
  3. Drag steps to **reorder** them, or click ✕ to remove
  4. When ready, click **"Commit N steps to log"** to append all steps as events

  The exchange is shared — all connected participants see the same build lane in real
  time and can contribute steps collaboratively.

  ---

  ## Docking and Undocking

  Both panels (GM and Player) can operate in two modes:

  - **Docked** — embedded as a sidebar within the table view (GM on left, Player on right)
  - **Undocked** — opened as a separate browser window at its standalone URL

  Toggle between modes using the dock/undock button on each panel. When undocked, the
  panel maintains real-time sync with the table via PubSub. This is useful for
  multi-monitor setups: keep the table on one screen and panels on another.

  ---

  ## Selection and Filtering

  Click to select entities on the table or in the GM panel search results. Your
  selection is **per-user** — it is not shared with other participants.

  Selecting entities **filters the event log** in the Player Panel to show only events
  involving those entities. This is a powerful alternative path for editing entity
  details: select a character, then scroll their filtered history to find and edit
  specific events (skill changes, aspect additions, consequence recoveries) rather than
  hunting through the full chronological log.

  Multiple entities and scenes can be selected simultaneously. Click **"Clear
  selection"** in the event log header to remove all filters.

  ---

  ## Touch and Mobile

  The app is fully usable on tablets and touch devices with these differences from
  desktop:

  **Interaction changes:**
  - **Ring menus** open on **tap** (not hover) and close when you tap elsewhere
  - **Pinning** works via **long-press** (500ms, with haptic vibration) in addition to
    double-tap
  - **Dragging** cards, tokens, and steps requires an 8px movement threshold to
    distinguish drags from taps
  - **Event reordering** and **exchange step reordering** use touch drag with the same
    threshold

  **Visibility:**
  - Action buttons on entity cards (aspect invoke/compel, skill +/−, stunt remove,
    expand toggle) that are hidden-until-hover on desktop are shown at **reduced opacity**
    on touch devices, so they remain discoverable without hover
  - The activity bar icons are shown at full brightness on touch (on desktop they dim
    and brighten on hover)

  **Viewport:**
  - The table locks the viewport and disables overscroll to prevent accidental
    pull-to-refresh or browser navigation gestures
  - Double-tap zoom is suppressed so double-tap can be used for pinning

  ---

  ## Bookmark Browser

  URL: `/branches`

  A standalone page listing all active bookmarks with links to navigate directly to
  any bookmark's table view. Useful for quickly switching between timelines without
  opening the GM panel.
  """

  @fate_rules """
  # Fate RPG Quick Reference

  ## Attribution

  This work is based on Fate Core System and Fate Accelerated Edition
  (found at https://fate-srd.com/), products of Evil Hat Productions, LLC,
  developed, authored, and edited by Leonard Balsera, Brian Engard, Jeremy Keller,
  Ryan Macklin, Mike Olson, Clark Valentine, Amanda Valentine, Fred Hicks, and
  Rob Donoghue, and licensed for our use under the Creative Commons Attribution 3.0
  Unported license (http://creativecommons.org/licenses/by/3.0/).

  ## Obtaining the Rulebooks

  ### English Editions

  - **Fate Core System** — Evil Hat Productions, 2013. 308 pages.
    ISBN 978-1-61317-029-8.
    Purchase: https://evilhat.com/product/fate-core-system/
    Pay-what-you-want PDF: https://evilhat.itch.io/fate-core

  - **Fate Accelerated Edition (FAE)** — Evil Hat Productions, 2013. 48 pages.
    ISBN 978-1-61317-047-2.
    Purchase: https://evilhat.com/product/fate-accelerated-edition/

  - **Fate Condensed** — Evil Hat Productions, 2020. 68 pages. The most recent
    streamlined edition, 100% compatible with Fate Core.
    Pay-what-you-want: https://evilhat.itch.io/fate-condensed

  - **Fate SRD** — free online reference covering the full rules:
    https://fate-srd.com/

  ### Published Translations

  Note: published translations have their own copyright held by their respective
  publishers. They are not covered by the CC-BY 3.0 license on the English SRD.

  - **German** — *Fate Core: Deutsche Ausgabe*, Uhrwerk Verlag, 2015.
    ISBN 978-3-95867-005-1. https://shop.uhrwerk-verlag.de/
  - **Spanish** — *Fate Básico* and *Fate Acelerado*, Nosolorol.
    https://www.nosolorol.com/
  - **Polish** — *Fate Core: Edycja Polska*, Hengal.
  - **Italian** — Italian edition, crowdfunded via Ulule.
  - **Brazilian Portuguese** — community SRD translation:
    https://fatesrdbrasil.github.io/

  ## Agent Guidance

  This resource covers only the Fate rules that Fateble implements. When a user asks
  about Fate rules or concepts not covered here (extras, setting creation, character
  advancement, magic systems, etc.), **recommend the rulebooks and SRD first** — with
  titles, ISBNs, and URLs from the section above — before falling back to web searches.
  The books are the authoritative source and the user deserves to know they exist.

  ---

  ## The Fate Ladder

  Skill ratings in Fate map to descriptive names:

  | Rating | Name |
  |-------:|------|
  | +8 | Legendary |
  | +7 | Epic |
  | +6 | Fantastic |
  | +5 | Superb |
  | +4 | Great |
  | +3 | Good |
  | +2 | Fair |
  | +1 | Average |
  | +0 | Mediocre |
  | −1 | Poor |
  | −2 | Terrible |

  Most starting PCs have a pointed cap at Great (+4). NPCs and hazards can go higher.

  ## Aspects

  An **aspect** is a short phrase that describes something important. Anything can
  have aspects: characters, scenes, zones, the campaign itself.

  ### Types of Aspects

  - **High concept** — the core identity ("Cyberpunk Street Samurai")
  - **Trouble** — a recurring source of complications ("Owes a Favor to the Yakuza")
  - **Situation** — temporary environmental aspects on scenes or zones ("On Fire",
    "Pitch Dark")
  - **Boost** — a fragile, one-use advantage from succeeding with style; disappears
    after one free invoke or at end of scene
  - **Consequence** — a lasting aspect representing injury or setback (see Consequences)
  - **Additional** — any other character aspect

  ### Invoking Aspects

  Spend a **fate point** (or use a **free invoke**) to invoke a relevant aspect for:
  - **+2** to your roll, or
  - a **reroll** of all four dice

  The aspect must be narratively relevant to the action.

  ### Compelling Aspects

  When an aspect would make a character's life more complicated, the GM (or another
  player) can offer a **compel**. If the target accepts, they earn a **fate point** and
  suffer the complication. If they refuse, they pay a fate point.

  ### Free Invokes

  When you create or discover an aspect (via Create Advantage), you get one or more
  **free invokes** — uses that don't cost a fate point. Free invokes can be stacked
  with paid invokes.

  ## Skills

  Skills represent competence. Each has a numeric rating on the ladder.

  ### Fate Core Default Skills (18)

  Athletics, Burglary, Contacts, Crafts, Deceive, Drive, Empathy, Fight, Investigate,
  Lore, Notice, Physique, Provoke, Rapport, Resources, Shoot, Stealth, Will

  ### Fate Accelerated Approaches (6)

  Careful, Clever, Flashy, Forceful, Quick, Sneaky

  ### The Skill Pyramid

  In Fate Core, starting characters arrange skills in a pyramid: one Great (+4), two
  Good (+3), three Fair (+2), four Average (+1). Remaining skills default to Mediocre
  (+0). In Accelerated, approaches start at different ratings without the pyramid
  constraint.

  ## Stunts

  A **stunt** grants a special ability. Common patterns:

  - **+2 bonus** in narrow circumstances ("Because I am a [descriptor], I get +2 when
    I use [skill] to [action] when [circumstance]")
  - **Skill substitution** — use one skill in place of another in specific situations
  - **Rule exception** — a unique narrative permission ("Once per session, I can...")

  Starting characters typically get three free stunts. Additional stunts reduce refresh.

  ## Stress and Consequences

  ### Stress

  Stress tracks represent short-term resilience. Default tracks in Fate Core:
  - **Physical** (2 boxes, extended by Physique)
  - **Mental** (2 boxes, extended by Will)

  When hit, check a stress box with a value >= the shifts you need to absorb.
  Each box can only be checked once. **Stress clears at the end of every scene.**

  ### Consequences

  Consequences absorb larger hits but last longer:

  | Severity | Shifts Absorbed | Recovery |
  |----------|:-:|---|
  | Mild | 2 | Clears after one scene with justification |
  | Moderate | 4 | Clears after one session with justification |
  | Severe | 6 | Clears after one scenario with justification |
  | Extreme | 8 | Permanent — replaces one of your aspects |

  A consequence is an aspect. Opponents can invoke it against you. Recovery involves
  renaming the consequence to reflect healing ("Broken Arm" becomes "Arm in a Sling"),
  then clearing it after the appropriate time.

  ### Absorbing Hits

  When you're hit for shifts, you must absorb them using some combination of:
  - **Stress boxes** (each absorbs its box value in shifts)
  - **Consequences** (each absorbs its severity value in shifts)

  If you can't absorb all the shifts, you are **taken out** — the attacker decides
  your fate.

  ## Fate Points

  ### Earning Fate Points
  - Accepting a **compel** on one of your aspects
  - **Conceding** a conflict before being taken out
  - At the start of a session, refresh to your **refresh** value (if current FP is lower)

  ### Spending Fate Points
  - **Invoke** an aspect for +2 or a reroll
  - Power certain stunts
  - Make a **declaration** (establish a narrative detail)

  ### Refresh
  Each entity has a **refresh** value (typically 3 for starting PCs). At the start of
  each session (or when the refresh action is used), fate points reset to the refresh
  value if current FP is lower. If current FP is higher (from earning through compels),
  it stays.

  ## The Four Actions

  Every skill roll uses one of four actions:

  ### Overcome
  Roll against a **fixed difficulty** set by the GM to get past an obstacle.
  - **Fail**: you don't achieve your goal, or you achieve it at a serious cost
  - **Tie**: you achieve your goal at a minor cost, or get a lesser version
  - **Succeed**: you achieve your goal cleanly
  - **Succeed with Style** (3+ shifts): you achieve your goal and get a boost

  ### Create Advantage
  Roll to create a new **situation aspect** or discover an existing hidden one.
  - **Fail**: you don't create the aspect, or you do but the opposition gets a free invoke
  - **Tie**: you get a boost instead of a full aspect
  - **Succeed**: you create the aspect with one free invoke
  - **Succeed with Style**: you create the aspect with two free invokes

  ### Attack
  Roll to harm another entity. The target **defends** against your roll.
  - **Fail**: you don't hit
  - **Tie**: you don't hit but get a boost
  - **Succeed**: you hit for shifts equal to the difference between your roll and the
    defense
  - **Succeed with Style**: as succeed, but you can reduce shifts by 1 to also gain
    a boost

  ### Defend
  Roll to oppose an attack or an overcome attempt against you.

  ## The Four Outcomes

  Every roll produces one of four outcomes based on shifts (your total minus the
  opposition or difficulty):

  | Shifts | Outcome |
  |--------|---------|
  | < 0 | **Fail** |
  | 0 | **Tie** |
  | 1–2 | **Succeed** |
  | 3+ | **Succeed with Style** |

  ## Conflicts

  A **conflict** is a structured scene where entities are trying to harm each other.

  ### Exchanges
  Conflicts are organized into **exchanges** (rounds). In each exchange, every
  participant gets to take an action. The app's exchange builder lets you assemble a
  sequence of rolls, invokes, shift resolutions, stress applications, and consequences
  collaboratively, then commit them all to the event log at once.

  ### Turn Order
  Fate uses a flexible approach to turn order based on the narrative and skills, rather
  than a fixed initiative roll. The GM typically calls on characters in an order that
  makes narrative sense.

  ### Conceding
  Before being taken out, a character can **concede** the conflict. They lose, but on
  their own terms — they get to negotiate the outcome with the GM. They also earn a
  fate point for conceding, plus one for each consequence taken during the conflict.

  ### Being Taken Out
  If you can't absorb all the shifts from an attack (no available stress boxes or
  consequence slots), you are **taken out**. The attacker decides what happens to you.

  ## Contests and Challenges

  **Contests** are opposed sequences where two sides race to achieve a goal (e.g. a
  chase). Each exchange, both sides roll and accumulate victories; first to three wins.

  **Challenges** are complex tasks broken into a series of overcome actions, each
  tackling a different facet of the problem.

  These are less structured than conflicts and are typically handled through a series
  of individual rolls rather than the exchange builder.
  """

  def concepts, do: @concepts
  def ui, do: @ui
  def fate_rules, do: @fate_rules
end

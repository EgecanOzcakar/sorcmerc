## Creator readability — skills as rows, no stray warnings, a feat's picks under the feat (2026-09-25)

Three reports against the character creator (#188, #189, #190), all about
the page reading the wrong way rather than about the rules underneath it.

**#188 — skills as a list.** The live sheet (the side panel on every step,
and the whole of the Review page) printed the build's skills as one
comma-run paragraph: "Athletics +5, Insight +3, Intimidation +2, Perception
+3, Survival +3", wrapped wherever the panel's edge fell, so a bonus was as
likely to open the next line as close its own, and expertise was a bare "E".
`_sheet_bbcode` now lays out whatever is a list as one. Skills are a table of
name and bonus (`skill_rows`, then `_pair_table`): two pairs a row in the
side panel, three on the Review page's wider column, alphabetical, read left
to right. Expertise is a gilt ◆ after the name, the mark the profile's sheet
already uses, with a one-line key under the table when a build has any. On
the Review page the spells are a table of names (cantrips and spells apart)
instead of another comma run; the kit is called by its names ("Chain Mail",
not `chain-mail`); and the proficiencies the sheet never showed at all —
armor, weapons, tools, languages — get a caption and a row each. The side
panel is a line or two taller for a five-skill build than the paragraph was;
that is the price of a bonus that stays beside its skill.

**#189 — the warning on the Review page.** Every barbarian, fighter and
rogue reached the Review page wearing a gilt "warnings:" block — four lines
of `bundle-choice "bundle-choice:class:fighter:0" cannot resolve —
starting-equipment bundles are not exported (SCHEMA gap #2)` for a fighter.
The export has no starting-equipment bundles (`data/SCHEMA.md` gap #2), and
`core/rules/pass_gear.gd` reported every `bundle-choice` grant as a warning;
the creator reads `sheet.warnings` out to the player. But nothing about such
a build is wrong: the kit is picked on the creator's own Equipment step, the
game's answer to the gap rather than a hole in it, and the tests already
treated the line as the one warning a finished build was allowed
(`tests/test_class_abilities.gd`, `tests/test_rules.gd`). So it is no longer
a warning at all, and those two tests now allow none — which also stops a
real warning (a catalog miss, a `BUG:` line) hiding in a list everyone had
learned to skip. The Review page's warnings block still prints what is left;
on every build of every class it is now empty (a sweep of all species ×
classes × backgrounds at levels 1 and 4 found no other warning).

**#190 — a feat's follow-up under the feat.** Choose a human's origin feat
and whatever it asks for next — Magic Initiate's spell list and then its
spells, Skilled's three skills — appeared *above* the feat. The resolver
lists choice points by kind (`pass_pending.gd` walks ability picks, skills,
fighting styles, feature picks, then feats, then spells), and nearly every
kind a feat hands out comes before feats. `Creator.page_order` now moves
every point a chosen feat brought to just after the feat-choice that chose
it, in the resolver's order among themselves, and leaves everything else
where it stood, so a pick still never shuffles the rest of the page. #191's
list-merging respects the same boundary (`choice_groups` takes the build's
choices): Skilled's any-three-skills was the human's any-skill list over
again and would have been folded back up into it. The level-up page lists
this level's picks in the same order, for a feat taken at 4.

Screenshots: `docs/shots/issue-188-creator-skills-before.png` /
`issue-188-creator-skills.png` (the Review page, and the side panel beside
it), `issue-188-creator-expertise.png` (a rogue's ◆ rows),
`issue-189-creator-warnings-before.png` / `issue-189-creator-warnings.png`,
`issue-190-feat-order-before.png` / `issue-190-feat-order.png`. Tests:
`tests/test_creator.gd` (`feat_follow_ups_come_after_the_feat`,
`kit_classes_carry_no_warnings`, `skills_are_rows`).

### Still open

- The side panel is not in a scroll container. A build with a long pending
  list (a level-8 recruit with every level's picks open) can still run it
  past the bottom of the window, and the skill rows cost a line or two
  more than the paragraph did. Worth a scroll the first time a report
  shows it.
- `page_order` anchors only what a feat-choice *on the page* chose. A
  background's fixed origin feat (Magic Initiate for the Acolyte) has no
  feat row to sit under, so its picks keep the resolver's place; if one of
  those ever reads out of order, anchor them under the background's heading.
- The Review page's warnings block is still raw resolver text. It is empty
  on every shipped build now; a content pack that trips one will show the
  modder's diagnostic to the player, which is arguably right for a pack but
  not worded for a player.

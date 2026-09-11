# Third-party art licenses

The game's code and everything non-LPC is proprietary. The character and
creature pixel art in `assets/lpc/` (and the sheets composited from it into
`assets/generated/`) is **not**: it comes from the Liberated Pixel Cup
ecosystem and carries real obligations.

* `CC-BY-SA-3.0.txt` — Creative Commons Attribution-ShareAlike 3.0 Unported.
  Share-alike: modified/recolored LPC parts must be published under the same
  license. Keep any such edits in `assets/lpc/`, which is the publishable
  folder.
* `GPL-3.0.txt` — GNU GPL v3, the alternative license most LPC art is dual
  (or triple) licensed under.
* OGA-BY 3.0 covers some parts (the whole bat sprite, among others). It is the
  OpenGameArt attribution-only variant of CC-BY:
  <https://opengameart.org/content/oga-by-30-faq>. Attribution only, no
  share-alike, so nothing extra is required beyond the credits list.

Who made what: `assets/lpc/CREDITS.csv` (rows copied from the upstream
generator for exactly the parts vendored here) is the source of truth.
`assets/generated/credits.txt` is generated from it by `tools/lpc_compose.py`
and is what the in-game credits screen (Settings → Art credits) displays.

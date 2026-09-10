# Tiny Swords Free Pack — local runtime assets

Author: Pixel Frog. [Publisher and current license terms](https://pixelfrog-assets.itch.io/tiny-swords). Verified 2026-09-10.

The current Free Pack allows use in personal and commercial games and permits editing. Credit is optional. Redistribution, resale, or repackaging of the assets is restricted, including edited versions. This is the current Free Pack, not the separately offered older CC0 pack.

No license file was included in the supplied extracted folder. The publisher page is the license reference. Do not label these files CC0.

PNG copies stay local and are ignored by Git. The source filenames, dimensions and SHA-256 hashes are recorded in `manifest.json`; source PNG bytes are preserved. These copies came from the user's local `Tiny Swords (Free Pack)/Tiny Swords (Free Pack)` directory, not a new download. The exact upstream release identifier was not supplied.

Install after a fresh checkout:

```sh
make import_tiny_swords
# Or use an alternate copy of the same pack:
make import_tiny_swords ASSET_SOURCE="/path/to/Tiny Swords (Free Pack)"
```

`make check_tiny_swords_assets` checks installed bytes against the manifest. Tile coordinates use the publisher's 64×64 grid, rendered as 32-world-unit cells. [Tilemap guide](https://pixelfrog-assets.itch.io/tiny-swords/devlog/1138989/tilemap-guide).

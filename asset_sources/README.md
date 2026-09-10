# Original character inputs

The reference16 and reference32 PNGs are repository-authored synthetic test fixtures, generated from the original 4A reference artwork on 2026-09-10. They contain no third-party artwork.

Treat these files as original inputs. The processing pipeline reads and snapshots them; it writes derived frames only under build/. Each module owns a source_manifest.json recording the original SHA-256 and its custom importer owns the sheet layout.

The user-provided Archer, Orc, Warrior, Lancer and Monk sources remain under client/assets/Characters/. Their migration is a later checkpoint.

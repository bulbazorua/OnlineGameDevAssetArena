#!/usr/bin/env python3
"""Author the four 60x28 land arenas. Run explicitly, never on game startup."""
import json
from pathlib import Path

WIDTH, HEIGHT = 60, 28  # 1,680 cells: six times the original 20x14 maps.
DATA = Path(__file__).resolve().parents[1] / "client/content/data"


class Arena:
    def __init__(self, identity, key, title):
        self.identity, self.key, self.title = identity, key, title
        self.cells = [["." for _ in range(WIDTH)] for _ in range(HEIGHT)]
        self.heights = [[0 for _ in range(WIDTH)] for _ in range(HEIGHT)]
        self.rect(0, 0, WIDTH - 1, 1, "t")
        self.rect(0, HEIGHT - 2, WIDTH - 1, HEIGHT - 1, "t")
        self.rect(0, 0, 1, HEIGHT - 1, "t")
        self.rect(WIDTH - 2, 0, WIDTH - 1, HEIGHT - 1, "t")

    def rect(self, left, top, right, bottom, terrain):
        for y in range(top, bottom + 1):
            for x in range(left, right + 1):
                self.cells[y][x] = terrain

    def lake(self, cx, cy, rx, ry):
        for y in range(max(2, cy - ry - 1), min(HEIGHT - 2, cy + ry + 2)):
            for x in range(max(2, cx - rx - 1), min(WIDTH - 2, cx + rx + 2)):
                distance = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if distance <= 1.5:
                    self.cells[y][x] = "w" if distance < 0.75 else "s"

    def terrace(self, left, top, right, bottom, stair_x, entrance="south"):
        for y in range(top, bottom + 1):
            for x in range(left, right + 1):
                self.heights[y][x] = 1
                self.cells[y][x] = "c" if x in (left, right) or y in (top, bottom - 1, bottom) else "."
        if entrance == "south":
            self.rect(stair_x, bottom - 1, stair_x + 1, bottom, "=")
            self.rect(stair_x, bottom - 3, stair_x + 1, bottom - 2, "g")
        else:
            self.rect(stair_x, top, stair_x + 1, top, "=")
            self.rect(stair_x, top + 1, stair_x + 1, top + 2, "g")

    def details(self):
        # Small clearings, tall-grass patches and flower/rock landmarks. No RNG.
        for x, y in [(25, 5), (33, 22), (5, 18), (54, 9)]:
            for dy in range(2):
                for dx in range(3):
                    if self.cells[y + dy][x + dx] == ".":
                        self.cells[y + dy][x + dx] = '"'
        for x, y in [(4, 4), (54, 22), (26, 22), (35, 5)]:
            if self.cells[y][x] == ".":
                self.cells[y][x] = "#"
        # Wide central route and spawn clearings remain open in every arena.
        self.rect(2, 13, 57, 15, "g")
        for x in (12, 47):
            self.rect(x - 1, 13, x + 1, 16, "g")

    def export(self):
        self.details()
        return {"id": self.identity, "key": self.key, "display_name": self.title,
                "width": WIDTH, "height": HEIGHT, "tile_size": 32,
                "rows": ["".join(row) for row in self.cells],
                "elevation_rows": ["".join(map(str, row)) for row in self.heights],
                "spawns": [[12, 14], [47, 14]]}


def build():
    meadow = Arena(1, "meadow_crossing", "Meadow Crossing")
    meadow.terrace(7, 3, 22, 10, 14)
    meadow.terrace(38, 18, 53, 24, 45, "north")
    meadow.lake(47, 6, 5, 2)
    meadow.lake(14, 21, 5, 3)
    meadow.rect(28, 2, 30, 25, "g")
    meadow.rect(14, 11, 15, 12, "g")
    meadow.rect(45, 16, 46, 17, "g")

    sandbar = Arena(2, "sandbar", "Sandbar")
    sandbar.terrace(20, 3, 39, 9, 29)
    sandbar.terrace(6, 19, 20, 24, 12, "north")
    sandbar.lake(8, 6, 4, 3)
    sandbar.lake(41, 23, 10, 2)
    sandbar.rect(29, 10, 30, 20, "g")
    sandbar.rect(12, 16, 13, 18, "g")
    sandbar.rect(49, 4, 50, 20, "g")
    sandbar.rect(31, 19, 48, 20, "g")

    garden = Arena(3, "stone_garden", "Stone Garden")
    garden.terrace(5, 3, 20, 10, 12)
    garden.terrace(39, 3, 54, 10, 47)
    garden.terrace(24, 19, 35, 24, 29, "north")
    garden.lake(9, 21, 4, 2)
    garden.lake(50, 21, 4, 2)
    garden.rect(12, 11, 13, 12, "g")
    garden.rect(47, 11, 48, 12, "g")
    garden.rect(29, 5, 30, 18, "g")
    for x, y in [(25, 7), (34, 7), (21, 17), (38, 17)]:
        garden.rect(x, y, x + 1, y + 1, "#")
    village = Arena(4, "tiny_swords_village", "Tiny Swords Village")
    village.terrace(24, 3, 35, 10, 29)
    village.lake(16, 22, 4, 2)
    village.lake(42, 22, 3, 2)
    village.rect(29, 11, 30, 25, "g")
    for x in (8, 19, 40, 51):
        village.rect(x, 10, x + 1, 12, "g")
    village.rect(3, 19, 56, 20, "g")
    village.rect(6, 16, 7, 24, "g")
    village.rect(51, 16, 52, 24, "g")
    record = village.export()
    # One authored footprint source: bake it into authoritative terrain cells.
    presentation = json.loads((DATA.parent / "presentation/arenas/tiny_swords_village.json").read_text())
    rows = [list(row) for row in record["rows"]]
    for prop in presentation["props"]:
        left, top, width, height = prop["footprint_cells"]
        for y in range(top, top + height):
            for x in range(left, left + width):
                if rows[y][x] not in (".", "g", '\"'):
                    raise ValueError(f"Building {prop['key']} overlaps blocked terrain")
                rows[y][x] = "b"
    record["rows"] = ["".join(row) for row in rows]
    return {"schema_version": 2, "arenas": [arena.export() for arena in (meadow, sandbar, garden)] + [record]}


if __name__ == "__main__":
    (DATA / "arenas.json").write_text(json.dumps(build(), indent=2) + "\n")

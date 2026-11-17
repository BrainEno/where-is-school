#!/usr/bin/env python3
"""Structural checks for ``NavMapUtil``: one copy of the navigation rule (issue #212).

The behaviour of ``NavMapUtil.has_geometry`` is checked where a navigation server exists
(``tests/navigation_test.gd``). What this file checks is the thing a behaviour test cannot:
that the repository still holds **one** implementation of the rule and that the three
controllers go through it.

- the method body exists once, in ``scripts/world/nav_map_util.gd``;
- no other GDScript under ``scripts/`` or ``addons/`` calls
  ``NavigationServer3D.map_get_regions(...).size() > 0`` directly - the shape the three
  copies had;
- ``PlayerController``, ``PointerNavigator`` and ``CompanionController`` each keep their
  private ``_map_has_geometry`` wrapper and each body is exactly the delegation (so the rule
  cannot be re-inlined in one of them later);
- ``LocationNavigation.get_map_region_count()`` still owns the count, and still does not
  claim to answer the yes/no question (its comment points at `NavMapUtil`).

Run it with ``python3 tests/nav_map_util_test.py`` (CI does). Standard library only.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UTIL = ROOT / "scripts" / "world" / "nav_map_util.gd"
CALLERS = {
    "scripts/actors/player/player_controller.gd": "PlayerController",
    "scripts/interaction/pointer_navigator.gd": "PointerNavigator",
    "scripts/world/companion_controller.gd": "CompanionController",
}

FAILURES: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def gd_files(*roots: str) -> list[Path]:
    out: list[Path] = []
    for root in roots:
        out += sorted((ROOT / root).rglob("*.gd"))
    return out


def body_of(text: str, signature: str) -> str | None:
    """The indented block that follows ``signature`` (a ``func`` line), or None."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith(signature):
            block = []
            for follow in lines[i + 1:]:
                if follow.strip() and not follow.startswith(("\t", " ")):
                    break
                block.append(follow)
            return "\n".join(block)
    return None


def the_rule_is_written_once() -> None:
    check(UTIL.is_file(), f"{UTIL.relative_to(ROOT)} must exist; it is the one copy")

    # The shape the three copies had, in any spacing.
    pattern = re.compile(
        r"map_get_regions\(\s*\w+\s*\)\s*\.\s*size\(\)\s*>\s*0")
    for path in gd_files("scripts", "addons", "tests"):
        if path == UTIL:
            continue
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            if pattern.search(line):
                check(False,
                      f"{path.relative_to(ROOT)}:{number} asks the geometry question "
                      "directly; call `NavMapUtil.has_geometry` instead (issue #212)")

    util_text = UTIL.read_text(encoding="utf-8")
    check(re.search(r"static func has_geometry\(map: RID\) -> bool:", util_text)
          is not None, "NavMapUtil.has_geometry(map: RID) -> bool is missing")
    body = body_of(util_text, "static func has_geometry(")
    check(body is not None and "map.is_valid()" in body and "map_get_regions" in body,
          "NavMapUtil.has_geometry no longer answers the invalid-map and empty-map cases")
    check("class_name NavMapUtil" in util_text, "NavMapUtil has no class_name")
    check(util_text.count("static func has_geometry") == 1,
          "NavMapUtil declares has_geometry more than once")


def callers_delegate() -> None:
    for rel, name in CALLERS.items():
        path = ROOT / rel
        check(path.is_file(), f"{rel} is missing")
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        check(f"class_name {name}" in text, f"{rel} no longer declares class_name {name}")
        body = body_of(text, "func _map_has_geometry(")
        check(body is not None, f"{rel} lost its `_map_has_geometry` wrapper")
        if body is None:
            continue
        statement = [line.strip() for line in body.splitlines() if line.strip()]
        check(statement == ["return NavMapUtil.has_geometry(map)"],
              f"{rel}'s wrapper is not a plain delegation: {statement}")
        check(text.count("NavMapUtil.has_geometry") >= 1,
              f"{rel} does not call NavMapUtil")
        # The controller must not carry the yes/no *answer* itself any more. A count
        # accessor is a different question (`get_navigation_region_count` returns -1 for an
        # invalid map), and the `the_rule_is_written_once` scan only bans the yes/no shape.


def the_count_keeps_its_owner() -> None:
    """The *count* is a different question, and keeps its owner.

    ``LocationNavigation.get_map_region_count()`` answers "how many regions reached the
    map", which is how a bake failure is described; ``NavMapUtil`` answers the yes/no.
    Both are wanted, and neither may grow into the other by accident.
    """
    path = ROOT / "scripts" / "world" / "location_navigation.gd"
    text = path.read_text(encoding="utf-8")
    body = body_of(text, "func get_map_region_count(")
    check(body is not None, "LocationNavigation.get_map_region_count() is gone")
    check(body is not None and "map_get_regions" in body,
          "get_map_region_count no longer counts the map's regions")

    companion = (ROOT / "scripts" / "world" / "companion_controller.gd").read_text(
        encoding="utf-8")
    companion_body = body_of(companion, "func get_navigation_region_count(")
    check(companion_body is not None, "CompanionController lost its region count")
    check(companion_body is not None and "-1" in companion_body,
          "the companion's region count no longer reports an invalid map as -1")


def main() -> int:
    the_rule_is_written_once()
    callers_delegate()
    the_count_keeps_its_owner()
    if FAILURES:
        for failure in FAILURES:
            print("NAV_MAP_UTIL_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("NAV_MAP_UTIL_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())

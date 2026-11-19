#!/usr/bin/env python3
"""Guards the layer that makes the protagonist's memory a mechanic rather than a mood.

The game separates four kinds of knowledge and shows a badge for each: what the player saw,
what someone said, what the protagonist remembers, and what they only imagine. Three of those
four are well covered: 23 inspections write a ``record`` entry, 17 conversations carry an
``imagined`` line, and every inner-voice line is tagged with its source.

The fourth was almost empty. Of 40 inspectable objects, **2** had a ``recall`` line. That is
the layer the premise rests on - an adult who remembers the place and may be remembering it
wrong - and it was the one nobody was checking, which is exactly why it stayed empty while
the rest of the content grew.

This test holds three things that are cheap to lose and expensive to notice:

1. **A recollection exists, and is paired across languages.** ``recall`` carries an
   ``entry_id`` that must match in both languages, and one language having a memory where the
   other has none is a bug the runtime cannot report, because each language loads alone.
2. **A recollection is not a second description.** A memory that repeats the observation
   teaches the player nothing about the difference between seeing and remembering. Every
   ``recall`` must share almost no wording with the ``text`` it follows.
3. **An inner voice is not an oracle.** The narrative rules say a voice may be wrong. A voice
   that only ever states facts is a hint system with a personality. Each voice's lines must
   carry at least one admission of doubt somewhere in its repertoire.

Run with ``python3 tests/memory_layer_test.py``. No network, no Godot.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSPECTIONS = ROOT / "data" / "inspections"
DIALOGUE = ROOT / "data" / "dialogue"
ABILITIES = ROOT / "data" / "abilities"

LOCALES = ("zh-CN", "en")
CHAPTERS = ("classroom", "corridor", "street", "residential", "alley", "playground", "laboratory")

## The share of a recollection's characters that may also appear in the observation it
## follows. A memory is allowed to name the same object; it is not allowed to be the same
## sentence again. 0.75 leaves room for a shared noun and catches a copy.
MAX_OVERLAP = 0.75
## Below this many inspectables with a recollection, the layer is a decoration again.
MIN_RECALLED = 5

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def entries(path: Path) -> dict[str, dict]:
    data = load(path)
    return {k: v for k, v in data.items() if isinstance(v, dict)}


def overlap(first: str, second: str) -> float:
    """Jaccard overlap of character bigrams: what share of wording the two share."""
    def grams(text: str) -> set[str]:
        cleaned = re.sub(r"\s+", "", text)
        return {cleaned[i : i + 2] for i in range(len(cleaned) - 1)}

    a, b = grams(first), grams(second)
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def check_recall_pairing() -> None:
    for chapter in CHAPTERS:
        zh_path = INSPECTIONS / "zh-CN" / f"{chapter}.json"
        en_path = INSPECTIONS / "en" / f"{chapter}.json"
        if not zh_path.exists() or not en_path.exists():
            continue
        zh, en = entries(zh_path), entries(en_path)
        for key, zh_entry in zh.items():
            en_entry = en.get(key)
            if en_entry is None:
                continue
            zh_recall = zh_entry.get("recall")
            en_recall = en_entry.get("recall")

            if (zh_recall is None) != (en_recall is None):
                only = "zh-CN" if zh_recall else "en"
                failures.append(
                    f"{chapter}/{key}: only {only} has a 'recall' line. Each language loads "
                    "alone, so the player reads a different scene depending on the switch."
                )
                continue
            if zh_recall is None:
                continue

            for lang, recall in (("zh-CN", zh_recall), ("en", en_recall)):
                check(
                    bool(str(recall.get("text", "")).strip()),
                    f"{chapter}/{key} ({lang}): 'recall' has no text.",
                )
                check(
                    bool(str(recall.get("entry_id", "")).strip()),
                    f"{chapter}/{key} ({lang}): 'recall' has no entry_id, so it is never "
                    "written to the recollection list and the badge never appears.",
                )
            check(
                zh_recall.get("entry_id") == en_recall.get("entry_id"),
                f"{chapter}/{key}: recall entry ids differ between languages "
                f"({zh_recall.get('entry_id')!r} vs {en_recall.get('entry_id')!r}).",
            )

            # A memory must not be the observation said twice.
            for lang, entry in (("zh-CN", zh_entry), ("en", en_entry)):
                shared = overlap(
                    str(entry.get("text", "")), str(entry.get("recall", {}).get("text", ""))
                )
                check(
                    shared < MAX_OVERLAP,
                    f"{chapter}/{key} ({lang}): the recollection reuses {shared:.0%} of the "
                    "observation's wording. A memory that repeats the description teaches "
                    "nothing about the difference between seeing and remembering.",
                )


def check_recall_exists() -> None:
    """The layer has to actually carry content, not one token example."""
    for locale in LOCALES:
        recalled = 0
        total = 0
        for chapter in CHAPTERS:
            path = INSPECTIONS / locale / f"{chapter}.json"
            if not path.exists():
                continue
            for entry in entries(path).values():
                total += 1
                if entry.get("recall"):
                    recalled += 1
        check(
            recalled >= MIN_RECALLED,
            f"{locale}: {recalled} of {total} inspectable objects have a recollection; "
            f"the floor is {MIN_RECALLED}. Below it, remembering is a mood rather than a "
            "layer of the story.",
        )


## Words a voice uses when it is not sure. Either language: the check is about the stance.
DOUBT_MARKERS = (
    "可能", "也许", "拿不准", "不确定", "说不定", "记错", "记不住", "想不起",
    "maybe", "perhaps", "not sure", "cannot remember", "cannot say", "might have",
    "might be", "I think", "or I have", "fair question", "wrong",
)


def check_voices_admit_doubt() -> None:
    """A voice that never doubts itself is an oracle, and the bible forbids oracles."""
    for locale in LOCALES:
        path = DIALOGUE / locale / "inner_voice.json"
        if not path.exists():
            continue
        data = load(path)
        voices: dict[str, list[str]] = {}
        for conversation in data.get("conversations", {}).values():
            for node in conversation.get("nodes", []):
                speaker = str(node.get("speaker", ""))
                if not speaker.startswith("voice_"):
                    continue
                voices.setdefault(speaker, []).append(str(node.get("text", "")))
        for speaker, lines in voices.items():
            joined = " ".join(lines).lower()
            check(
                any(marker in joined for marker in DOUBT_MARKERS),
                f"inner_voice ({locale}): '{speaker}' never admits doubt in any of its "
                f"{len(lines)} line(s). A voice that is always right is a hint system, not "
                "a way of thinking.",
            )


def check_registry_matches_locales() -> None:
    """Every registered voice needs a speaker profile and a name in both languages."""
    structure = load(ABILITIES / "abilities.json")
    abilities = structure.get("abilities", {})
    check(bool(abilities), "abilities.json registers no voices at all.")

    for ability_id, ability in abilities.items():
        speaker = str(ability.get("speaker", ""))
        check(
            bool(speaker),
            f"ability '{ability_id}': no speaker, so its lines cannot be drawn.",
        )
        profile = ROOT / "data" / "characters" / f"{speaker}.tres"
        check(
            profile.exists(),
            f"ability '{ability_id}' names speaker '{speaker}', but "
            f"data/characters/{speaker}.tres does not exist. A voice without a profile "
            "fails at start-up.",
        )
        for locale in LOCALES:
            text = load(ABILITIES / f"{locale}.json").get("abilities", {})
            entry = text.get(ability_id)
            check(
                entry is not None,
                f"ability '{ability_id}' has no entry in data/abilities/{locale}.json.",
            )
            if entry is None:
                continue
            for field in ("name", "description"):
                check(
                    bool(str(entry.get(field, "")).strip()),
                    f"ability '{ability_id}' ({locale}): empty '{field}'.",
                )

    # A voice's passive rules must point at conversations that exist in every language.
    for locale in LOCALES:
        conversations = load(DIALOGUE / locale / "inner_voice.json").get("conversations", {})
        for rule in structure.get("passives", []):
            target = str(rule.get("conversation", ""))
            check(
                target in conversations,
                f"passive '{rule.get('id')}' ({locale}): triggers conversation '{target}', "
                "which inner_voice.json does not define. The voice would never speak.",
            )
            check(
                str(rule.get("ability", "")) in abilities,
                f"passive '{rule.get('id')}': names ability '{rule.get('ability')}', "
                "which is not registered.",
            )



## Every node id in a conversation, and whether the walk that the *runtime* performs can
## reach it. This is the loader's own rule, restated: a `choices` node follows only its
## options, a `check` node follows only its two branches, and an ordinary node follows `next`
## or, when `next` is absent, the next node in file order. A skipped `conditions` node is
## still reachable in the file sense; conditions decide at run time, not here.
def walk(graph: dict) -> set[str]:
    nodes = graph.get("nodes", [])
    order = [n["id"] for n in nodes]
    index = {node_id: i for i, node_id in enumerate(order)}
    reached: set[str] = set()
    stack = [graph.get("start")]
    while stack:
        node_id = stack.pop()
        if node_id in reached or node_id not in index:
            continue
        reached.add(node_id)
        node = nodes[index[node_id]]
        choices = node.get("choices") or []
        check = node.get("check") or {}
        if choices:
            stack.extend(choice.get("next") for choice in choices)
        elif check:
            stack.extend(check.get(branch) for branch in ("success", "failure"))
        elif node.get("next"):
            stack.append(node["next"])
        else:
            following = index[node_id] + 1
            if following < len(nodes):
                stack.append(nodes[following]["id"])
    return reached


def check_structure(locale: str) -> None:
    """The rules the loader enforces, so a content edit fails here instead of in the engine."""
    for path in sorted((DIALOGUE / locale).glob("*.json")):
        data = load(path)
        for conversation_id, graph in data.get("conversations", {}).items():
            nodes = graph.get("nodes", [])
            ids = [node["id"] for node in nodes]
            where = f"{path.name}/{conversation_id}"

            check(len(ids) == len(set(ids)), f"{where}: duplicate node ids.")
            if not nodes:
                check(False, f"{where}: no nodes.")
                continue
            known = set(ids)
            check(
                graph.get("start") in known,
                f"{where}: 'start' names '{graph.get('start')}', which is not a node.",
            )
            for node in nodes:
                targets = [c.get("next") for c in node.get("choices") or []]
                if node.get("check"):
                    targets += [
                        node["check"].get(b) for b in ("success", "failure")
                        if node["check"].get(b)
                    ]
                if node.get("next"):
                    targets.append(node["next"])
                for target in targets:
                    check(
                        target in known,
                        f"{where}/{node['id']}: points at '{target}', which does not exist.",
                    )
            # A check node never has `next` or `choices`, and both branches must lead on.
            for node in nodes:
                if not node.get("check"):
                    continue
                check(
                    not node.get("choices"),
                    f"{where}/{node['id']}: a check node also has choices.",
                )
                for branch in ("success", "failure"):
                    check(
                        branch in node["check"],
                        f"{where}/{node['id']}: check has no '{branch}'.",
                    )
            # The last node must end explicitly, unless it branches.
            last = nodes[-1]
            if not last.get("check") and not last.get("choices"):
                check(
                    "next" in last and last["next"] is None,
                    f"{where}: the last node '{last['id']}' does not end with \"next\": null, "
                    "so where the conversation stops is ambiguous.",
                )
            reached = walk(graph)
            unreachable = known - reached
            check(
                not unreachable,
                f"{where}: unreachable from '{graph.get('start')}': {sorted(unreachable)}. "
                "The runtime walks choices and check branches only, so this content is dead.",
            )


def check_parity() -> None:
    """Both languages must define the same conversations, in the same order, node for node."""
    for path in sorted((DIALOGUE / "zh-CN").glob("*.json")):
        other = DIALOGUE / "en" / path.name
        if not other.exists():
            failures.append(f"{path.name}: no English file.")
            continue
        zh, en = load(path), load(other)
        zh_ids = list(zh.get("conversations", {}))
        en_ids = list(en.get("conversations", {}))
        check(
            zh_ids == en_ids,
            f"{path.name}: the two languages define different conversations or different "
            f"orders ({zh_ids} vs {en_ids}).",
        )
        for conversation_id in zh_ids:
            # The guard tests the conversations table, not the file's top-level keys: `en` is
            # the whole document, so `conversation_id not in en` was always true and every
            # node comparison below it was dead code. The test passed while checking nothing.
            if conversation_id not in en.get("conversations", {}):
                continue
            a = zh["conversations"][conversation_id].get("nodes", [])
            b = en["conversations"][conversation_id].get("nodes", [])
            check(
                [n["id"] for n in a] == [n["id"] for n in b],
                f"{path.name}/{conversation_id}: node order differs between languages.",
            )
            for first, second in zip(a, b):
                check(
                    first.get("speaker") == second.get("speaker"),
                    f"{path.name}/{conversation_id}/{first['id']}: speaker differs "
                    f"({first.get('speaker')!r} vs {second.get('speaker')!r}). The same node "
                    "must be the same person speaking in both languages.",
                )
                if first.get("check") or second.get("check"):
                    for field in ("ability", "difficulty", "kind"):
                        check(
                            (first.get("check") or {}).get(field)
                            == (second.get("check") or {}).get(field),
                            f"{path.name}/{conversation_id}/{first['id']}: check.{field} "
                            "differs between languages, so the same attempt has two odds.",
                        )
                check(
                    len(first.get("choices") or []) == len(second.get("choices") or []),
                    f"{path.name}/{conversation_id}/{first['id']}: choice count differs.",
                )


## A passive rule fires without the player choosing to look, so the roll behind it is hidden and
## it must be the first thing in its conversation: the voice speaks before the player can act.
## The engine test states this too; restating it here means an edit that breaks it fails in
## seconds rather than after a fourteen-minute engine run.
def check_passive_openings() -> None:
    registry = load(ROOT / "data" / "abilities" / "abilities.json")
    # `abilities` is a table keyed by voice and `passives` is a flat list beside it.
    for rule in registry.get("passives", []):
        conversation_id = str(rule.get("conversation", ""))
        if not conversation_id:
            continue
        found = None
        for locale in LOCALES:
            for path in (DIALOGUE / locale).glob("*.json"):
                document = load(path)
                graph = document.get("conversations", {}).get(conversation_id)
                if graph:
                    found = (locale, path.name, graph)
                    break
            if found:
                break
        if not found:
            failures.append(
                f"passive '{rule.get('id')}' names conversation '{conversation_id}', which "
                "no chapter defines."
            )
            continue
        locale, name, graph = found
        start = graph.get("start")
        first = next((n for n in graph.get("nodes", []) if n.get("id") == start), None)
        check(first is not None, f"{name}/{conversation_id}: start node '{start}' is missing.")
        if first is None:
            continue
        roll = first.get("check") or {}
        check(
            bool(roll),
            f"{name}/{conversation_id}: a passive conversation must open with a hidden "
            "check, and the first node has none.",
        )
        if roll:
            check(
                str(roll.get("kind", "")) == "hidden",
                f"{name}/{conversation_id}: a passive roll is hidden, but the opening "
                f"check is '{roll.get('kind')}'.",
            )


## Every route in ConversationRouter must name conversations that exist, and every route must
## end with a fallback that always matches. A route whose rules all have requirements returns
## nothing in the state they do not cover, and OpeningSequence only finds out at run time.
##
## The table uses two shapes - one rule on the line it opens (`&"x": [{...`), and one rule per
## line under it - so the route is found by its line and its rules are the text up to the next
## route line or the closing bracket. Matching brackets by hand would be a parser; this is a
## test, and it anchors on the indentation the file actually uses.
def check_routes_resolve() -> None:
    source = (ROOT / "scripts" / "dialogue" / "conversation_router.gd").read_text(encoding="utf-8")
    defined: set[str] = set()
    for locale in LOCALES:
        for path in (DIALOGUE / locale).glob("*.json"):
            defined |= set(load(path).get("conversations", {}))
    route_lines = [
        (number, match.group(1), match.group(2))
        for number, match in (
            (i, re.match(r'\t&"([a-z_0-9]+)":\s*\[(.*)$', line))
            for i, line in enumerate(source.split(chr(10)))
        )
        if match
    ]
    check(bool(route_lines), "no routes were found in conversation_router.gd; the pattern is stale.")
    for index, (number, route_id, first_line) in enumerate(route_lines):
        rows = source.split(chr(10))
        # The body runs from this line to the line before the next route, then stops at the
        # first `	],` that closes the dictionary entry.
        stop = route_lines[index + 1][0] if index + 1 < len(route_lines) else len(rows)
        body_lines = [first_line]
        for line in rows[number + 1 : stop]:
            if line.strip() == "]," or line.strip() == "],".rstrip():
                break
            body_lines.append(line)
        body = chr(10).join(body_lines)
        names = re.findall(r'"conversation":\s*&"([a-z_0-9]+)"', body)
        check(bool(names), f"route '{route_id}' has no rules naming a conversation.")
        for name in names:
            check(
                name in defined,
                f"route '{route_id}' points at conversation '{name}', which no chapter defines.",
            )
        check(
            re.search(r'"requires":\s*\{\s*\}', body) is not None,
            f"route '{route_id}' has no catch-all rule, so an unmatched state resolves to nothing.",
        )

def main() -> int:
    check_recall_exists()
    check_recall_pairing()
    check_voices_admit_doubt()
    check_registry_matches_locales()
    for locale in LOCALES:
        check_structure(locale)
    check_parity()
    check_passive_openings()
    check_routes_resolve()
    if failures:
        for failure in failures:
            print(f"MEMORY_LAYER_FAILURE: {failure}")
        print(f"FAIL: {len(failures)} problem(s) found.")
        return 1
    print(
        "MEMORY_LAYER_OK: recollections are paired across languages and say something the "
        "observation did not; every inner voice admits it can be wrong; every voice has a "
        "profile and a name in both languages."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

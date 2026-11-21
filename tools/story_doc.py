#!/usr/bin/env python3
"""Story documents: the dialogue and inspection tables as editable scripts, and back.

The narrative lives in ``data/dialogue/<locale>/*.json`` and ``data/inspections/<locale>/*.json``.
Those files are exact but unreadable for a writer, so this tool turns the Chinese tables into
plain-text scripts ("台本") a writer can edit in Google Docs, and turns an edited script back
into the same JSON. The format is defined in ``docs/STORY_DOCS.zh-CN.md``.

    python3 tools/story_doc.py export --out build/story_doc            # *.txt (+ *.docx)
    python3 tools/story_doc.py import build/story_doc/returned/*.docx  # rewrites zh-CN JSON
    python3 tools/story_doc.py roundtrip                              # export→import is identity

Design rules, each of which the round-trip test (``tests/story_doc_test.py``) holds:

* **Every field is visible.** A line carries its stable ``[node_id]``; structure (next, choices,
  checks, conditions, effects, knowledge records) is written as short Chinese keyword lines, so
  a writer can add or remove lines and branches, not only reword them.
* **Nothing is lost.** Importing an unedited export reproduces the JSON byte for byte, including
  key order: rebuilt objects take the key order of the object they replace.
* **Chinese is the master.** Import rewrites ``zh-CN`` only. English keeps its texts by id and
  takes the Chinese structure (the build requires identical structure); every English text that
  is new or whose Chinese changed is listed in ``pending_en.json`` for translation.

Standard library only, ``.docx`` included. Google Docs converts the ``.docx`` on upload; a
returned document can be exported from Drive as ``.docx`` or plain text, and both import.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
MASTER = "zh-CN"
# The only abilities a subjective (imagined) conversation may roll; mirrors
# `DialogueGraph.IMAGINATION_ABILITIES` in scripts/dialogue/dialogue_graph.gd.
IMAGINATION_ABILITIES = ("whimsy",)
MIRROR = "en"

SOURCES = {"observed": "亲眼所见", "reported": "听人说的", "recalled": "记忆里的", "imagined": "想象中的"}
KINDS = {"visible": "可见", "hidden": "隐藏"}
END = "结束"
NARRATOR = "旁白"
SEP = "｜"
NEWLINE_MARK = "⏎"
# Locale keys a writer may edit in the plot document.
UI_PREFIXES = ("objective.", "place.", "end.")

CONV_HEAD = re.compile(r"^■\s*会话\s+(\S+)\s*$")
INSP_HEAD = re.compile(r"^■\s*检视\s+(\S+)\s*$")
CHAPTER_HEAD = re.compile(r"^▣\s*章节\s+(\S+)\s*$")
DOC_HEAD = re.compile(r"^◆\s*(对话|检视|界面文字)\s*(\S*)\s*$")
NODE_LINE = re.compile(r"^\[([^\]\s]+)\]\s*([^：:]+?)\s*[：:](.*)$")
CHOICE_LINE = re.compile(r"^◇\s*\[([^\]\s]+)\]\s*(.*?)\s*→\s*(\S+)\s*$")
RECORD_LINE = re.compile(r"^记录\s*\[([^\]\s]+)\]\s*(?:[（(]([^）)]*)[）)])?\s*[：:](.*)$")
RECALL_LINE = re.compile(r"^回想\s*\[([^\]\s]+)\]\s*[：:](.*)$")
UI_LINE = re.compile(r"^\[([a-z_]+\.[A-Za-z0-9_.]+)\]\s*(.*)$")
ATTR_LINE = re.compile(r"^(属性|来源|下一句|条件|效果|检定|仅一次|标签|标题|提示|说话人|首次|再看)\s*[：:]?\s*(.*)$")
BULLETS = "•·*-◦▪●○‣⁃ \t\u3000\u00a0"


class DocError(Exception):
    """A script line the importer cannot turn into data. The message names the line."""


# --------------------------------------------------------------------------------- data access


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def dialogue_path(locale: str, chapter: str) -> Path:
    return DATA / "dialogue" / locale / f"{chapter}.json"


def inspection_path(locale: str, chapter: str) -> Path:
    return DATA / "inspections" / locale / f"{chapter}.json"


def chapters(kind: str) -> list[str]:
    return sorted(p.stem for p in (DATA / kind / MASTER).glob("*.json"))


class Names:
    """Character id ↔ the label a writer reads (``Q``, ``你``, ``路感``…), from the data."""

    def __init__(self) -> None:
        strings = load_json(DATA / "locale" / f"{MASTER}.json")["strings"]
        self.objectives = strings
        self.speaker = {k[len("name."):]: v for k, v in strings.items() if k.startswith("name.")}
        registry = load_json(DATA / "abilities" / "abilities.json")["abilities"]
        voices = load_json(DATA / "abilities" / f"{MASTER}.json")["abilities"]
        self.ability = {}
        for ability_id, body in registry.items():
            name = voices.get(ability_id, {}).get("name", ability_id)
            self.ability[ability_id] = name
            self.speaker[body["speaker"]] = name
        self.speaker_back = {v: k for k, v in self.speaker.items()}
        self.speaker_back[NARRATOR] = "protagonist"
        self.ability_back = {v: k for k, v in self.ability.items()}

    def speaker_label(self, speaker: str, text: str = "", narration_hint: bool = False) -> str:
        if narration_hint and speaker == "protagonist" and is_narration(text):
            return NARRATOR
        return self.speaker.get(speaker, speaker)

    def speaker_id(self, label: str, where: str) -> str:
        label = label.strip()
        if label in self.speaker_back:
            return self.speaker_back[label]
        if label in self.speaker:
            return label
        raise DocError(f"{where}: 不认识的说话人「{label}」（可用：{'、'.join(self.speaker_back)}）")

    def ability_id(self, label: str, where: str) -> str:
        if label in self.ability_back:
            return self.ability_back[label]
        if label in self.ability:
            return label
        raise DocError(f"{where}: 不认识的能力「{label}」")


def is_narration(text: str) -> bool:
    """A protagonist line read as narration: no first person, not a quoted utterance.

    Only a reading aid. 旁白 and 你 both import as ``protagonist``, so the guess is lossless.
    """
    stripped = text.strip()
    if stripped.startswith(("（", "(")):
        return True
    return "我" not in stripped and not stripped.startswith(("「", "“", '"'))


# ----------------------------------------------------------------------------- small encoders


def enc_text(text: str) -> str:
    return text.replace("\n", NEWLINE_MARK)


def dec_text(text: str) -> str:
    return text.strip().replace(NEWLINE_MARK, "\n")


def enc_value(value) -> str:
    return json.dumps(value, ensure_ascii=False)


def dec_value(raw: str, where: str):
    raw = raw.strip().replace("“", '"').replace("”", '"')
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise DocError(f"{where}: 值「{raw}」不是 true/false/数字/\"文字\"") from exc


def enc_target(target) -> str:
    return END if target is None else str(target)


def dec_target(raw: str):
    raw = raw.strip()
    return None if raw in (END, "null") else raw


def split_list(raw: str) -> list[str]:
    return [part for part in re.split(r"[、,，\s]+", raw.strip()) if part]


def source_label(source: str) -> str:
    return SOURCES.get(source, source)


def source_id(label: str, where: str) -> str:
    label = label.strip()
    for key, name in SOURCES.items():
        if label in (key, name):
            return key
    raise DocError(f"{where}: 不认识的来源「{label}」（可用：{'、'.join(SOURCES.values())}）")


def enc_conditions(cond: dict) -> str:
    parts = []
    for key, value in cond.items():
        if key == "all_flags":
            parts.append("需要 " + "、".join(value))
        elif key == "not_flags":
            parts.append("排除 " + "、".join(value))
        elif key == "requires":
            parts.append("取值 " + "、".join(f"{k} = {enc_value(v)}" for k, v in value.items()))
        else:
            parts.append(f"原样 {key} = {enc_value(value)}")
    return SEP.join(parts)


def dec_conditions(raw: str, where: str) -> dict:
    cond: dict = {}
    for part in [p.strip() for p in raw.split(SEP) if p.strip()]:
        head, _, rest = part.partition(" ")
        if head == "需要":
            cond["all_flags"] = split_list(rest)
        elif head == "排除":
            cond["not_flags"] = split_list(rest)
        elif head == "取值":
            pairs = {}
            for item in re.split(r"[、，,]\s*(?=[^=]+=)", rest):
                name, eq, value = item.partition("=")
                if not eq:
                    raise DocError(f"{where}: 取值要写成「flag = 值」：{item}")
                pairs[name.strip()] = dec_value(value, where)
            cond["requires"] = pairs
        elif head == "原样":
            name, _, value = rest.partition("=")
            cond[name.strip()] = dec_value(value, where)
        else:
            raise DocError(f"{where}: 条件只认「需要／排除／取值」：{part}")
    return cond


# ------------------------------------------------------------------------------------- effects


def enc_effect(effect: dict, names: Names) -> str:
    kind = effect.get("type")
    if kind == "set_flag":
        return f"效果：设旗 {effect['flag']} = {enc_value(effect.get('value', True))}"
    if kind == "set_objective":
        preview = names.objectives.get(effect["key"])
        return f"效果：目标 {effect['key']}" + (f"（{preview}）" if preview else "")
    if kind == "record":
        meta = [f"来源 {source_label(effect.get('source', 'observed'))}"]
        if "speaker" in effect:
            meta.append(f"说话人 {names.speaker_label(effect['speaker'])}")
        return f"记录 [{effect['entry_id']}]（{'，'.join(meta)}）：{enc_text(effect.get('text', ''))}"
    if kind == "camera_focus" and set(effect) == {"type", "target"}:
        return f"效果：聚焦 {effect['target']}"
    return f"效果：原样 {enc_value(effect)}"


def dec_effect(line: str, names: Names, where: str) -> dict:
    match = RECORD_LINE.match(line)
    if match:
        effect = {"type": "record", "entry_id": match.group(1)}
        for item in re.split(r"[，,]", match.group(2) or ""):
            key, _, value = item.strip().partition(" ")
            if key == "来源":
                effect["source"] = source_id(value, where)
            elif key == "说话人":
                effect["speaker"] = names.speaker_id(value, where)
            elif key:
                raise DocError(f"{where}: 记录括号里只认「来源／说话人」：{item}")
        effect["text"] = dec_text(match.group(3))
        return effect
    body = ATTR_LINE.match(line).group(2).strip()
    head, _, rest = body.partition(" ")
    if head == "设旗":
        flag, eq, value = rest.partition("=")
        return {"type": "set_flag", "flag": flag.strip(), "value": dec_value(value, where) if eq else True}
    if head == "目标":
        key = rest.split("（", 1)[0].strip()  # the bracketed text is a preview, not data
        if not re.fullmatch(r"objective\.[a-z0-9_]+", key):
            raise DocError(f"{where}: 目标要写成「目标 objective.xxx」：{body}")
        return {"type": "set_objective", "key": key}
    if head == "聚焦":
        target = rest.strip()
        if not re.fullmatch(r"[a-z0-9_]+", target):
            raise DocError(f"{where}: 聚焦要写成「聚焦 <交互物 id>」，例如「聚焦 set_square」：{body}")
        return {"type": "camera_focus", "target": target}
    if head == "原样":
        return dec_value(rest, where)
    raise DocError(f"{where}: 效果只认「设旗／目标／聚焦」或「记录 [...]」：{body}")


# --------------------------------------------------------------------------------------- check


def enc_check(check: dict, names: Names) -> str:
    text = (
        f"检定：{names.ability.get(check['ability'], check['ability'])} 难度 {check['difficulty']} "
        f"{KINDS.get(check['kind'], check['kind'])} → 成功 {enc_target(check.get('success'))}，"
        f"失败 {enc_target(check.get('failure'))}"
    )
    extra = []
    if "modifiers" in check:
        mods = "、".join(f"{m['flag']} {m['value']:+d}" for m in check["modifiers"])
        extra.append(f"加值 {mods}")
    if "repeatable" in check:
        extra.append(f"可重复 {enc_value(check['repeatable'])}")
    return SEP.join([text, *extra])


CHECK_BODY = re.compile(r"^(\S+)\s+难度\s*(\d+)\s*(\S+)\s*→\s*成功\s*(\S+?)\s*[，,]\s*失败\s*(\S+)\s*$")


def dec_check(raw: str, names: Names, where: str) -> dict:
    head, *extras = [p.strip() for p in raw.split(SEP)]
    match = CHECK_BODY.match(head)
    if not match:
        raise DocError(f"{where}: 检定要写成「路感 难度 9 可见 → 成功 a，失败 b」：{head}")
    kind = {v: k for k, v in KINDS.items()}.get(match.group(3), match.group(3))
    check = {
        "ability": names.ability_id(match.group(1), where),
        "difficulty": int(match.group(2)),
        "kind": kind,
        "success": dec_target(match.group(4)),
        "failure": dec_target(match.group(5)),
    }
    for extra in extras:
        key, _, rest = extra.partition(" ")
        if key == "加值":
            mods = []
            for item in [part.strip() for part in re.split(r"[、，,]", rest) if part.strip()]:
                match = re.match(r"^(\S+)\s+([+-]?\d+)$", item)
                if not match:
                    raise DocError(f"{where}: 加值要写成「flag +1」：{item}")
                mods.append({"flag": match.group(1), "value": int(match.group(2))})
            check["modifiers"] = mods
        elif key == "可重复":
            check["repeatable"] = dec_value(rest, where)
        elif extra:
            raise DocError(f"{where}: 检定附加项只认「加值／可重复」：{extra}")
    return check


# ----------------------------------------------------------------------------- key-order merge


def ordered_like(new, old):
    """``new`` with the key order of ``old`` (recursively); keys only in ``new`` go last."""
    if isinstance(new, dict) and isinstance(old, dict):
        keys = [k for k in old if k in new] + [k for k in new if k not in old]
        return {k: ordered_like(new[k], old.get(k)) for k in keys}
    if isinstance(new, list) and isinstance(old, list):
        by_id = {item.get("id"): item for item in old if isinstance(item, dict) and "id" in item}
        out = []
        for index, item in enumerate(new):
            if isinstance(item, dict) and "id" in item:
                match = by_id.get(item["id"])
            else:
                match = old[index] if index < len(old) else None
                if isinstance(item, dict) and isinstance(match, dict) and item.get("type") != match.get("type"):
                    match = None
            out.append(ordered_like(item, match))
        return out
    return new


# ------------------------------------------------------------------------------ export: dialogue


def export_dialogue(chapter: str, names: Names, triggers: dict) -> list[tuple[str, str]]:
    data = load_json(dialogue_path(MASTER, chapter))
    out = [("title", f"◆ 对话 {chapter}")]
    for conv_id, conv in data["conversations"].items():
        # A line that repeats the option the player just picked is the protagonist speaking.
        echoes = {
            choice.get("next"): choice.get("text", "")
            for node in conv["nodes"]
            for choice in node.get("choices", [])
        }
        out.append(("h2", f"■ 会话 {conv_id}"))
        for note in triggers.get(conv_id, []):
            out.append(("note", f"※ 触发：{note}"))
        attrs = []
        for key, value in conv.items():
            if key == "start":
                attrs.append(f"起点 {value}")
            elif key == "default_source":
                attrs.append(f"默认来源 {source_label(value)}")
            elif key == "subjective":
                attrs.append(f"主观 {'是' if value else '否'}")
        out.append(("attr", "属性：" + SEP.join(attrs)))
        for node in conv["nodes"]:
            spoken = echoes.get(node["id"]) == node.get("text")
            out.extend(export_node(node, names, spoken))
    return out


def export_node(node: dict, names: Names, spoken: bool = False) -> list[tuple[str, str]]:
    label = names.speaker_label(node["speaker"], node.get("text", ""), narration_hint=not spoken)
    out = [("line", f"[{node['id']}] {label}：{enc_text(node.get('text', ''))}")]
    for key, value in node.items():
        if key == "source":
            out.append(("attr", f"来源：{source_label(value)}"))
        elif key == "next":
            out.append(("attr", f"下一句：{enc_target(value)}"))
        elif key == "conditions":
            out.append(("attr", f"条件：{enc_conditions(value)}"))
        elif key == "effects":
            out.extend(("attr", enc_effect(effect, names)) for effect in value)
        elif key == "check":
            out.append(("attr", enc_check(value, names)))
        elif key == "tags":
            out.append(("attr", "标签：" + "、".join(value)))
    for choice in node.get("choices", []):
        out.append(("choice", f"◇ [{choice['id']}] {enc_text(choice.get('text', ''))} → {enc_target(choice.get('next'))}"))
        for key, value in choice.items():
            if key == "conditions":
                out.append(("cattr", f"条件：{enc_conditions(value)}"))
            elif key == "once" and value:
                out.append(("cattr", "仅一次"))
            elif key == "once":
                out.append(("cattr", f"仅一次：{enc_value(value)}"))
            elif key == "effects":
                out.extend(("cattr", enc_effect(effect, names)) for effect in value)
    return out


# ---------------------------------------------------------------------------- export: inspection

INSPECTION_FIELDS = {"title": "标题", "prompt": "提示", "text": "首次", "repeat_text": "再看"}


def export_inspections(names: Names) -> list[tuple[str, str]]:
    out = [("title", "◆ 检视 全部")]
    for chapter in chapters("inspections"):
        data = load_json(inspection_path(MASTER, chapter))
        out.append(("h1", f"▣ 章节 {chapter}"))
        for item_id, item in data.items():
            if not isinstance(item, dict):
                continue
            out.append(("h2", f"■ 检视 {item_id}"))
            for key, value in item.items():
                if key in INSPECTION_FIELDS:
                    out.append(("line", f"{INSPECTION_FIELDS[key]}：{enc_text(value)}"))
                elif key == "speaker":
                    out.append(("attr", f"说话人：{names.speaker_label(value)}"))
                elif key == "source":
                    out.append(("attr", f"来源：{source_label(value)}"))
                elif key == "recall":
                    out.append(("attr", f"回想 [{value['entry_id']}]：{enc_text(value['text'])}"))
                elif key == "record":
                    out.append(("attr", enc_effect({"type": "record", **value}, names)))
                elif key == "effects":
                    out.extend(("attr", enc_effect(effect, names)) for effect in value)
    return out


# ------------------------------------------------------------------------------- export: UI text


def export_ui_strings() -> list[tuple[str, str]]:
    strings = load_json(DATA / "locale" / f"{MASTER}.json")["strings"]
    out = [("title", "◆ 界面文字")]
    for prefix, title in (("objective.", "目标条"), ("place.", "地名"), ("end.", "结束卡")):
        out.append(("h2", f"※ {title}"))
        for key, value in strings.items():
            if key.startswith(prefix):
                out.append(("line", f"[{key}] {enc_text(value)}"))
    return out


# ---------------------------------------------------------------------------------- the parser


def clean(raw: str) -> str:
    return raw.strip(BULLETS).rstrip()


def parse_document(lines: list[str], names: Names) -> tuple[str, str, dict]:
    """Returns ``(kind, chapter, payload)`` for one returned document."""
    kind = chapter = ""
    for raw in lines:
        match = DOC_HEAD.match(clean(raw))
        if match:
            kind, chapter = match.group(1), match.group(2)
            break
    if not kind:
        raise DocError("找不到文档开头的「◆ 对话 …」「◆ 检视 …」或「◆ 界面文字」标题行；请勿删除它")
    if kind == "对话":
        return kind, chapter, parse_dialogue(lines, names)
    if kind == "检视":
        return kind, chapter, parse_inspections(lines, names)
    return kind, chapter, parse_ui(lines)


def parse_dialogue(lines: list[str], names: Names) -> dict:
    conversations: dict = {}
    conv = node = choice = None
    conv_id = ""
    for number, raw in enumerate(lines, 1):
        line = clean(raw)
        where = f"第 {number} 行"
        if not line or line.startswith(("※", "//", "◆")):
            continue
        head = CONV_HEAD.match(line)
        if head:
            conv_id = head.group(1)
            if conv_id in conversations:
                raise DocError(f"{where}: 会话 {conv_id} 出现了两次")
            conv = conversations[conv_id] = {"nodes": []}
            node = choice = None
            continue
        if conv is None:
            continue
        where = f"{where}（会话 {conv_id}）"
        match = NODE_LINE.match(line)
        if match and not line.startswith(("◇", "记录", "回想")):
            node = {
                "id": match.group(1),
                "speaker": names.speaker_id(match.group(2), where),
                "text": dec_text(match.group(3)),
            }
            conv["nodes"].append(node)
            choice = None
            continue
        match = CHOICE_LINE.match(line)
        if match:
            if node is None:
                raise DocError(f"{where}: 选项必须写在某一句台词下面")
            choice = {"id": match.group(1), "text": dec_text(match.group(2)), "next": dec_target(match.group(3))}
            node.setdefault("choices", []).append(choice)
            continue
        if line.startswith("属性"):
            conv.update(parse_conv_attrs(ATTR_LINE.match(line).group(2), where))
            continue
        target = choice if choice is not None else node
        if target is None:
            raise DocError(f"{where}: 这一行不属于任何台词：{line}")
        apply_attr(target, line, names, where, is_choice=choice is not None)
    for conv_id, conv in conversations.items():
        conversations[conv_id] = {k: v for k, v in conv.items() if k != "nodes"} | {"nodes": conv["nodes"]}
    return conversations


def parse_conv_attrs(raw: str, where: str) -> dict:
    attrs: dict = {}
    for part in [p.strip() for p in raw.split(SEP) if p.strip()]:
        key, _, value = part.partition(" ")
        value = value.strip()
        if key == "起点":
            attrs["start"] = value
        elif key == "默认来源":
            attrs["default_source"] = source_id(value, where)
        elif key == "主观":
            if value not in ("是", "否"):
                raise DocError(f"{where}: 主观只能写「是」或「否」")
            attrs["subjective"] = value == "是"
        else:
            raise DocError(f"{where}: 属性只认「起点／默认来源／主观」：{part}")
    return attrs


def apply_attr(target: dict, line: str, names: Names, where: str, is_choice: bool) -> None:
    if line.startswith("记录"):
        target.setdefault("effects", []).append(dec_effect(line, names, where))
        return
    match = ATTR_LINE.match(line)
    if not match:
        raise DocError(f"{where}: 看不懂这一行（台词要以 [id] 开头，选项以 ◇ 开头）：{line}")
    key, value = match.group(1), match.group(2).strip()
    allowed = {"条件", "仅一次", "效果"} if is_choice else {"来源", "下一句", "条件", "效果", "检定", "标签"}
    if key not in allowed:
        owner = "选项" if is_choice else "台词"
        raise DocError(f"{where}: {owner}下面不能写「{key}」")
    if key == "来源":
        target["source"] = source_id(value, where)
    elif key == "下一句":
        target["next"] = dec_target(value)
    elif key == "条件":
        target["conditions"] = dec_conditions(value, where)
    elif key == "效果":
        target.setdefault("effects", []).append(dec_effect(line, names, where))
    elif key == "检定":
        target["check"] = dec_check(value, names, where)
    elif key == "仅一次":
        target["once"] = dec_value(value, where) if value else True
    elif key == "标签":
        target["tags"] = split_list(value)


def parse_inspections(lines: list[str], names: Names) -> dict:
    result: dict = {}
    chapter = item_id = ""
    item = None
    reverse = {v: k for k, v in INSPECTION_FIELDS.items()}
    for number, raw in enumerate(lines, 1):
        line = clean(raw)
        where = f"第 {number} 行"
        if not line or line.startswith(("※", "//", "◆")):
            continue
        match = CHAPTER_HEAD.match(line)
        if match:
            chapter = match.group(1)
            result.setdefault(chapter, {})
            item = None
            continue
        match = INSP_HEAD.match(line)
        if match:
            if not chapter:
                raise DocError(f"{where}: 检视条目必须放在某个「▣ 章节 …」下面")
            item_id = match.group(1)
            item = result[chapter][item_id] = {}
            continue
        if item is None:
            continue
        where = f"{where}（检视 {item_id}）"
        if line.startswith("记录"):
            record = dec_effect(line, names, where)
            record.pop("type")
            item["record"] = record
            continue
        match = RECALL_LINE.match(line)
        if match:
            item["recall"] = {"entry_id": match.group(1), "text": dec_text(match.group(2))}
            continue
        match = ATTR_LINE.match(line)
        if not match:
            raise DocError(f"{where}: 看不懂这一行：{line}")
        key, value = match.group(1), match.group(2)
        if key in reverse:
            item[reverse[key]] = dec_text(value)
        elif key == "说话人":
            item["speaker"] = names.speaker_id(value, where)
        elif key == "来源":
            item["source"] = source_id(value, where)
        elif key == "效果":
            item.setdefault("effects", []).append(dec_effect(line, names, where))
        else:
            raise DocError(f"{where}: 检视条目里不能写「{key}」")
    return result


def parse_ui(lines: list[str]) -> dict:
    strings = {}
    for raw in lines:
        match = UI_LINE.match(clean(raw))
        if match and match.group(1).startswith(UI_PREFIXES):
            strings[match.group(1)] = dec_text(match.group(2))
    return strings


# ------------------------------------------------------------------------- import: validation


def validate_conversations(conversations: dict) -> list[str]:
    """The structural rules a writer can break in a document, checked before anything is written.

    The Godot content tests stay the authority; this only makes the common mistakes come back
    as Chinese messages that name the conversation and the line, instead of a CI failure.
    """
    errors = []
    for conv_id, conv in conversations.items():
        nodes = conv["nodes"]
        ids = [node["id"] for node in nodes]
        where = f"会话 {conv_id}"
        if not nodes:
            errors.append(f"{where}: 没有任何台词")
            continue
        for dup in sorted({i for i in ids if ids.count(i) > 1}):
            errors.append(f"{where}: [{dup}] 用了两次，id 不能重复")
        known = set(ids)
        if conv.get("start") not in known:
            errors.append(f"{where}: 起点 {conv.get('start')} 不是本会话里的台词")
        if "next" not in nodes[-1] or nodes[-1]["next"] is not None:
            if "choices" not in nodes[-1] and "check" not in nodes[-1]:
                errors.append(f"{where}: 最后一句 [{nodes[-1]['id']}] 必须写「下一句：结束」")
        subjective = conv.get("subjective", False)
        for node in nodes:
            here = f"{where} [{node['id']}]"
            targets = []
            if node.get("next") is not None:
                targets.append(("下一句", node["next"]))
            check = node.get("check")
            if check:
                if "choices" in node or "next" in node:
                    errors.append(f"{here}: 带检定的台词不能再写「下一句」或选项")
                targets += [("成功", check.get("success")), ("失败", check.get("failure"))]
            choice_ids = [c["id"] for c in node.get("choices", [])]
            for dup in sorted({i for i in choice_ids if choice_ids.count(i) > 1}):
                errors.append(f"{here}: 选项 [{dup}] 用了两次")
            for choice in node.get("choices", []):
                targets.append((f"选项 {choice['id']}", choice.get("next")))
                if not choice.get("text"):
                    errors.append(f"{here}: 选项 [{choice['id']}] 没有文字")
                if subjective and choice.get("once"):
                    errors.append(f"{here}: 主观会话里的选项不能「仅一次」")
            for label, target in targets:
                if target is not None and target not in known:
                    errors.append(f"{here}: {label} 指向 {target}，本会话里没有这句")
            if not node.get("text") and not node.get("choices"):
                errors.append(f"{here}: 台词是空的")
            if subjective:
                if check and check.get("ability") not in IMAGINATION_ABILITIES:
                    errors.append(f"{here}: 主观会话只能带「异想天开」检定")
                effects = [e for holder in [node, *node.get("choices", [])] for e in holder.get("effects", [])]
                for effect in effects:
                    if effect.get("type") in ("set_flag", "set_objective"):
                        errors.append(f"{here}: 主观会话不能设旗或改目标")
                    if effect.get("type") == "record" and effect.get("source") in ("observed", "reported"):
                        errors.append(f"{here}: 主观会话只能记录「记忆里的／想象中的」")
    return errors


def structure_changes(old: dict, new: dict) -> list[str]:
    """What changed besides wording, so a reviewer sees moved effects and new branches."""
    notes = []
    for conv_id in [c for c in old if c not in new]:
        notes.append(f"删除会话 {conv_id}")
    for conv_id, conv in new.items():
        if conv_id not in old:
            notes.append(f"新增会话 {conv_id}（{len(conv['nodes'])} 句）")
            continue
        before = {n["id"]: n for n in old[conv_id]["nodes"]}
        after = {n["id"]: n for n in conv["nodes"]}
        for node_id in [n for n in before if n not in after]:
            notes.append(f"{conv_id}: 删除 [{node_id}]")
        for node_id, node in after.items():
            if node_id not in before:
                notes.append(f"{conv_id}: 新增 [{node_id}]")
                continue
            strip = lambda n: json.dumps(  # noqa: E731 - compare everything but wording
                {k: v for k, v in strip_text(n).items()}, ensure_ascii=False, sort_keys=True)
            if strip(node) != strip(before[node_id]):
                notes.append(f"{conv_id}: [{node_id}] 的结构变了（说话人／跳转／条件／效果／选项）")
        if [n["id"] for n in old[conv_id]["nodes"] if n["id"] in after] != [n for n in after if n in before]:
            notes.append(f"{conv_id}: 台词顺序变了（没写「下一句」的台词会按新顺序接着播）")
        if {k: v for k, v in old[conv_id].items() if k != "nodes"} != {k: v for k, v in conv.items() if k != "nodes"}:
            notes.append(f"{conv_id}: 会话属性变了")
    return notes


def strip_text(data):
    if isinstance(data, dict):
        return {k: strip_text(v) for k, v in data.items() if k not in TEXT_KEYS}
    if isinstance(data, list):
        return [strip_text(v) for v in data]
    return data


# ---------------------------------------------------------------------------- import: rebuild


def rebuild_dialogue(chapter: str, conversations: dict) -> dict:
    old = load_json(dialogue_path(MASTER, chapter))
    new = {k: v for k, v in old.items() if k != "conversations"}
    new["conversations"] = conversations
    return ordered_like(new, old)


def rebuild_inspections(chapter: str, items: dict) -> dict:
    path = inspection_path(MASTER, chapter)
    old = load_json(path) if path.exists() else {"format_version": 1, "locale": MASTER}
    new = {k: v for k, v in old.items() if not isinstance(v, dict)}
    new.update(items)
    return ordered_like(new, old)


TEXT_KEYS = ("text", "repeat_text", "title", "prompt")


def text_slots(data, path=()):
    """Yields ``(path, text)`` for every translatable string, addressed by stable ids."""
    if isinstance(data, dict):
        for key, value in data.items():
            if key in TEXT_KEYS and isinstance(value, str):
                yield path + (key,), value
            elif key not in ("id",):
                yield from text_slots(value, path + (key,))
    elif isinstance(data, list):
        for index, item in enumerate(data):
            if isinstance(item, dict) and "id" in item:
                yield from text_slots(item, path + (f"#{item['id']}",))
            elif isinstance(item, dict) and "entry_id" in item:
                yield from text_slots(item, path + (f"@{item['entry_id']}",))
            else:
                yield from text_slots(item, path + (index,))


def set_slot(data, path, value) -> None:
    node = data
    for step in path[:-1]:
        if isinstance(step, str) and step[:1] in "#@" and isinstance(node, list):
            key = "id" if step[0] == "#" else "entry_id"
            node = next(item for item in node if isinstance(item, dict) and item.get(key) == step[1:])
        else:
            node = node[step]
    node[path[-1]] = value


def mirror(new_master: dict, old_master: dict, old_mirror: dict, locale: str) -> tuple[dict, list]:
    """The mirror locale with the master's structure and its own texts, plus what is pending."""
    out = copy.deepcopy(new_master)
    if "locale" in out:
        out["locale"] = locale
    old_master_texts = dict(text_slots(old_master))
    old_mirror_texts = dict(text_slots(old_mirror))
    pending = []
    for path, text in text_slots(new_master):
        kept = old_mirror_texts.get(path)
        if kept is not None and old_master_texts.get(path) == text:
            set_slot(out, path, kept)
            continue
        pending.append({"path": [str(p) for p in path], "zh": text, "zh_before": old_master_texts.get(path), "en_before": kept})
        set_slot(out, path, kept if kept is not None else text)
    return ordered_like(out, old_mirror), pending


def apply_document(lines: list[str], names: Names, write: bool) -> dict:
    """Imports one returned document. Returns a summary with the files it changed."""
    kind, chapter, payload = parse_document(lines, names)
    changed, pending = [], []
    targets: list[tuple[Path, dict, Path, dict, dict]] = []
    structure: list[str] = []
    if kind == "对话":
        errors = validate_conversations(payload)
        if errors:
            raise DocError("\n  ".join(["结构有问题，未写入任何文件："] + errors))
        structure = structure_changes(load_json(dialogue_path(MASTER, chapter))["conversations"], payload)
        new = rebuild_dialogue(chapter, payload)
        targets.append((dialogue_path(MASTER, chapter), new, dialogue_path(MIRROR, chapter), {}, {}))
    elif kind == "检视":
        for name, items in payload.items():
            new = rebuild_inspections(name, items)
            targets.append((inspection_path(MASTER, name), new, inspection_path(MIRROR, name), {}, {}))
    else:
        return apply_ui(payload, write)
    for master_path, new, mirror_path, _, _ in targets:
        old_master = load_json(master_path) if master_path.exists() else {}
        old_mirror = load_json(mirror_path) if mirror_path.exists() else {}
        new_mirror, todo = mirror(new, old_master, old_mirror, MIRROR)
        for item in todo:
            item["file"] = str(mirror_path.relative_to(ROOT))
        pending.extend(todo)
        for path, data in ((master_path, new), (mirror_path, new_mirror)):
            text = dump_json(data)
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                changed.append(str(path.relative_to(ROOT)))
                if write:
                    path.write_text(text, encoding="utf-8")
    return {"kind": kind, "chapter": chapter, "changed": changed, "pending_en": pending,
            "structure": structure}


def apply_ui(strings: dict, write: bool) -> dict:
    master_path = DATA / "locale" / f"{MASTER}.json"
    mirror_path = DATA / "locale" / f"{MIRROR}.json"
    master, mirror_data = load_json(master_path), load_json(mirror_path)
    pending, unknown = [], []
    for key, value in strings.items():
        if key not in master["strings"]:
            unknown.append(key)
            continue
        if master["strings"][key] != value:
            pending.append({"file": str(mirror_path.relative_to(ROOT)), "path": ["strings", key],
                            "zh": value, "zh_before": master["strings"][key],
                            "en_before": mirror_data["strings"].get(key)})
            master["strings"][key] = value
    if unknown:
        raise DocError("界面文字只能改已有的键，新的键请写批注：" + "、".join(unknown))
    changed = []
    if pending:
        changed.append(str(master_path.relative_to(ROOT)))
        if write:
            master_path.write_text(dump_json(master), encoding="utf-8")
    return {"kind": "界面文字", "chapter": "", "changed": changed, "pending_en": pending, "structure": []}


# ------------------------------------------------------------------------------- the documents


def build_all(names: Names) -> dict[str, list[tuple[str, str]]]:
    from story_doc_plot import plot_document, trigger_notes  # noqa: PLC0415 - sibling module

    triggers = trigger_notes()
    docs = {"00_剧情安排": plot_document(names) + export_ui_strings()}
    for index, chapter in enumerate(chapter_order(), 1):
        docs[f"{index:02d}_对话_{chapter}"] = export_dialogue(chapter, names, triggers)
    docs[f"{len(docs):02d}_检视文字"] = export_inspections(names)
    return docs


def chapter_order() -> list[str]:
    preferred = ["prologue", "corridor", "school_annexes", "street", "residential", "alley",
                 "playground", "inner_voice"]
    present = chapters("dialogue")
    return [c for c in preferred if c in present] + [c for c in present if c not in preferred]


# ------------------------------------------------------------------------------------ .docx I/O
#
# A .docx is a zip of XML parts. The scripts only need paragraphs, four heading levels and a
# few run colours, so the standard library writes and reads them: no python-docx, and the
# tool runs anywhere the repository's Python tests run. Google Docs converts this on upload
# and exports a .docx (or plain text) that :func:`read_lines` reads back.

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
DOCX_HEADINGS = {"title": ("Title", 20), "h1": ("Heading1", 16), "h2": ("Heading2", 13), "h3": ("Heading3", 12)}
DOCX_SMALL = {"attr": "6B6B6B", "cattr": "6B6B6B", "note": "6B6B6B", "ref": "6B6B6B"}

DOCX_PARTS = {
    "[Content_Types].xml": (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        "</Types>"
    ),
    "_rels/.rels": (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        "</Relationships>"
    ),
    "word/_rels/document.xml.rels": (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        "</Relationships>"
    ),
}


def docx_styles() -> str:
    styles = [
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
        '<w:pPr><w:spacing w:after="60"/></w:pPr><w:rPr><w:sz w:val="22"/></w:rPr></w:style>'
    ]
    for style_id, size in DOCX_HEADINGS.values():
        name = "Title" if style_id == "Title" else f"heading {style_id[-1]}"
        level = "" if style_id == "Title" else f'<w:outlineLvl w:val="{int(style_id[-1]) - 1}"/>'
        styles.append(
            f'<w:style w:type="paragraph" w:styleId="{style_id}"><w:name w:val="{name}"/>'
            f'<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
            f'<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/>{level}</w:pPr>'
            f'<w:rPr><w:b/><w:sz w:val="{size * 2}"/></w:rPr></w:style>'
        )
    return (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="{W_NS}">'
        + "".join(styles)
        + "</w:styles>"
    )


def docx_run(text: str, size: int | None = None, color: str | None = None) -> str:
    from xml.sax.saxutils import escape  # noqa: PLC0415 - only the .docx path needs it

    props = (f'<w:color w:val="{color}"/>' if color else "") + (f'<w:sz w:val="{size * 2}"/>' if size else "")
    return f'<w:r>{f"<w:rPr>{props}</w:rPr>" if props else ""}<w:t xml:space="preserve">{escape(text)}</w:t></w:r>'


def docx_paragraph(style: str, text: str) -> str:
    if style in DOCX_HEADINGS:
        return f'<w:p><w:pPr><w:pStyle w:val="{DOCX_HEADINGS[style][0]}"/></w:pPr>{docx_run(text)}</w:p>'
    indent = '<w:pPr><w:ind w:left="360"/></w:pPr>' if style == "cattr" else ""
    if style in DOCX_SMALL:
        runs = docx_run(text, 9, DOCX_SMALL[style])
    elif style == "choice":
        runs = docx_run(text, None, "1F5C99")
    elif style == "line" and text.startswith("[") and "] " in text:
        cut = text.index("] ") + 2  # the [id] tag is small and grey so the line reads first
        runs = docx_run(text[:cut], 8, "999999") + docx_run(text[cut:])
    else:
        runs = docx_run(text)
    return f"<w:p>{indent}{runs}</w:p>"


def write_docx(lines: list[tuple[str, str]], path: Path) -> None:
    import zipfile  # noqa: PLC0415

    body = "".join(docx_paragraph(style, text) for style, text in lines)
    document = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="{W_NS}"><w:body>'
        f'{body}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/>'
        "</w:sectPr></w:body></w:document>"
    )
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, xml in DOCX_PARTS.items():
            archive.writestr(name, xml)
        archive.writestr("word/styles.xml", docx_styles())
        archive.writestr("word/document.xml", document)


def read_docx_lines(path: Path) -> list[str]:
    """Every paragraph's text, in order. Tracked deletions are skipped; a soft line break
    (Shift+Enter in Google Docs) splits a paragraph into two script lines."""
    import xml.etree.ElementTree as ET  # noqa: PLC0415
    import zipfile  # noqa: PLC0415

    with zipfile.ZipFile(path) as archive:
        root = ET.fromstring(archive.read("word/document.xml"))
    tag = lambda name: f"{{{W_NS}}}{name}"  # noqa: E731
    lines: list[str] = []
    for paragraph in root.iter(tag("p")):
        parts: list[str] = []
        for node in paragraph.iter():
            if node.tag == tag("t"):
                parts.append(node.text or "")
            elif node.tag in (tag("br"), tag("cr")):
                parts.append("\n")
            elif node.tag == tag("tab"):
                parts.append("\t")
        lines.extend("".join(parts).split("\n"))
    return lines


def read_lines(path: Path) -> list[str]:
    if path.suffix == ".docx":
        return read_docx_lines(path)
    return path.read_text(encoding="utf-8-sig").splitlines()


# ------------------------------------------------------------------------------------- the CLI


def cmd_export(args) -> int:
    names = Names()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, lines in build_all(names).items():
        (out / f"{name}.txt").write_text("\n".join(text for _, text in lines) + "\n", encoding="utf-8")
        if not args.text_only:
            write_docx(lines, out / f"{name}.docx")
        print(f"wrote {out / name}")
    return 0


def cmd_import(args) -> int:
    names = Names()
    pending, failed = [], False
    for raw in args.files:
        path = Path(raw)
        try:
            summary = apply_document(read_lines(path), names, write=not args.dry_run)
        except DocError as exc:
            print(f"{path.name}: {exc}", file=sys.stderr)
            failed = True
            continue
        pending.extend(summary["pending_en"])
        changed = "、".join(summary["changed"]) or "无变化"
        print(f"{path.name}: {summary['kind']} {summary['chapter']} → {changed}")
        for note in summary["structure"]:
            print(f"  结构：{note}")
    if args.pending and not args.dry_run:
        Path(args.pending).parent.mkdir(parents=True, exist_ok=True)
        Path(args.pending).write_text(json.dumps(pending, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{len(pending)} English text(s) to translate → {args.pending}")
    return 1 if failed else 0


def roundtrip_errors() -> list[str]:
    """Export every table and import it again; any difference is an error."""
    names = Names()
    errors = []
    for name, lines in build_all(names).items():
        try:
            summary = apply_document([text for _, text in lines], names, write=False)
        except DocError as exc:
            errors.append(f"{name}: {exc}")
            continue
        for path in summary["changed"]:
            errors.append(f"{name}: round trip would rewrite {path}")
        if summary["structure"]:
            errors.append(f"{name}: round trip reported structure changes: {summary['structure'][:3]}")
        if summary["pending_en"]:
            errors.append(f"{name}: round trip invented {len(summary['pending_en'])} pending translation(s)")
    return errors


def cmd_roundtrip(_args) -> int:
    errors = roundtrip_errors()
    for error in errors:
        print(error, file=sys.stderr)
    print("story_doc round trip: " + ("FAILED" if errors else "ok"))
    return 1 if errors else 0


def main(argv: list[str] | None = None) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    sub = parser.add_subparsers(dest="command", required=True)
    export = sub.add_parser("export", help="write the editable scripts")
    export.add_argument("--out", default="build/story_doc")
    export.add_argument("--text-only", action="store_true", help="write only the .txt scripts")
    export.set_defaults(func=cmd_export)
    imp = sub.add_parser("import", help="turn returned scripts (.docx or .txt) back into JSON")
    imp.add_argument("files", nargs="+")
    imp.add_argument("--dry-run", action="store_true")
    imp.add_argument("--pending", default="build/story_doc/pending_en.json")
    imp.set_defaults(func=cmd_import)
    sub.add_parser("roundtrip", help="prove export→import changes nothing").set_defaults(func=cmd_roundtrip)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""The read-only half of the story documents: how the plot is arranged.

``tools/story_doc.py`` exports the lines; this module explains when they play. Everything here
is *read* from the repository on every export - the prologue steps, the locations, the router,
the inner-voice rules, who writes and who reads each story flag - so the plot document cannot
drift from the game. None of it is imported back: changing the arrangement is code, and a
writer asks for it with a comment in the document.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
MASTER = "zh-CN"

# What each prologue step is, in the player's terms. The step list itself is read from
# scripts/world/prologue_steps.gd; a step missing here is still listed, just without prose.
STEP_NOTES = {
    "wake": "醒来：从黑场淡入，主角趴在课桌上。目标条显示「先缓一缓」。没有对话。",
    "q_wake": "Q 走过来开口（会话 q_wake）。第一句写入 met_q。Q 描述 B（q_b_looks）后可选「去想象B」"
    "（记 imagine_b_chosen）：Q 说完，想象场景 expected_b 立刻开始。",
    "bag": "翻书包：没有提醒。玩家翻了书包 → Q 问课本（q_after_bag）；"
    "一直没翻 → 计时用完，记 bag_wait_expired，不假装发生过对话。",
    "expectation": "想象 B（expected_b，主观会话，徽章「想象中的」）。B 的四句话各是一个分岔点：正常应对 / 荒诞（装疯）"
    " / 跳出幻想；每个方向 2-4 轮，荒诞方向在「课本呢」之后有一次「臆想」检定。没选「去想象B」就跳过并记"
    " expectation_skipped。",
    "bell": "第二遍铃（bell_moment），目标条「第二遍铃响了」。",
    "substitute": "代课的 N 进门、点名、宣布自习（n_class）。以 class_dismissed 结束，教室门从此可出。"
    "在 q_wake 选了「去隔壁班借」的玩家，下课前可在后门做一次推演检定（classroom_rear_door_borrow），"
    "成功即从后门进走廊、记 skipped_class，算翘课：铃声和 N 的一拍都不再发生。检定只属于主角，Q 不跟随。",
}

OPEN_QUESTIONS = [
    "P0 小试：操场看过交还板（seen:pg_return_board）后，q_ask_along 多一句问话？",
    "P0 主切片：推荐「从消防梯另一侧再看」；备选「楼层表 → 校墙 → 走廊复看」。",
    "P1：回响「借看课本」或「点名」那一刻；六声部的成长与新增文案仍待设计，不为注册而硬加检定。",
    "记忆选择 A/B/C 的对象未定；D 不互斥。",
    "B 还没有正式出场（目前只在想象与他人转述里）。",
]


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def locations() -> dict:
    data = load_json(DATA / "story/locations.json")
    return data.get("locations", data)


def gd_files() -> list[Path]:
    return sorted(p for base in ("scripts", "scenes") for p in (ROOT / base).rglob("*.gd"))


def flag_constants() -> dict[str, str]:
    """``StoryFlags`` constant name → flag string."""
    text = (ROOT / "scripts/narrative/story_flags.gd").read_text(encoding="utf-8")
    return dict(re.findall(r'^const\s+([A-Z_0-9]+)\s*:\s*StringName\s*=\s*&"([^"]+)"', text, re.M))


def strings() -> dict[str, str]:
    return load_json(DATA / "locale" / f"{MASTER}.json")["strings"]


def conversations() -> dict[str, tuple[str, dict]]:
    out = {}
    for path in sorted((DATA / "dialogue" / MASTER).glob("*.json")):
        for conv_id, conv in load_json(path)["conversations"].items():
            out[conv_id] = (path.stem, conv)
    return out


def inspections() -> dict[str, tuple[str, dict]]:
    out = {}
    for path in sorted((DATA / "inspections" / MASTER).glob("*.json")):
        for item_id, item in load_json(path).items():
            if isinstance(item, dict):
                out[item_id] = (path.stem, item)
    return out


def router_rules() -> list[tuple[str, str, str]]:
    """``(route, conversation, requires)`` in priority order, read from the router source."""
    consts = flag_constants()
    text = (ROOT / "scripts/dialogue/conversation_router.gd").read_text(encoding="utf-8")
    body = text.split("const ROUTES", 1)[1].split("\nstatic func", 1)[0]
    rules, route = [], ""
    pending_conv = None
    for line in body.splitlines():
        head = re.match(r'^\t&"(\w+)":', line)
        if head:
            route = head.group(1)
        for kind, value in re.findall(r'"(conversation|requires)":\s*(&"\w+"|\{[^}]*\})', line):
            if kind == "conversation":
                pending_conv = value[2:-1]
            elif pending_conv:
                req = re.sub(r"StoryFlags\.([A-Z_0-9]+)", lambda m: consts.get(m.group(1), m.group(1)), value[1:-1])
                rules.append((route, pending_conv, req.strip() or "无条件"))
                pending_conv = None
    return rules


def scene_uses() -> dict[str, list[str]]:
    """Route or conversation id → the scenes that point at it."""
    uses = defaultdict(list)
    for path in sorted((ROOT / "scenes").rglob("*.tscn")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for key in re.findall(r'(?:conversation_route|conversation_id) = &"(\w+)"', text):
            if path.stem not in uses[key]:
                uses[key].append(path.stem)
    return uses


def code_mentions(ids: set[str]) -> dict[str, list[str]]:
    """Conversation id → ``file · func()`` for every literal mention in GDScript (router excluded)."""
    found = defaultdict(list)
    for path in gd_files():
        # The router has its own section; story_flags / prologue_steps only share spellings
        # (a flag or a step called like the conversation), they never play anything.
        if path.name in ("conversation_router.gd", "story_flags.gd", "prologue_steps.gd"):
            continue
        func = ""
        for line in path.read_text(encoding="utf-8").splitlines():
            head = re.match(r"^(?:static\s+)?func\s+(\w+)", line)
            if head:
                func = head.group(1)
            if re.match(r"^\s*(&\"\w+\",?\s*)+:\s*$", line):
                continue  # a `match` arm on a step name, not a conversation being played
            for name in re.findall(r'&"(\w+)"', line):
                if name in ids:
                    where = f"{path.name}" + (f" · {func}()" if func else "（常量）")
                    if where not in found[name]:
                        found[name].append(where)
    return found


def trigger_notes() -> dict[str, list[str]]:
    """Conversation id → one-line notes on what plays it, for the ``※ 触发`` lines."""
    convs = conversations()
    ids = set(convs)
    notes = defaultdict(list)
    names = strings()
    scenes = scene_uses()
    for route, conv, req in router_rules():
        where = "、".join(scenes.get(route, [])) or "（场景未直接引用）"
        notes[conv].append(f"路由 {route}（场景 {where}）条件：{req}")
    for loc_id, loc in locations().items():
        if loc.get("arrival_conversation") in ids:
            place = names.get(f"place.{loc_id}", loc_id)
            notes[loc["arrival_conversation"]].append(f"首次到达「{place}」时自动播放（写入 {loc.get('arrival_flag', '')}）")
    for rule in load_json(DATA / "abilities/abilities.json").get("passives", []):
        trig = rule["trigger"]
        kind = {"inspection": "检视", "location": "到达地点", "conversation_end": "会话结束"}.get(trig["kind"], trig["kind"])
        notes[rule["conversation"]].append(f"内心声音被动：{kind} {trig['id']} 之后{'（仅一次）' if rule.get('once') else ''}")
    for conv, where in code_mentions(ids).items():
        notes[conv].append("代码编排：" + "；".join(where))
    for conv, where in scenes.items():
        if conv in ids and not any(conv == r[0] for r in router_rules()):
            notes[conv].append("场景直接交互：" + "、".join(where))
    for conv in ids:
        if not notes[conv]:
            notes[conv].append("⚠ 没有任何场景、路由或代码播放这段会话（疑似遗留内容，改它不会出现在游戏里）")
    return notes


def flag_table() -> list[tuple[str, list[str], list[str]]]:
    """``(flag, writers, readers)`` for every flag the content or the code names."""
    writes, reads = defaultdict(list), defaultdict(list)

    def add(table, flag, where):
        if where not in table[flag]:
            table[flag].append(where)

    for conv_id, (_chapter, conv) in conversations().items():
        for node in conv["nodes"]:
            here = f"{conv_id}/{node['id']}"
            for holder in [node, *node.get("choices", [])]:
                tag = here if holder is node else f"{here}◇{holder['id']}"
                for effect in holder.get("effects", []):
                    if effect.get("type") == "set_flag":
                        add(writes, effect["flag"], tag)
                cond = holder.get("conditions", {})
                for flag in [*cond.get("all_flags", []), *cond.get("not_flags", []), *cond.get("requires", {})]:
                    add(reads, flag, tag)
            for mod in node.get("check", {}).get("modifiers", []):
                add(reads, mod["flag"], f"{here}（检定加值）")
    for item_id, (_chapter, item) in inspections().items():
        for effect in item.get("effects", []):
            if effect.get("type") == "set_flag":
                add(writes, effect["flag"], f"检视 {item_id}")
    for route, conv, req in router_rules():
        for flag in re.findall(r"([a-z_0-9:]+)\s*:", req):
            add(reads, flag, f"路由 {route}→{conv}")
    consts = flag_constants()
    for path in gd_files():
        if path.name == "story_flags.gd":
            continue
        text = path.read_text(encoding="utf-8")
        for name in set(re.findall(r"StoryFlags\.([A-Z_0-9]+)", text)):
            flag = consts.get(name)
            if not flag:
                continue
            if re.search(rf"set_flag\(\s*StoryFlags\.{name}\b", text):
                add(writes, flag, f"代码 {path.name}")
            if re.search(rf"(?<!set_flag\()StoryFlags\.{name}\b(?!\s*,\s*(true|false))", text):
                add(reads, flag, f"代码 {path.name}")
    flags = sorted(set(writes) | set(reads))
    return [(flag, writes.get(flag, []), reads.get(flag, [])) for flag in flags if not flag.startswith(("check:", "choice:"))]


def prologue_steps() -> list[str]:
    text = (ROOT / "scripts/world/prologue_steps.gd").read_text(encoding="utf-8")
    block = text.split("const STEPS", 1)[1].split("= [", 1)[1].split("]", 1)[0]
    return re.findall(r'&"(\w+)"', block)


def plot_document(names) -> list[tuple[str, str]]:
    s = strings()
    out = [("title", "剧情安排（本节只读，导入时忽略；末尾「◆ 界面文字」一节可改）")]
    out += [
        ("h1", "※ 一、怎么读、怎么改"),
        ("note", "※ 台本按章节分成多份文档：00 是本页，01–08 是各章对话，最后一份是全部检视文字。完整格式说明见仓库 docs/STORY_DOCS.zh-CN.md。"),
        ("note", "※ 台词行：[节点id] 说话人：文字。说话人可写 你、旁白、Q、N、B、同学、洞察、细察、回声、臆想、推演、共鸣；「旁白」和「你」导入后都是主角（游戏没有独立的旁白角色，第二人称叙述就是旁白）。"),
        ("note", "※ 台词下面的小字是结构：来源、下一句、条件、效果、记录、检定。◇ 开头是玩家选项，选项下面缩进的小字属于这个选项。"),
        ("note", "※ 来源决定徽章：亲眼所见 / 听人说的 / 记忆里的 / 想象中的。「想象中的」永远不会变成世界状态。"),
        ("note", "※ 可以改字、增删台词和选项、改跳转。新台词请起一个新的 [id]（小写字母、数字、下划线），不要复用旧 id。"),
        ("note", "※ 没写「下一句」的台词会接着播下一行；会话最后一句必须写「下一句：结束」。"),
        ("note", "※ 「※」开头的行和 Google 文档批注都不会被导入。想改编排（何时触发、谁在场）请写批注，我改代码。"),
        ("note", "※ 只改中文。英文由导入后统一同步翻译。"),
    ]
    out.append(("h1", "※ 二、序章节拍（按顺序执行，每拍由一个 flag 证明已完成）"))
    for index, step in enumerate(prologue_steps(), 1):
        out.append(("ref", f"{index}. {step}：{STEP_NOTES.get(step, '（无说明）')}"))
    out.append(("h1", "※ 三、地点（17 处）"))
    insp = defaultdict(int)
    for _item, (chapter, _body) in inspections().items():
        insp[chapter] += 1
    for loc_id, loc in locations().items():
        place = s.get(f"place.{loc_id}", "（尚无地名）")
        bits = [f"{place}（{loc_id}）"]
        if loc.get("objective"):
            bits.append(f"目标条 {loc['objective']}「{s.get(loc['objective'], '')}」")
        if loc.get("arrival_conversation"):
            bits.append(f"到达会话 {loc['arrival_conversation']}")
        if loc.get("arrival_flags"):
            bits.append("到达写入 " + "、".join(loc["arrival_flags"]))
        bits.append(f"检视 {insp.get(loc_id, 0)} 处")
        out.append(("ref", "· " + "；".join(bits)))
    out.append(("h1", "※ 四、谁在什么条件下说哪段（路由，自上而下第一条满足者生效）"))
    for route, conv, req in router_rules():
        out.append(("ref", f"· {route} → {conv}：{req}"))
    out.append(("h1", "※ 五、内心声音的被动开口"))
    for rule in load_json(DATA / "abilities/abilities.json").get("passives", []):
        voice = names.ability.get(rule["ability"], rule["ability"])
        out.append(("ref", f"· {voice}：{rule['trigger']['kind']} {rule['trigger']['id']} → {rule['conversation']}{'（仅一次）' if rule.get('once') else ''}"))
    out.append(("ref", "· 已注册六个声音：洞察、细察、回声、臆想、推演、共鸣；数值暂定，共鸣暂无检定文案。"))
    out.append(("h1", "※ 六、剧情 flag：谁写、谁读（「无人读取」= 记下了但还没有回响）"))
    for flag, writers, readers in flag_table():
        reader = "、".join(readers) if readers else "无人读取"
        out.append(("ref", f"· {flag}：写 {('、'.join(writers) or '—')}｜读 {reader}"))
    out.append(("h1", "※ 七、待决的剧情问题（详见 docs/NARRATIVE_GAMEPLAY_REVIEW.zh-CN.md）"))
    out += [("ref", f"· {q}") for q in OPEN_QUESTIONS]
    return out

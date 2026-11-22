#!/usr/bin/env python3
"""Validate a mobile author draft and optionally write review copies, not live game data."""
from __future__ import annotations

import argparse
import difflib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import authoring_build
import export_mobile
import story_doc

ROOT = Path(__file__).resolve().parents[1]


def preserve_source_values(candidate, original):
    """JSON in Godot uses doubles; keep unchanged leaves in their original Python type."""
    if isinstance(candidate, dict) and isinstance(original, dict):
        return {key: preserve_source_values(value, original.get(key)) for key, value in candidate.items()}
    if isinstance(candidate, list) and isinstance(original, list):
        by_id = {item["id"]: item for item in original if isinstance(item, dict) and "id" in item}
        return [preserve_source_values(value,
                                      by_id.get(value["id"]) if isinstance(value, dict) and "id" in value
                                      else original[index] if index < len(original) else None)
                for index, value in enumerate(candidate)]
    return original if candidate == original else candidate


def review(draft: Path, godot: str, output: Path | None) -> None:
    if not draft.is_file() or not 0 < draft.stat().st_size <= 2 * 1024 * 1024:
        raise ValueError("需要一个不超过 2 MiB 的作者版 JSON 草稿。")
    if output:
        if output.is_relative_to(ROOT) and output.relative_to(ROOT).parts[:1] not in (("build",), ("builds",)):
            raise ValueError("请把审阅副本输出到仓库外或 build/、builds/；不会直接写发布数据。")
        if output.exists() and (not output.is_dir() or any(output.iterdir())):
            raise ValueError("审阅输出目录必须为空。")
    expected = (ROOT / ".godot-version").read_text().strip()
    if not export_mobile.run(godot, "--version", capture=True).strip().startswith(expected + ".stable."):
        raise ValueError(f"预检需要 Godot {expected} Stable。")
    with tempfile.TemporaryDirectory(prefix="wis-draft-review-") as temp:
        work = Path(temp)
        tree = work / "project"
        export_mobile.stage(tree, authoring=True)
        authoring_build.configure_project(tree, "review", editor=False)
        project = tree / "project.godot"
        title = authoring_build.AUTHOR_NAME
        project.write_text(project.read_text(encoding="utf-8").replace(f'config/name="{title}"',
                           'config/name="Where Is School - Draft Review"'), encoding="utf-8")
        export_mobile.import_project(godot, tree)
        script = tree / "review_author_draft.gd"
        script.write_bytes((ROOT / "tools/review_author_draft.gd").read_bytes())
        reviewed = work / "review.json"
        export_mobile.run(godot, "--headless", "--path", tree, "--script", script, "--", draft, reviewed)
        result = json.loads(reviewed.read_text(encoding="utf-8"))

    waiting = result["pending_followups"]
    if waiting:
        print(f"占位草稿预检通过：{len(waiting)} 句待补写。补写后重新导出；未生成候选对白。")
        if output:
            output.mkdir(parents=True, exist_ok=True)
            write_list(output / "pending_followups.json", waiting)
        return

    changes = result["chapters"]
    pending: list[dict] = []
    copies: dict[str, str] = {}
    diff: list[str] = []
    for chapter, candidate in changes.items():
        zh_path = story_doc.dialogue_path(story_doc.MASTER, chapter)
        en_path = story_doc.dialogue_path(story_doc.MIRROR, chapter)
        old_zh, old_en = story_doc.load_json(zh_path), story_doc.load_json(en_path)
        candidate = preserve_source_values(candidate, old_zh)
        # Keep the same shape/pending translation workflow as returned story documents.
        changed_en, todo = story_doc.mirror(candidate, old_zh, old_en, story_doc.MIRROR)
        for item in todo:
            item["file"] = str(en_path.relative_to(ROOT))
        pending.extend(todo)
        for path, new in ((zh_path, story_doc.ordered_like(candidate, old_zh)), (en_path, changed_en)):
            relative = path.relative_to(ROOT).as_posix()
            after = story_doc.dump_json(new)
            before = path.read_text(encoding="utf-8")
            if before != after:
                copies[relative] = after
                diff.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True),
                                                 fromfile=f"a/{relative}", tofile=f"b/{relative}"))
    for name in copies:
        print("将变更：", name)
    print(f"预检通过：{len(changes)} 个章节，{len(pending)} 项英文待译；未写入项目。")
    if output:
        output.mkdir(parents=True, exist_ok=True)
        for name, candidate in copies.items():
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(candidate, encoding="utf-8")
        (output / "preview.diff").write_text("".join(diff), encoding="utf-8")
        write_list(output / "pending_en.json", pending)


def write_list(path: Path, items: list[dict]) -> None:
    path.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("draft", type=Path)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, help="Optional empty directory for review copies or a pending follow-up list")
    args = parser.parse_args()
    try:
        review(args.draft.resolve(), args.godot, args.output.resolve() if args.output else None)
        return 0
    except (OSError, ValueError, export_mobile.BuildError, subprocess.SubprocessError) as error:
        print(f"作者草稿未写入项目：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

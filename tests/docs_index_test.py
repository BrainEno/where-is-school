#!/usr/bin/env python3
"""Positive and negative contracts for tools/check_docs_index.py (issue #209).

Fixture trees prove that an unindexed document, stale row, bad status, broken link,
missing ADR row or archived file without a status header cannot silently look current.
The real repository is checked as well. Run with python3 tests/docs_index_test.py.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_docs_index as index  # noqa: E402


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def status_header(title: str) -> str:
    return (
        f"# {title}\n\n"
        "> **状态：** 历史/归档\n"
        "> **最后核对：** 2026-11-17\n"
        "> **负责人：** 文档 Agent\n"
        "> **取代者：** [docs/README.md](../README.md)\n\n"
    )


class DocsIndexTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.write_clean_tree()

    def write_clean_tree(self) -> None:
        write(self.root, "docs/README.md", """# Docs index

> **状态：** 现行
> **最后核对：** 2026-11-17
> **负责人：** 文档 Agent
> **取代者：** [archive/README.md](archive/README.md)

<!-- docs-index:start -->
| 文档 | 用途 | 状态 | 负责人 | 最后核对 | 取代者 / 说明 |
|---|---|---|---|---|---|
| [README.md](README.md) | 本页 | 目录/索引 | 文档 Agent | 2026-11-17 | [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) |
| [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) | 协议 | 现行 | 仓库所有者 | 2026-11-17 | [README.md](README.md) |
| [adr/README.md](adr/README.md) | ADR 索引 | 目录/索引 | 文档 Agent | 2026-11-17 | [README.md](README.md) |
| [adr/0001-test.md](adr/0001-test.md) | ADR 0001 | 现行 | 仓库所有者 | 2026-11-17 | [adr/README.md](adr/README.md) |
| [archive/README.md](archive/README.md) | 归档清单 | 历史/归档 | 文档 Agent | 2026-11-17 | [README.md](README.md) |
| [archive/old.md](archive/old.md) | 旧审计 | 历史/归档 | 文档 Agent | 2026-11-17 | [README.md](README.md) |
<!-- docs-index:end -->
""")
        write(self.root, "docs/AGENT_PROTOCOL.md", "# Protocol\n\nNo links here.\n")
        write(self.root, "docs/adr/README.md", """# ADRs

> **状态：** 目录/索引
> **最后核对：** 2026-11-17
> **负责人：** 文档 Agent
> **取代者：** [docs/README.md](../README.md)

<!-- adr-index:start -->
| 编号 / 记录 | 状态 | 最后核对 | 复核条件 |
|---|---|---|---|
| [0001 — Test](0001-test.md) | 已接受 | 2026-11-17 | 引擎改变时 |
<!-- adr-index:end -->
""")
        write(self.root, "docs/adr/0001-test.md", """# ADR 0001 — Test

- **Status:** Accepted
- **Date:** 2026-11-17
""")
        write(self.root, "docs/archive/README.md", status_header("Archive") + "See [docs/README.md](../README.md).\n")
        write(self.root, "docs/archive/old.md", status_header("Old audit") + "Superseded by [docs/README.md](../README.md).\n")

    def replace(self, relative: str, old: str, new: str) -> None:
        path = self.root / relative
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8")

    def assert_problem(self, message: str) -> None:
        errors = index.check(self.root)
        self.assertTrue(any(message in error for error in errors), errors)

    def test_clean_tree_and_cli_pass(self) -> None:
        self.assertEqual(index.check(self.root), [])
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = index.main(["--check", "--root", str(self.root)])
        self.assertEqual(code, 0)
        self.assertIn("DOCS_INDEX=success", out.getvalue())

    def test_unindexed_document_fails(self) -> None:
        write(self.root, "docs/new.md", "# New\n")
        self.assert_problem("unindexed document docs/new.md")

    def test_stale_index_row_fails(self) -> None:
        write(self.root, "docs/stray.txt", "not a Markdown document\n")
        self.replace("docs/README.md", "[AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) | 协议", "[stray.txt](stray.txt) | 协议")
        self.assert_problem("unindexed document docs/AGENT_PROTOCOL.md")
        self.assert_problem("stale index row docs/stray.txt")

    def test_unknown_status_fails(self) -> None:
        self.replace("docs/README.md", "| [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) | 协议 | 现行 |", "| [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) | 协议 | 随便 |")
        self.assert_problem("unknown status '随便'")

    def test_broken_local_link_fails(self) -> None:
        self.replace("docs/AGENT_PROTOCOL.md", "No links here.", "See [missing.md](missing.md).")
        self.assert_problem("broken local file link: missing.md")

    def test_missing_adr_row_fails(self) -> None:
        write(self.root, "docs/adr/0002-second.md", """# ADR 0002 — Second

- **Status:** Proposed
- **Date:** 2026-11-17
""")
        self.assert_problem("missing ADR row for docs/adr/0002-second.md")

    def test_archive_status_header_is_required(self) -> None:
        write(self.root, "docs/archive/old.md", "# Old audit\n\nNo header.\n")
        self.assert_problem("missing status-header field")

    def test_real_repository_is_clean(self) -> None:
        self.assertEqual(index.check(index.ROOT), [])


if __name__ == "__main__":
    unittest.main()

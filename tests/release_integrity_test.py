#!/usr/bin/env python3
"""Release integrity regressions; synthetic bytes, not playable-build evidence.

Run directly, or through verify_build_test.py (the existing release CI entry).
Each malformed fixture changes one boundary from a complete positive fixture.
No extraction, engine, network, third-party assets or large ZIP bomb is needed.
"""

from __future__ import annotations

import contextlib
import io
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import godot_pck as pck
import release_archive as ra
import verify_build as vb
import verify_build_test as fixtures
from release_pack_fixtures import embed, fields, pack_files


def changed(blob: bytes, offset: int, value: int, width: str = "Q") -> bytes:
    result = bytearray(blob)
    struct.pack_into("<" + width, result, offset, value)
    return bytes(result)


class PackIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.files = [("project.binary", b"actual resource bytes"), ("data/a.json", b"{}")]
        self.pack = pack_files(self.files)

    def refused(self, blob: bytes, pattern: str = ".", *, embedded: bool = False) -> None:
        with self.assertRaisesRegex(pck.PackError, pattern):
            vb.load_blob(blob, embedded)

    def test_complete_format_and_relative_base_matrix(self) -> None:
        prefix = b"MZ" + bytes(126)
        for version in (2, 3, 4):
            for flags in (0, 2):
                for embedded in (False, True):
                    with self.subTest(version=version, flags=flags, embedded=embedded):
                        body = pack_files(self.files, version, flags=flags,
                                          embedded_base=len(prefix) if embedded else 0)
                        blob = embed(body, prefix) if embedded else body
                        entries, header = vb.load_blob(blob, embedded)
                        self.assertEqual(entries, [("res://" + name, len(data)) for name, data in self.files])
                        self.assertEqual(header["engine"], "4.7.2")
                        self.assertEqual(header["version"], version)
                        self.assertEqual(header["relative_offsets"], version >= 3 or bool(flags & 2))

    def test_all_header_truncations_are_pack_errors_not_struct_errors(self) -> None:
        for version, size in ((2, 96), (3, 104), (4, 104)):
            body = pack_files(self.files, version)
            for length in range(size):
                with self.subTest(version=version, length=length):
                    self.refused(body[:length])

    def test_all_directory_truncations_are_refused(self) -> None:
        start = fields(self.pack)["directory"]
        for length in range(start, len(self.pack)):
            with self.subTest(length=length):
                self.refused(self.pack[:length])

    def test_invalid_api_boundaries_do_not_use_negative_slices(self) -> None:
        for base, end in ((-1, None), (len(self.pack) + 1, None), (0, -1),
                          (12, 4), (0, len(self.pack) + 1)):
            with self.subTest(base=base, end=end):
                with self.assertRaises(pck.PackError):
                    vb.read_pack(self.pack, base, end=end)

    def test_directory_must_follow_the_whole_header_and_have_a_count(self) -> None:
        for target in (0, 32, 40, 103, len(self.pack) - 3, len(self.pack) + 1, 2**64 - 1):
            with self.subTest(target=target):
                self.refused(changed(self.pack, 32, target), "directory offset")

    def test_directory_count_has_a_safety_ceiling(self) -> None:
        location = fields(self.pack)["directory"]
        self.refused(changed(self.pack, location, pck.MAX_FILES + 1, "I"), "claims.*files")

    def test_file_base_and_data_offset_are_checked_against_real_bytes(self) -> None:
        row = fields(self.pack)
        for offset in (len(self.pack), 2**64 - 1):
            with self.subTest(offset=offset):
                self.refused(changed(self.pack, row["offset"], offset), "data range")
        self.refused(changed(self.pack, 24, 2**64 - 1), "file base")
        self.refused(changed(self.pack, 24, 0), "data range")

    def test_file_size_cannot_invent_an_absent_payload(self) -> None:
        row = fields(self.pack)
        for size in (len(self.pack) + 1, 2**64 - 1):
            with self.subTest(size=size):
                self.refused(changed(self.pack, row["size"], size), "data range")
        # The old directory-only fixture accepted exactly this absent-data shape.
        header = self.pack[:104]
        directory = self.pack[row["directory"]:]
        self.refused(changed(header + directory, 32, 104))

    def test_data_cannot_point_into_metadata_even_with_a_matching_hash(self) -> None:
        row = fields(self.pack)
        file_base = struct.unpack_from("<Q", self.pack, 24)[0]
        offset = row["directory"] - file_base
        self.refused(changed(self.pack, row["offset"], offset), "overlaps the pack directory")

    def test_changing_one_payload_byte_fails_the_md5(self) -> None:
        blob = bytearray(self.pack)
        blob[struct.unpack_from("<Q", blob, 24)[0]] ^= 1
        self.refused(bytes(blob), "project.binary.*MD5 mismatch")

    def test_changing_one_digest_byte_is_not_ignored(self) -> None:
        blob = bytearray(self.pack)
        blob[fields(self.pack)["digest"]] ^= 1
        self.refused(bytes(blob), "MD5 mismatch")

    def test_zero_length_file_uses_the_real_empty_digest(self) -> None:
        body = pack_files([("empty.txt", b"")])
        self.assertEqual(vb.load_blob(body, False)[0], [("res://empty.txt", 0)])
        blob = bytearray(body)
        digest = fields(body)["digest"]
        blob[digest:digest + 16] = bytes(16)
        self.refused(bytes(blob), "MD5 mismatch")

    def test_encrypted_sparse_and_unknown_pack_flags_fail_closed(self) -> None:
        for flag in (1, 3, 4, 6, 8, 0x80000000):
            with self.subTest(flag=flag):
                self.refused(changed(self.pack, 20, flag, "I"), "unsupported pack flags")

    def test_encrypted_removal_delta_and_unknown_file_flags_are_not_plain_files(self) -> None:
        for flag in (1, 2, 4, 7, 8, 0x80000000):
            with self.subTest(flag=flag):
                self.refused(changed(self.pack, fields(self.pack)["flags"], flag, "I"),
                             "unsupported file flags")

    def test_unsafe_resource_spellings_cannot_bypass_prefix_rules(self) -> None:
        for name in ("/tests/private.gd", "../tests/private.gd", "assets/../tests/private.gd",
                     "assets/./a", "assets//a", "assets/", "res://tests/a", "C:/tests/a",
                     "tests\\private.gd", "data/a\n.json", "data/a\x7f.json", ""):
            with self.subTest(name=name):
                self.refused(pack_files([(name, b"payload")]))

    def test_utf8_and_nul_are_validated_instead_of_replaced(self) -> None:
        for name in (b"data/\xff.json", b"data/a\0hidden", b"\0\0\0\0"):
            with self.subTest(name=name):
                self.refused(pack_files([(name, b"payload")]), "UTF-8|NUL")

    def test_path_lengths_are_bounded_and_four_byte_padded(self) -> None:
        for length in (0, 1, 3, pck.MAX_PATH_BYTES + 4, 2**32 - 1):
            with self.subTest(length=length):
                self.refused(changed(self.pack, fields(self.pack)["length"], length, "I"),
                             "padded path length")

    def test_duplicate_and_unicode_equivalent_resource_paths_are_refused(self) -> None:
        for names in (("same", "same"), ("data/café", "data/cafe\u0301")):
            with self.subTest(names=names):
                self.refused(pack_files([(name, b"payload") for name in names]), "repeats a resource path")

    def test_legitimate_unicode_and_imported_paths_keep_their_bytes(self) -> None:
        files = [("data/zh-CN/课间.json", b"{}"),
                 (".godot/exported/ab/export-text.ttf-012.fontdata", b"font fixture")]
        entries, _ = vb.load_blob(pack_files(files), False)
        self.assertEqual(entries, [("res://" + name, len(data)) for name, data in files])

    def test_partial_data_overlap_is_not_a_complete_file_allocation(self) -> None:
        body = pack_files([("one", b"a" * 64), ("two", b"a" * 64)])
        self.refused(changed(body, fields(body, 1)["offset"], 32), "partially overlaps")

    def test_exact_shared_payload_with_equal_digest_is_safe(self) -> None:
        body = pack_files([("one", b"a" * 64), ("two", b"a" * 64)])
        body = changed(body, fields(body, 1)["offset"], 0)
        self.assertEqual(vb.load_blob(body, False)[0], [("res://one", 64), ("res://two", 64)])

    def test_footer_selects_the_real_pack_not_a_valid_pack_in_a_resource(self) -> None:
        nested = pack_files([("fake.json", b"decoy")])
        outer = pack_files([("actual.bin", nested)])
        entries, _ = vb.load_blob(embed(outer), True)
        self.assertEqual(entries, [("res://actual.bin", len(nested))])
        self.refused(embed(changed(outer, 4, 99, "I")), "unsupported pack format", embedded=True)

    def test_corrupt_outer_payload_cannot_fall_back_to_the_intact_nested_pack(self) -> None:
        nested = pack_files([("fake.json", b"decoy")])
        outer = bytearray(pack_files([("actual.bin", b"x" + nested)]))
        outer[struct.unpack_from("<Q", outer, 24)[0]] ^= 1
        self.refused(embed(bytes(outer)), "actual.bin.*MD5 mismatch", embedded=True)

    def test_payload_cannot_read_bytes_from_the_embedded_footer(self) -> None:
        footer = len(self.pack)
        file_base = struct.unpack_from("<Q", self.pack, 24)[0]
        body = changed(self.pack, fields(self.pack)["offset"], footer - file_base)
        self.refused(embed(body), "data range", embedded=True)

    def test_missing_or_impossible_footer_is_not_a_magic_scan(self) -> None:
        good = embed(self.pack)
        for blob in (b"", self.pack, good[:-1], good + b"wrapped",
                     changed(good, len(good) - 12, 0),
                     changed(good, len(good) - 12, 2**64 - 1)):
            with self.subTest(size=len(blob)):
                self.refused(blob, "footer", embedded=True)


class ArchiveIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stem = "where-is-school-0.1.0-windows"

    def package(self, extras: dict[str, bytes] | None = None, *, platform: str = "windows") -> Path:
        self.stem = f"where-is-school-0.1.0-{platform}"
        factory = fixtures.windows_files if platform == "windows" else fixtures.linux_files
        return fixtures.make_package(self.root, self.stem, factory() | fixtures.LICENCES | (extras or {}),
                                     modes={"where-is-school": 0o755})

    def verdict(self, path: Path) -> list[str]:
        return vb.inspect_package(path, "0.1.0").problems

    def assert_problem(self, path: Path, needle: str) -> None:
        problems = self.verdict(path)
        self.assertTrue(any(needle in problem for problem in problems), problems)

    def append(self, path: Path, name: str, payload: bytes = b"fixture", *, mode: int = 0o644) -> None:
        info = zipfile.ZipInfo(f"{self.stem}/{name}")
        info.create_system = 3
        info.external_attr = mode << 16
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)  # expected duplicate-fixture warning only
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr(info, payload)

    def central_offset(self, blob: bytes, name: str) -> int:
        cursor = 0
        wanted = f"{self.stem}/{name}".encode()
        while (cursor := blob.find(b"PK\x01\x02", cursor)) >= 0:
            length = struct.unpack_from("<H", blob, cursor + 28)[0]
            if blob[cursor + 46:cursor + 46 + length] == wanted:
                return cursor
            cursor += 4
        self.fail(f"central-directory fixture member missing: {name}")

    def test_complete_both_platforms_and_explicit_directories_still_pass(self) -> None:
        for platform in ("windows", "linux"):
            with self.subTest(platform=platform):
                path = self.package(platform=platform)
                self.append(path, "licences/", b"", mode=stat.S_IFDIR | 0o755)
                self.assertEqual(self.verdict(path), [])

    def test_stored_and_deflated_members_both_pass(self) -> None:
        for method in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            path = self.package()
            info = zipfile.ZipInfo(f"{self.stem}/extra.txt")
            info.compress_type = method
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr(info, b"synthetic text" * 20)
            self.assertEqual(self.verdict(path), [])

    def test_duplicate_executable_licence_and_directory_are_not_collapsed(self) -> None:
        for name, data in (("where-is-school.exe", fixtures.windows_files()["where-is-school.exe"]),
                           ("licences/COPYRIGHT.md", b"different text"), ("extra/", b"")):
            with self.subTest(name=name):
                path = self.package()
                if name.endswith("/"):
                    self.append(path, name, b"")
                self.append(path, name, data)
                self.assert_problem(path, "duplicate or aliased")

    def test_case_and_unicode_equivalent_names_have_one_extraction_identity(self) -> None:
        for names in (("LICENCES/copyright.md",), ("notes/café.txt", "notes/cafe\u0301.txt"),
                      ("extras/A.txt", "extras/a.txt")):
            with self.subTest(names=names):
                path = self.package(dict.fromkeys(names, b"fixture"))
                self.assert_problem(path, "duplicate or aliased")

    def test_windows_path_aliases_and_escape_spellings_are_refused(self) -> None:
        for name in ("../escape", "sub/../escape", "/absolute", "C:/absolute", "sub\\escape",
                     "docs\\private.txt", "double//slash", "sub/./dot", "trailing.", "space ",
                     "NUL", "nul.txt", "aux.txt", "COM1.log", "LPT9", "COM¹.txt",
                     "notes.txt:stream", "what?.txt", "tab\t.txt", 'quote".txt'):
            with self.subTest(name=name):
                self.assert_problem(self.package({name: b"fixture"}), "unsafe archive path")

    def test_raw_nul_name_is_checked_before_zipinfo_truncates_it(self) -> None:
        path = self.package({"nulX.txt": b"fixture"})
        blob = path.read_bytes().replace(b"nulX.txt", b"nul\0.txt")
        path.write_bytes(blob)
        self.assert_problem(path, "embedded NUL")

    def test_invalid_utf8_in_either_zip_header_is_a_readable_cli_refusal(self) -> None:
        for central in (True, False):
            with self.subTest(header="central" if central else "local"):
                path = self.package({"extra.txt": b"fixture"})
                with zipfile.ZipFile(path) as archive:
                    info = archive.getinfo(f"{self.stem}/extra.txt")
                blob = bytearray(path.read_bytes())
                if central:
                    offset = self.central_offset(blob, "extra.txt")
                    flags_at, name_at = offset + 8, offset + 46
                    diagnostic = "not a readable zip"
                else:
                    offset = info.header_offset
                    flags_at, name_at = offset + 6, offset + 30
                    diagnostic = "unreadable archive member"
                flags = struct.unpack_from("<H", blob, flags_at)[0]
                struct.pack_into("<H", blob, flags_at, flags | 0x800)
                blob[name_at + len(info.filename.encode("utf-8")) - 1] = 0xFF
                path.write_bytes(blob)
                stdout, stderr = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    code = vb.main(["--package", str(path), "--expect-version", "0.1.0"])
                self.assertEqual(code, 1)
                self.assertIn(diagnostic, stderr.getvalue())
                self.assertNotIn("PASS:", stdout.getvalue())
                self.assertNotIn("Traceback", stdout.getvalue() + stderr.getvalue())

    def test_file_cannot_also_be_an_implicit_or_explicit_parent_directory(self) -> None:
        for extras in ({"extra": b"file", "extra/child": b"child"},
                       {"EXTRA": b"file", "extra/child": b"child"},
                       {"extra": b"file", "extra/": b""}):
            with self.subTest(extras=list(extras)):
                self.assertTrue(self.verdict(self.package(extras)))

    def test_symlinks_sockets_and_devices_are_not_regular_package_files(self) -> None:
        for kind in (stat.S_IFLNK, stat.S_IFSOCK, stat.S_IFCHR, stat.S_IFIFO, stat.S_IFBLK):
            with self.subTest(kind=kind):
                path = self.package()
                self.append(path, "extra", mode=kind | 0o755)
                self.assert_problem(path, "special file or symbolic link")

    def test_directory_type_and_spelling_must_agree_and_carry_no_data(self) -> None:
        for name, payload, mode in (("extra", b"", stat.S_IFDIR | 0o755),
                                    ("extra/", b"", stat.S_IFREG | 0o644),
                                    ("extra/", b"not empty", stat.S_IFDIR | 0o755)):
            with self.subTest(name=name, mode=mode):
                path = self.package()
                self.append(path, name, payload, mode=mode)
                self.assertTrue(self.verdict(path))

    def test_case_variant_development_folders_and_suffixes_are_still_forbidden(self) -> None:
        for name in ("DOCS/private.txt", "TOOLS/build.py", "export.LOG", "other.PCK", ".ds_store"):
            with self.subTest(name=name):
                self.assertTrue(self.verdict(self.package({name: b"fixture"})))

    def test_nearby_but_distinct_file_names_are_not_over_rejected(self) -> None:
        extras = {"documentation/readme.txt": b"notes", "auxiliary.txt": b"notes",
                  "CONSOLE.txt": b"notes", "notes/课间.txt": b"notes"}
        self.assertEqual(self.verdict(self.package(extras)), [])

    def test_crc_of_an_otherwise_unused_licence_is_checked(self) -> None:
        path = self.package()
        with zipfile.ZipFile(path) as archive:
            info = archive.getinfo(f"{self.stem}/licences/COPYRIGHT.md")
        blob = bytearray(path.read_bytes())
        name_size, extra_size = struct.unpack_from("<HH", blob, info.header_offset + 26)
        data = info.header_offset + 30 + name_size + extra_size
        blob[data] ^= 1
        path.write_bytes(blob)
        self.assert_problem(path, "unreadable archive member")

    def test_corrupt_deflate_returns_a_diagnostic_not_an_exception(self) -> None:
        path = self.package()
        info = zipfile.ZipInfo(f"{self.stem}/unused.txt")
        info.compress_type = zipfile.ZIP_DEFLATED
        with zipfile.ZipFile(path, "a") as archive:
            archive.writestr(info, b"repeated fixture bytes" * 100)
        with zipfile.ZipFile(path) as archive:
            info = archive.getinfo(info.filename)
        blob = bytearray(path.read_bytes())
        length, extra = struct.unpack_from("<HH", blob, info.header_offset + 26)
        blob[info.header_offset + 30 + length + extra] = 0xFF
        path.write_bytes(blob)
        self.assert_problem(path, "unreadable archive member")

    def test_local_header_must_name_the_same_member_as_the_directory(self) -> None:
        path = self.package({"unused.txt": b"fixture"})
        with zipfile.ZipFile(path) as archive:
            offset = archive.getinfo(f"{self.stem}/unused.txt").header_offset
        blob = bytearray(path.read_bytes())
        blob[offset + 30] ^= 1
        path.write_bytes(blob)
        self.assert_problem(path, "unreadable archive member")

    def test_encryption_and_unknown_compression_are_rejected_before_open(self) -> None:
        for field, value, needle in ((8, 1, "encrypted ZIP"), (10, 99, "compression method")):
            with self.subTest(field=field):
                path = self.package()
                blob = path.read_bytes()
                offset = self.central_offset(blob, "HOW-TO-RUN.txt")
                path.write_bytes(changed(blob, offset + field, value, "H"))
                with mock.patch.object(zipfile.ZipFile, "open", side_effect=AssertionError("unsafe read")):
                    self.assert_problem(path, needle)

    def test_expanded_member_and_total_limits_precede_allocation(self) -> None:
        for total in (False, True):
            with self.subTest(total=total):
                path = self.package()
                blob = path.read_bytes()
                names = ("where-is-school.exe", "HOW-TO-RUN.txt") if total else ("where-is-school.exe",)
                for name in names:
                    offset = self.central_offset(blob, name)
                    size = ra.MAX_MEMBER_BYTES if total else ra.MAX_MEMBER_BYTES + 1
                    blob = changed(blob, offset + 24, size, "I")
                path.write_bytes(blob)
                with mock.patch.object(zipfile.ZipFile, "open", side_effect=AssertionError("unsafe read")):
                    self.assert_problem(path, "safety limit")

    def test_count_limit_and_empty_archive_are_reported(self) -> None:
        path = self.package()
        with mock.patch.object(ra, "MAX_MEMBERS", 2):
            self.assert_problem(path, "members (safety limit")
        with zipfile.ZipFile(path, "w"):
            pass
        self.assert_problem(path, "is empty")

    def test_linux_notes_cannot_be_replaced_by_windows_only_notes(self) -> None:
        path = self.package({"README.txt": fixtures.NOTES.replace(b"./where-is-school", b"game.exe")},
                            platform="linux")
        self.assert_problem(path, "README.txt has no Linux launch command")


class ArchiveBoundaryTests(unittest.TestCase):
    def test_member_size_limit_includes_the_boundary_but_not_one_byte_over(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = fixtures.make_package(Path(directory), "where-is-school-0.1.0-windows",
                                         {"one": b"x"})
            with zipfile.ZipFile(path) as archive:
                info = archive.infolist()[0]
                for size in (0, ra.MAX_MEMBER_BYTES):
                    with self.subTest(size=size):
                        info.file_size = size
                        self.assertEqual(ra.check_directory(archive), [])
                info.file_size = ra.MAX_MEMBER_BYTES + 1
                self.assertTrue(any("member safety limit" in p for p in ra.check_directory(archive)))

    def test_total_size_limit_includes_the_boundary_without_allocating_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = fixtures.make_package(Path(directory), "where-is-school-0.1.0-windows",
                                         {"one": b"x", "two": b"y"})
            with zipfile.ZipFile(path) as archive:
                first, second = archive.infolist()
                first.file_size = ra.MAX_MEMBER_BYTES
                second.file_size = ra.MAX_TOTAL_BYTES - ra.MAX_MEMBER_BYTES
                self.assertEqual(ra.check_directory(archive), [])
                second.file_size += 1
                self.assertTrue(any("archive expands" in p for p in ra.check_directory(archive)))

    def test_each_zip_read_failure_becomes_an_actionable_verdict(self) -> None:
        errors = (OSError("disk read failed"), EOFError("short input"),
                  RuntimeError("encrypted"), NotImplementedError("compression"),
                  zipfile.BadZipFile("CRC"), ra.zlib.error("deflate"))
        with tempfile.TemporaryDirectory() as directory:
            path = fixtures.make_package(Path(directory), "where-is-school-0.1.0-windows",
                                         fixtures.windows_files() | fixtures.LICENCES)
            for error in errors:
                with self.subTest(error=type(error).__name__), zipfile.ZipFile(path) as archive:
                    with mock.patch.object(archive, "open", side_effect=error):
                        problems = ra.check_data(archive)
                    self.assertEqual(len(problems), 1)
                    self.assertIn("unreadable archive member", problems[0])
                    self.assertIn(str(error), problems[0])

    def test_streaming_limit_is_enforced_independently_of_central_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = fixtures.make_package(Path(directory), "where-is-school-0.1.0-windows",
                                         {"small": b"x"})
            with zipfile.ZipFile(path) as archive:
                with mock.patch.object(archive, "open", return_value=io.BytesIO(b"x" * 33)):
                    with mock.patch.object(ra, "MAX_MEMBER_BYTES", 32):
                        problems = ra.check_data(archive)
                self.assertTrue(any("expanded data exceeds" in p for p in problems))
                with mock.patch.object(archive, "open", return_value=io.BytesIO(b"")):
                    problems = ra.check_data(archive)
                self.assertTrue(any("differs from declared" in p for p in problems))

    def test_truncated_zip_directory_is_a_reported_package_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = fixtures.make_package(Path(directory), "where-is-school-0.1.0-windows",
                                         fixtures.windows_files() | fixtures.LICENCES)
            original = path.read_bytes()
            for cut in (1, 12, 22, len(original)):
                with self.subTest(cut=cut):
                    path.write_bytes(original[:-cut])
                    result = vb.inspect_package(path, "0.1.0")
                    self.assertTrue(any("not a readable zip" in p for p in result.problems))


class ReleaseEntryPointTests(unittest.TestCase):
    def test_pack_engine_must_match_the_single_project_pin(self) -> None:
        expected = (ROOT / ".godot-version").read_text().strip()
        entries = fixtures.game_entries()
        self.assertEqual(vb.verify(entries, {"engine": expected})[0], [])
        for engine in (None, "99.0.0", "4.7.1", "4.7.2.dev", ""):
            with self.subTest(engine=engine):
                problems, _ = vb.verify(entries, {"engine": engine})
                self.assertTrue(any("this project requires" in p for p in problems))
                self.assertTrue(any(".godot-version" in p for p in problems))

    def test_missing_engine_pin_is_a_refusal_not_an_assumed_version(self) -> None:
        with mock.patch.object(Path, "read_text", side_effect=OSError("missing version pin")):
            problems, _ = vb.verify(fixtures.game_entries(), {"engine": "4.7.2"})
        self.assertTrue(any("cannot read the project's Godot version pin" in p for p in problems))

    def test_cli_rejects_an_intact_pack_from_the_wrong_engine(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "foreign.pck"
            resources = [(name.removeprefix("res://"), b"x" * size)
                         for name, size in fixtures.game_entries()]
            path.write_bytes(changed(pack_files(resources), 8, 99, "I"))
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = vb.main(["--pck", str(path)])
            self.assertEqual(code, 1)
            self.assertIn("this project requires", stderr.getvalue())
            self.assertNotIn("PASS:", stdout.getvalue())

    def test_cli_checks_payload_digest_before_declaring_a_pack_successful(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "damaged.pck"
            resources = [(name.removeprefix("res://"), b"x" * size)
                         for name, size in fixtures.game_entries()]
            blob = bytearray(pack_files(resources))
            blob[struct.unpack_from("<Q", blob, 24)[0]] ^= 1
            path.write_bytes(blob)
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = vb.main(["--pck", str(path)])
            self.assertEqual(code, 1)
            self.assertIn("MD5 mismatch", stderr.getvalue())
            self.assertNotIn("PASS:", stdout.getvalue())

    def test_real_shipped_notes_and_support_status_are_explicit(self) -> None:
        for path in (ROOT / "packaging/HOW-TO-RUN.txt", ROOT / "packaging/linux/README.txt"):
            with self.subTest(path=path.name):
                text = path.read_text()
                self.assertIn("./where-is-school", text)
                self.assertIn("experimental", text.lower())
                self.assertIn("unverified", text.lower())
                for filename in ("save.json", "settings.cfg", "logs/"):
                    self.assertIn(filename, text)
                self.assertNotIn("gamepad is not mapped", text)
                self.assertNotIn("glibc 2.31", text)
        linux = (ROOT / "packaging/linux/README.txt").read_text()
        self.assertNotIn("cp where-is-school.desktop ~/.local/share/applications/", linux)
        self.assertIn("%k", linux)

    def test_ci_entry_point_runs_this_suite_and_watches_its_dependencies(self) -> None:
        entry = (ROOT / "tests/verify_build_test.py").read_text()
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        self.assertIn('with_name("release_integrity_test.py")', entry)
        for relative in ("tools/godot_pck.py", "tools/release_archive.py", "tests/release_integrity_test.py",
                         "tests/release_pack_fixtures.py"):
            self.assertIn(f'"{relative}"', workflow)

    def test_cli_returns_one_not_a_traceback_for_truncated_pack(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "broken.pck"
            path.write_bytes(b"GDPC" + struct.pack("<IIIIIQ", 4, 4, 7, 2, 2, 0))
            result = subprocess.run([sys.executable, str(ROOT / "tools/verify_build.py"), "--pck", str(path)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("FAIL:", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_complete_package_and_embedded_pack_follow_the_whole_cli(self) -> None:
        for platform in ("windows", "linux"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                files = fixtures.windows_files() if platform == "windows" else fixtures.linux_files()
                executable = vb.PACKAGE_EXECUTABLE[platform]
                # This is plausible-size synthetic metadata, NOT a runnable engine.
                prefix = files[executable].ljust(10 * vb.MiB, b"\0")
                resources = [(name.removeprefix("res://"), b"x" * size)
                             for name, size in fixtures.game_entries()]
                files[executable] = embed(pack_files(resources), prefix)
                path = fixtures.make_package(Path(directory), f"where-is-school-0.1.0-{platform}",
                                             files | fixtures.LICENCES, modes={"where-is-school": 0o755})
                stdout, stderr = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    code = vb.main(["--package", str(path), "--expect-version", "0.1.0"])
                self.assertEqual(code, 0, stderr.getvalue())
                self.assertIn("PASS:", stdout.getvalue())
                self.assertIn("pack format 4", stdout.getvalue())

    def test_cli_reports_crc_failure_without_reading_a_fake_executable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            files = fixtures.windows_files() | fixtures.LICENCES
            path = fixtures.make_package(Path(directory), "where-is-school-0.1.0-windows", files)
            with zipfile.ZipFile(path) as archive:
                info = archive.getinfo("where-is-school-0.1.0-windows/licences/COPYRIGHT.md")
            blob = bytearray(path.read_bytes())
            length, extra = struct.unpack_from("<HH", blob, info.header_offset + 26)
            blob[info.header_offset + 30 + length + extra] ^= 1
            path.write_bytes(blob)
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = vb.main(["--package", str(path), "--expect-version", "0.1.0"])
            self.assertEqual(code, 1)
            self.assertIn("package layout", stdout.getvalue())
            self.assertIn("unreadable archive member", stderr.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)

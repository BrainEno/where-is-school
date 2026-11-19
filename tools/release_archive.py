"""Bounded, extraction-free ZIP checks shared by the release artifact verifier.

Check the full central directory before making a filename dictionary or reading
members. A package must have one unambiguous extraction on both supported OSes;
ZIP permits duplicates, symlinks and Windows aliases that a dict conceals.
"""

from __future__ import annotations

import stat
import unicodedata
import zipfile
import zlib

# These are parser safety limits, not replacements for verify_build's stricter
# per-resource PCK budgets. The executable already has a 150 MiB release ceiling.
MAX_MEMBERS = 2048
MAX_MEMBER_BYTES = 150 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
READ_CHUNK = 64 * 1024
SUPPORTED_COMPRESSION = (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)
READ_ERRORS = (OSError, EOFError, UnicodeError, RuntimeError, NotImplementedError, zipfile.BadZipFile, zlib.error)
WINDOWS_PUNCTUATION = frozenset('<>:"\\|?*')
WINDOWS_DEVICES = frozenset(
    ("CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$")
    + tuple(prefix + suffix for prefix in ("COM", "LPT") for suffix in "123456789¹²³")
)


def _name_problem(name: str) -> str:
    if not name or name.startswith("/"):
        return "empty or absolute path"
    if "\0" in name:
        return "embedded NUL in path"
    # A final slash denotes an explicit directory. No other empty component or
    # alternate separator is accepted; do not normalize an unsafe name into safety.
    path = name[:-1] if name.endswith("/") else name
    for part in path.split("/"):
        if part in ("", ".", ".."):
            return "empty, dot or escaping path component"
        if any(char in WINDOWS_PUNCTUATION or ord(char) < 32 or ord(char) == 127 for char in part):
            return "non-portable Windows path character or control byte"
        if part.endswith((".", " ")):
            return "Windows-aliased trailing dot or space"
        # Device names remain reserved with an extension, e.g. NUL.txt.
        if part.split(".", 1)[0].upper() in WINDOWS_DEVICES:
            return "reserved Windows device name"
    return ""


def _identity(name: str) -> str:
    return unicodedata.normalize("NFC", name.rstrip("/")).casefold()


def check_directory(archive: zipfile.ZipFile) -> list[str]:
    """Reject ambiguous names/types/oversized headers before touching member data."""
    infos = archive.infolist()
    if len(infos) > MAX_MEMBERS:
        return [f"archive has {len(infos)} members (safety limit {MAX_MEMBERS})"]
    problems: list[str] = []
    entries: dict[str, tuple[str, bool]] = {}
    total = 0
    for info in infos:
        # ZipInfo.filename truncates at a NUL. orig_filename is the central
        # directory's original string and is the one that must be audited.
        name = info.orig_filename
        problem = _name_problem(name)
        if problem:
            problems.append(f"unsafe archive path {name!r}: {problem}")
            continue
        identity = _identity(name)
        directory = info.is_dir()
        if identity in entries:
            problems.append(f"duplicate or aliased archive path {name!r} conflicts with {entries[identity][0]!r}")
        else:
            entries[identity] = (name, directory)
        mode = info.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
            problems.append(f"{name!r}: special file or symbolic link is not a release member")
        elif (kind == stat.S_IFDIR and not directory) or (kind == stat.S_IFREG and directory):
            problems.append(f"{name!r}: file type disagrees with its directory spelling")
        if info.flag_bits & (1 | 0x40):
            problems.append(f"{name!r}: encrypted ZIP members cannot be verified")
        if info.compress_type not in SUPPORTED_COMPRESSION:
            problems.append(f"{name!r}: unsupported ZIP compression method {info.compress_type}")
        if directory and info.file_size:
            problems.append(f"{name!r}: a directory entry carries file data")
        if not 0 <= info.file_size <= MAX_MEMBER_BYTES:
            problems.append(f"{name!r}: expanded size {info.file_size} exceeds the member safety limit {MAX_MEMBER_BYTES}")
        if info.compress_size < 0:
            problems.append(f"{name!r}: negative compressed size")
        total += info.file_size
    if total > MAX_TOTAL_BYTES:
        problems.append(f"archive expands to {total} bytes (safety limit {MAX_TOTAL_BYTES})")
    for identity, (name, _directory) in entries.items():
        parts = identity.split("/")
        for length in range(1, len(parts)):
            parent = "/".join(parts[:length])
            if parent in entries and not entries[parent][1]:
                problems.append(f"{name!r}: parent {entries[parent][0]!r} is a file, not a directory")
                break
    return problems


def check_data(archive: zipfile.ZipFile) -> list[str]:
    """Stream every member to EOF so zipfile verifies its CRC and local header.

    Called only after check_directory succeeds. No extraction, no archive-sized
    allocation, no skipped licence/icon/extra members just because the CLI does
    not otherwise need to read them. The streaming limits also defend against
    local data that disagrees with its central-directory size.
    """
    total = 0
    for info in archive.infolist():
        size = 0
        try:
            with archive.open(info) as member:
                while True:
                    block = member.read(READ_CHUNK)
                    if not block:
                        break
                    size += len(block)
                    total += len(block)
                    if size > MAX_MEMBER_BYTES or total > MAX_TOTAL_BYTES:
                        return [f"{info.filename!r}: expanded data exceeds the archive safety limit"]
            if size != info.file_size:
                return [f"{info.filename!r}: expanded size {size} differs from declared {info.file_size}"]
        except READ_ERRORS as error:
            return [f"{info.filename!r}: unreadable archive member: {error}"]
    return []


def audit(archive: zipfile.ZipFile) -> list[str]:
    """The order matters: reject dangerous metadata before decompressing anything."""
    problems = check_directory(archive)
    return problems if problems else check_data(archive)

#!/usr/bin/env python3
"""Deliver one verified IPA with a signed, encrypted, short-lived transfer ticket."""

from __future__ import annotations

import argparse
import base64
import binascii
from hashlib import file_digest
import http.client
import json
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlsplit
from zipfile import ZipFile

CHUNK_SIZE = 256 * 1024


def openssl(*args: str | Path) -> subprocess.CompletedProcess:
    return subprocess.run(["openssl", *args], capture_output=True, check=False)


def decrypt(folder: Path, source: str, dest: str, cert: str, key: str) -> None:
    result = openssl("cms", "-decrypt", "-binary", "-inform", "DER", "-in", folder / source,
                     "-recip", folder / cert, "-inkey", folder / key, "-out", folder / dest)
    if result.returncode:
        raise SystemExit("Encrypted delivery content could not be decrypted")


def receive(folder: Path) -> None:
    """Only the holder of the transport signing key can select the Drive session."""
    verify_key = Path(__file__).with_name("livecontainer_delivery_public.pem")
    row = f"wis-ipa-delivery-v1 {os.environ['GITHUB_RUN_ID']} {os.environ['GITHUB_RUN_ATTEMPT']}"
    target = f"repos/{os.environ['GITHUB_REPOSITORY']}/commits/{os.environ['GITHUB_SHA']}/comments?per_page=100"
    end = time.monotonic() + 480
    while time.monotonic() < end:
        query = subprocess.run(["gh", "api", "-X", "GET", target], capture_output=True, timeout=20, check=False)
        if query.returncode == 0:
            for candidate in json.loads(query.stdout):
                lines = candidate.get("body", "").splitlines()
                if len(lines) != 3 or lines[0] != row or len(lines[1]) > 16_000 or len(lines[2]) > 512:
                    continue
                try:
                    (folder / "ticket.cms").write_bytes(base64.b64decode(lines[1], validate=True))
                    (folder / "ticket.sig").write_bytes(base64.b64decode(lines[2], validate=True))
                except binascii.Error:
                    continue
                result = openssl("dgst", "-sha256", "-verify", verify_key,
                                 "-signature", folder / "ticket.sig", folder / "ticket.cms")
                if result.returncode == 0:
                    decrypt(folder, "ticket.cms", "ticket.json", "job.pem", "job.key")
                    print("Verified encrypted one-file delivery ticket")
                    return
        time.sleep(4)
    raise SystemExit("No authorized one-file delivery ticket arrived")


def stream_to_drive(ipa: Path, uri: str) -> None:
    session = urlsplit(uri)
    if (session.scheme, session.netloc, session.path) != (
        "https", "www.googleapis.com", "/upload/drive/v3/files",
    ) or not session.query:
        raise SystemExit("Missing authorized Google Drive upload session")
    destination = session.path + "?" + session.query
    total = ipa.stat().st_size
    connection = http.client.HTTPSConnection(session.netloc, timeout=45)
    try:
        with ipa.open("rb") as stream:
            offset = 0
            while offset < total:
                block = stream.read(CHUNK_SIZE)
                end = offset + len(block)
                if end == offset:
                    raise SystemExit("IPA ended before its declared size")
                connection.request("PUT", destination, body=block, headers={
                    "Content-Type": "application/octet-stream",
                    "Content-Length": str(len(block)),
                    "Content-Range": f"bytes {offset}-{end - 1}/{total}",
                    "X-Goog-Upload-Offset": str(offset),
                    "X-Goog-Upload-Total-Size": str(total),
                    "X-Goog-Upload-Command": "upload, finalize" if end == total else "upload",
                })
                response = connection.getresponse()
                body = response.read()
                state = response.getheader("X-Goog-Upload-Status")
                if state is None:
                    state = {308: "active", 200: "final", 201: "final"}.get(response.status)
                if state == "active" and response.status < 400:
                    received = response.getheader("X-Goog-Upload-Size-Received")
                    confirmed = response.getheader("Range")
                    match = re.fullmatch(r"bytes=0-(\d+)", confirmed or "")
                    if ((received is not None and received != str(end))
                            or (confirmed is not None and (match is None or int(match[1]) + 1 != end))
                            or end == total):
                        raise SystemExit("Google Drive did not acknowledge the uploaded chunk")
                    offset = end
                    continue
                if state == "final" and 200 <= response.status < 300 and end == total:
                    item = json.loads(body)
                    if item.get("name") != ipa.name or not item.get("id"):
                        raise SystemExit("Drive did not confirm the expected file")
                    print(f"Google Drive accepted {total} bytes for {ipa.name}")
                    return
                raise SystemExit(f"Drive upload refused at byte {offset} (HTTP {response.status})")
    except (OSError, ValueError, http.client.HTTPException):
        raise SystemExit("Drive upload interrupted or returned invalid metadata") from None
    finally:
        connection.close()
    raise SystemExit("Drive upload never finalized")


def upload(folder: Path) -> None:
    ticket_path = folder / "ticket.json"
    ticket = json.loads(ticket_path.read_text())
    ticket_path.unlink()
    (folder / "archive.pem").write_text(ticket["archive_cert"])
    (folder / "archive.key").write_text(ticket["archive_key"])
    ipa = folder / os.environ["IPA_NAME"]
    try:
        decrypt(folder, "ios-device.cms", ipa.name, "archive.pem", "archive.key")
    finally:
        (folder / "archive.key").unlink()
    with ipa.open("rb") as blob:
        digest = file_digest(blob, "sha256").hexdigest()
    if digest != os.environ["IPA_SHA256"] or ipa.stat().st_size != int(os.environ["IPA_BYTES"]):
        raise SystemExit("Decrypted IPA does not match the macOS-verified build")
    with ZipFile(ipa) as zipped:
        if zipped.testzip() is not None or "Payload/where-is-school.app/Info.plist" not in zipped.namelist():
            raise SystemExit("Invalid iOS IPA payload")
    stream_to_drive(ipa, ticket["upload_session"])


def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["receive", "upload"])
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    if args.command == "receive":
        receive(args.folder)
    else:
        upload(args.folder)


if __name__ == "__main__":
    main()

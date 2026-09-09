#!/usr/bin/env python3
"""Build the ENet version matching Odin's vendor bindings, locally on Linux."""

import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import urllib.request


VERSION = "1.3.17"
SHA256 = "1e0b4bc0b7127a2d779dd7928f0b31830f5b3dcb7ec9588c5de70033e8d2434a"
URL = f"https://codeload.github.com/lsalzman/enet/tar.gz/refs/tags/v{VERSION}"
DEPS = Path(__file__).resolve().parents[1] / "build" / "deps"


def main():
    if not sys.platform.startswith("linux"):
        raise SystemExit("This first host build supports Linux.")
    DEPS.mkdir(parents=True, exist_ok=True)
    archive = DEPS / f"enet-{VERSION}.tar.gz"
    if not archive.exists():
        print(f"Downloading ENet {VERSION}...", flush=True)
        with urllib.request.urlopen(URL, timeout=30) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != SHA256:
            raise SystemExit("ENet download checksum mismatch.")
        archive.write_bytes(data)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit(f"ENet checksum mismatch. Remove {archive} and retry.")

    with tarfile.open(archive) as bundle:
        bundle.extractall(DEPS, filter="data")
    source = DEPS / f"enet-{VERSION}"
    objects = DEPS / "enet-objects"
    objects.mkdir(exist_ok=True)
    features = (
        "FCNTL", "POLL", "GETADDRINFO", "GETNAMEINFO", "INET_PTON",
        "INET_NTOP", "MSGHDR_FLAGS", "SOCKLEN_T",
    )
    flags = ["-O2", "-I" + str(source / "include")]
    flags += [f"-DHAS_{feature}=1" for feature in features]
    compiler = shlex.split(os.environ.get("CC", "cc"))
    object_files = []
    for name in ("callbacks", "compress", "host", "list", "packet", "peer", "protocol", "unix"):
        output = objects / f"{name}.o"
        subprocess.run(compiler + flags + ["-c", str(source / f"{name}.c"), "-o", str(output)], check=True)
        object_files.append(str(output))
    subprocess.run(shlex.split(os.environ.get("AR", "ar")) + ["rcs", str(DEPS / "libenet.a")] + object_files, check=True)
    print(f"Built {DEPS / 'libenet.a'}")


if __name__ == "__main__":
    main()

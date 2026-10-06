#!/usr/bin/env python3
"""Regenerates the MMKV fixtures in Tests/AuroraCoreTests/Fixtures/mmkv.

The files come from the MMKV Core that the React Native build shipped, not
from AuroraCore's own encoder. The script downloads react-native-mmkv 3.3.0
from npm, checks the tarball against the integrity hash the app's
package-lock.json recorded, builds the MMKV Core it vendors (v2.0.0) with
CMake, and drives it through gen.cpp. Each scenario's expected values are
what MMKV itself reads back after writing.

Needs python3, npm, cmake, a C++20 compiler and zlib. Run from anywhere:

    python3 AuroraCore/Tools/mmkv-fixtures/generate.py
"""
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

PACKAGE = "react-native-mmkv"
VERSION = "3.3.0"
# From package-lock.json on main before the cutover.
INTEGRITY = "sha512-2iPjIJ+IAODXN35wm53EN6nv+hR/0NXLLiLWOdPA/0gXDB2dYVrr6MqvoiFpxhLhdj0B8fkf5ARNVavJaSvuuQ=="
STATE_KEY = "aurora/state"
BACKUP_KEY = "aurora/state.corrupt.1790510400000"

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(os.path.dirname(HERE))
FIXTURES = os.path.join(CORE, "Tests", "AuroraCoreTests", "Fixtures")
OUT = os.path.join(FIXTURES, "mmkv")


def legacy_raw():
    with open(os.path.join(FIXTURES, "legacy.json")) as handle:
        return {name: case["raw"] for name, case in json.load(handle)["cases"].items()}


def padded_json(length):
    """A valid persisted blob of exactly `length` UTF-8 bytes."""
    base = '{"version":6,"state":{"doses":[]},"pad":""}'
    assert len(base) <= length
    blob = base[:-2] + "x" * (length - len(base)) + '"}'
    assert len(blob.encode()) == length
    json.loads(blob)
    return blob


def many_doses(count):
    doses = [
        {"id": f"manual:dose:{1790500000000 + i * 60000}", "timestamp": 1790500000000 + i * 60000,
         "mg": 95, "source": "Drip", "note": "Café ☕ 日本"}
        for i in range(count)
    ]
    return json.dumps({"version": 6, "state": {"doses": doses}}, ensure_ascii=False, separators=(",", ":"))


def scenarios():
    raw = legacy_raw()
    return {
        # One write of a current blob.
        "single": [("set", STATE_KEY, raw["v6importing"])],
        # Zustand rewrites the whole blob on every change. With only one key
        # MMKV overwrites it in place, so the file holds a single record.
        "overwritten": [("set", STATE_KEY, raw["v1"]), ("set", STATE_KEY, raw["v4"]), ("set", STATE_KEY, raw["v6importing"])],
        # The RN storage adapter copied an unparsable blob aside, then the store saved fresh state.
        "corrupt-backup": [("set", STATE_KEY, "{not json"), ("set", BACKUP_KEY, "{not json"), ("set", STATE_KEY, raw["v5"])],
        # removeItem on the only key.
        "deleted": [("set", STATE_KEY, raw["v5"]), ("del", STATE_KEY)],
        # Lengths whose first byte is also a plausible length prefix ("{" is 123).
        "length-123": [("set", STATE_KEY, padded_json(123))],
        "length-124": [("set", STATE_KEY, padded_json(124))],
        # Large enough to need multi-byte lengths and to grow the file past one page.
        "large": [("set", STATE_KEY, many_doses(100))],
        # With a second key present MMKV appends instead of rewriting, so the
        # file holds stale copies of the state and the last one wins. One
        # write lands after a relaunch.
        "appended": [("set", BACKUP_KEY, "{not json"), ("set", STATE_KEY, raw["v1"]), ("set", STATE_KEY, raw["v4"]),
                     ("reopen",), ("set", STATE_KEY, raw["v6importing"])],
        # Many rewrites, then a trim, so MMKV compacts and rewrites the file.
        "rewritten": [("set", STATE_KEY, many_doses(i)) for i in range(1, 60)] + [("trim",)],
    }


def count_records(path):
    """Key/value records in the file, stale ones included, read independently of AuroraCore."""
    with open(path, "rb") as handle:
        data = handle.read()
    size = int.from_bytes(data[:4], "little")
    body = data[4:4 + size]

    def varint(position):
        result, shift = 0, 0
        while True:
            byte = body[position]
            position += 1
            result |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return result, position
            shift += 7

    counts = {}
    _, position = varint(0)
    while position < len(body):
        length, position = varint(position)
        key = body[position:position + length].decode()
        position += length
        length, position = varint(position)
        position += length
        counts[key] = counts.get(key, 0) + 1
    return counts


def run(cmd, **kwargs):
    subprocess.run(cmd, check=True, **kwargs)


def fetch_package(work):
    out = subprocess.run(["npm", "pack", f"{PACKAGE}@{VERSION}", "--json"], cwd=work, check=True,
                         capture_output=True, text=True).stdout
    tarball = os.path.join(work, json.loads(out)[0]["filename"])
    with open(tarball, "rb") as handle:
        digest = "sha512-" + base64.b64encode(hashlib.sha512(handle.read()).digest()).decode()
    if digest != INTEGRITY:
        sys.exit(f"integrity mismatch: {digest}")
    with tarfile.open(tarball) as archive:
        archive.extractall(work, filter="data")
    return os.path.join(work, "package")


def main():
    with tempfile.TemporaryDirectory() as work:
        package = fetch_package(work)
        core_src = os.path.join(package, "MMKV", "Core")
        build = os.path.join(work, "build")
        run(["cmake", "-S", core_src, "-B", build, "-DCMAKE_BUILD_TYPE=Release"], stdout=subprocess.DEVNULL)
        run(["cmake", "--build", build, "-j8"], stdout=subprocess.DEVNULL)
        gen = os.path.join(work, "gen")
        run(["c++", "-std=c++20", "-O1", "-I", core_src, os.path.join(HERE, "gen.cpp"),
             os.path.join(build, "libcore.a"), "-lz", "-lpthread", "-o", gen])
        with open(os.path.join(core_src, "MMKVPredef.h")) as handle:
            core_version = next(line.split('"')[1] for line in handle if "MMKV_VERSION =" in line)

        # Bytes 4-7 hold MMKV's item-size placeholder, a varint whose value
        # MMKV picks at random (AESCrypt::randomItemSizeHolder(4)) between
        # 0x200000 and 0x0FFFFFFF: always a canonical 4-byte varint, so it
        # differs from run to run. MMKVReader parses it with the same strict
        # varint rules as every other length and ignores its value.
        # Everything else is the same each time.
        shutil.rmtree(OUT, ignore_errors=True)
        os.makedirs(OUT)
        manifest = {
            "generator": "AuroraCore/Tools/mmkv-fixtures/generate.py",
            "package": f"{PACKAGE}@{VERSION}",
            "integrity": INTEGRITY,
            "mmkvCore": core_version,
            "builtOn": sys.platform,
            "scenarios": {},
        }
        for name, ops in scenarios().items():
            root = os.path.join(work, "roots", name)
            os.makedirs(root)
            lines = []
            for index, op in enumerate(ops):
                if op[0] == "set":
                    path = os.path.join(work, f"{name}-{index}.value")
                    with open(path, "w", encoding="utf-8") as handle:
                        handle.write(op[2])
                    lines.append(f"set\t{op[1]}\t{path}")
                else:
                    lines.append("\t".join(op))
            ops_file = os.path.join(work, f"{name}.ops")
            with open(ops_file, "w") as handle:
                handle.write("\n".join(lines) + "\n")
            out = subprocess.run([gen, root, ops_file], check=True, capture_output=True, text=True).stdout
            values = {}
            for line in out.splitlines():
                key, hexed = line.split("\t")
                values[key] = bytes.fromhex(hexed).decode("utf-8")
            os.makedirs(os.path.join(OUT, name))
            files = {}
            for file in sorted(os.listdir(root)):
                shutil.copyfile(os.path.join(root, file), os.path.join(OUT, name, file))
                with open(os.path.join(root, file), "rb") as handle:
                    files[file] = hashlib.sha256(handle.read()).hexdigest()
            manifest["scenarios"][name] = {"files": files, "values": values, "records": count_records(os.path.join(root, "aurora"))}
        with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=1, sort_keys=True)
            handle.write("\n")
    print(f"wrote {len(manifest['scenarios'])} scenarios to {OUT}")


if __name__ == "__main__":
    main()

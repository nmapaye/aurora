#!/usr/bin/env python3
"""Check Aurora's privacy manifest against the code (Python 3 stdlib only).

Source mode (default, runs on Linux):
  * every PrivacyInfo.xcprivacy parses; NSPrivacyTracking is false,
    NSPrivacyTrackingDomains and NSPrivacyCollectedDataTypes are present and
    empty ("Data Not Collected"); every accessed-API entry uses a known
    category and reason codes valid for it (SDK-only codes are rejected);
  * Swift/ObjC/C sources in Aurora/ and AuroraCore/Sources (not tests) are
    scanned, comments and string literals removed, for Apple's
    required-reason API categories: used but undeclared -> error, declared
    but unused -> warning;
  * every URL host in a file that can make requests (URLSession, ...) must
    be on the known list below; other URL literals are reported as links;
  * the app target must not exclude PrivacyInfo.xcprivacy and must not add
    remote Swift packages, CocoaPods or Carthage without a review.

Built-app mode (--app PATH, .app / .xcarchive / .ipa, needs a Mac build):
  * the bundled PrivacyInfo.xcprivacy exists and equals the source one;
  * the built Info.plist has no NSAppTransportSecurity (device builds;
    pass --allow-local-networking for a simulator build);
  * embedded frameworks/extensions carry their own manifest;
  * best-effort symbol hints in the executable (warnings only).

Required-reason categories and codes: Apple, "Describing use of required
reason API" (developer.apple.com/documentation/bundleresources/
describing-use-of-required-reason-api) and NSPrivacyAccessedAPIType.

Suppress a reviewed false positive with `// privacy-manifest: ignore` on the
line. Exit status: 0 pass (warnings allowed), 1 errors, 2 usage error.
"""
from __future__ import annotations

import argparse
import plistlib
import re
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_MANIFEST = Path("Aurora/PrivacyInfo.xcprivacy")
SOURCE_DIRS = [Path("Aurora"), Path("AuroraCore/Sources")]
SOURCE_SUFFIXES = {".swift", ".m", ".mm", ".c", ".h"}
SKIP_DIRS = {".git", "node_modules", "build", "DerivedData", ".build", "Tests"}
IGNORE_MARK = "privacy-manifest: ignore"

CAT = "NSPrivacyAccessedAPICategory"
# Reason codes valid in an app's own manifest. SDK-only codes are listed
# separately: an app target must not use them.
REASONS = {
    CAT + "FileTimestamp": {"DDA9.1", "C617.1", "3B52.1"},
    CAT + "SystemBootTime": {"35F9.1", "8FFB.1", "3D61.1"},
    CAT + "DiskSpace": {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
    CAT + "ActiveKeyboards": {"3EC4.1", "54BD.1"},
    CAT + "UserDefaults": {"CA92.1", "1C8F.1", "AC6B.1"},
}
SDK_ONLY = {CAT + "FileTimestamp": {"0A2A.1"}, CAT + "UserDefaults": {"C56D.1"}}

LIBC = r"(?<![\w.])"  # a C call, not a method or a member
PATTERNS = {
    CAT + "FileTimestamp": [
        r"\bNSFile(?:Creation|Modification)Date\b",
        r"\bNSURL(?:Creation|ContentModification|AttributeModification|ContentAccess|AddedToDirectory)Date(?:Key)?\b",
        r"\.(?:creationDateKey|contentModificationDateKey|attributeModificationDateKey|contentAccessDateKey|addedToDirectoryDateKey)\b",
        r"\bFileAttributeKey\.(?:creationDate|modificationDate)\b",
        r"\[\s*\.(?:creationDate|modificationDate)\s*\]",
        r"\.(?:creationDate|contentModificationDate|contentAccessDate|attributeModificationDate)\b(?=[^\n]*resourceValues)",
        LIBC + r"\b(?:stat|fstat|lstat|fstatat|getattrlist|fgetattrlist|getattrlistbulk|getattrlistat)\s*\(",
    ],
    CAT + "SystemBootTime": [
        r"\bsystemUptime\b",
        LIBC + r"\bmach_absolute_time\s*\(",
    ],
    CAT + "DiskSpace": [
        r"\b(?:NSURL)?[vV]olume(?:Available|Total)Capacity(?:ForImportantUsage|ForOpportunisticUsage)?Key\b",
        r"\bNSFileSystem(?:Free)?Size\b",
        r"\bFileAttributeKey\.system(?:Free)?Size\b",
        r"\[\s*\.system(?:Free)?Size\s*\]",
        LIBC + r"\b(?:statfs|fstatfs|statvfs|fstatvfs)\s*\(",
    ],
    CAT + "ActiveKeyboards": [r"\bactiveInputModes\b"],
    CAT + "UserDefaults": [r"\b(?:NS)?UserDefaults\b", r"@AppStorage\b", r"\bAppStorage\s*\("],
}
COMPILED = {c: [re.compile(p) for p in ps] for c, ps in PATTERNS.items()}

# Hosts the app may contact (or open in Safari). Anything else is an error so
# that a new off-device destination gets a privacy review first.
KNOWN_HOSTS = {
    "accounts.google.com": "Google OAuth (user's own account; inactive until configured)",
    "oauth2.googleapis.com": "Google OAuth token exchange",
    "www.googleapis.com": "Google Calendar API",
    "127.0.0.1": "Ollama on the developer's Mac, simulator builds only",
    "localhost": "Ollama on the developer's Mac, simulator builds only",
    "nmapaye.github.io": "privacy/support pages opened in Safari",
}
URL_RE = re.compile(r"\b(https?)://([A-Za-z0-9.\-]+)")
# Swift doc-comment / XML namespaces never contacted by the app.
INERT_HOSTS = {"www.apple.com", "apple.com"}
# A file with one of these can send requests itself; elsewhere a URL literal
# is a link the system opens outside Aurora (Safari), reported as a note.
NETWORK_API = re.compile(r"\b(?:URLSession|URLRequest|NWConnection|NWPathMonitor|ASWebAuthenticationSession|WKWebView|SFSafariViewController|CFStream|URLSessionWebSocketTask)\b")



class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.notes: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def note(self, msg: str) -> None:
        self.notes.append(msg)


def strip_swift(text: str) -> tuple[str, list[tuple[int, str]]]:
    """Blank comments and string literal bodies, keeping line numbers.

    Interpolations inside strings stay code. Returns the code and the string
    literals as (line, text) pairs.
    """
    out: list[str] = []
    strings: list[tuple[int, str]] = []
    i, n, line = 0, len(text), 1
    # Stack of contexts: ("code", paren_depth) for interpolation, or a string.
    stack: list[list] = [["code", 0]]
    buf: list[str] = []
    buf_line = 1

    def emit(ch: str, keep: bool) -> None:
        out.append(ch if keep or ch == "\n" else " ")

    while i < n:
        top = stack[-1]
        ch = text[i]
        if top[0] == "code":
            if text.startswith("//", i):
                j = text.find("\n", i)
                j = n if j < 0 else j
                out.append(" " * (j - i))
                i = j
                continue
            if text.startswith("/*", i):
                depth, j = 1, i + 2
                while j < n and depth:
                    if text.startswith("/*", j):
                        depth, j = depth + 1, j + 2
                    elif text.startswith("*/", j):
                        depth, j = depth - 1, j + 2
                    else:
                        j += 1
                for c in text[i:j]:
                    emit(c, False)
                line += text.count("\n", i, j)
                i = j
                continue
            m = re.match(r'(#*)("""|")', text[i:])
            if m and (m.group(1) or ch == '"'):
                hashes, quote = m.group(1), m.group(2)
                stack.append(["str", quote, hashes])
                out.append(" " * len(m.group(0)))
                buf, buf_line = [], line
                i += len(m.group(0))
                continue
            if ch == "(" and len(stack) > 1:
                top[1] += 1
            elif ch == ")" and len(stack) > 1:
                if top[1] == 0:
                    stack.pop()  # back into the string
                    out.append(" ")
                    i += 1
                    continue
                top[1] -= 1
            if ch == "\n":
                line += 1
            out.append(ch)
            i += 1
            continue
        # inside a string literal
        _, quote, hashes = top
        close = quote + hashes
        if text.startswith(close, i):
            strings.append((buf_line, "".join(buf)))
            stack.pop()
            out.append(" " * len(close))
            i += len(close)
            continue
        esc = "\\" + hashes
        if text.startswith(esc + "(", i):
            out.append(" " * (len(esc) + 1))
            i += len(esc) + 1
            stack.append(["code", 0])
            continue
        if text.startswith(esc, i) and i + len(esc) < n:
            seg = text[i:i + len(esc) + 1]
            buf.append(seg)
            for c in seg:
                emit(c, False)
            line += seg.count("\n")
            i += len(seg)
            continue
        if ch == "\n":
            line += 1
            if quote == '"':  # unterminated single-line string: recover
                strings.append((buf_line, "".join(buf)))
                stack.pop()
        buf.append(ch)
        emit(ch, False)
        i += 1
    return "".join(out), strings


def strip_c(text: str) -> tuple[str, list[tuple[int, str]]]:
    strings: list[tuple[int, str]] = []

    def repl(m: re.Match) -> str:
        s = m.group(0)
        if s.startswith('"') or s.startswith('@"'):
            strings.append((text.count("\n", 0, m.start()) + 1, s.strip('@"')))
        return re.sub(r"[^\n]", " ", s)

    code = re.sub(r'//[^\n]*|/\*.*?\*/|@?"(?:\\.|[^"\\\n])*"', repl, text, flags=re.S)
    return code, strings


def source_files(root: Path) -> list[Path]:
    files = []
    for d in SOURCE_DIRS:
        base = root / d
        if not base.exists():
            continue
        for p in sorted(base.rglob("*")):
            rel = p.relative_to(root)
            if p.suffix in SOURCE_SUFFIXES and p.is_file() and not (set(rel.parts) & SKIP_DIRS):
                files.append(p)
    return files


def find_manifests(root: Path) -> list[Path]:
    found = []
    for p in sorted(root.rglob("PrivacyInfo.xcprivacy")):
        if set(p.relative_to(root).parts) & (SKIP_DIRS - {"Tests"}):
            continue
        found.append(p)
    return found


def load_plist(path: Path, rep: Report) -> dict | None:
    try:
        with path.open("rb") as f:
            data = plistlib.load(f)
    except Exception as exc:  # noqa: BLE001 - report any parse failure
        rep.error(f"{path}: not a valid property list ({exc})")
        return None
    if not isinstance(data, dict):
        rep.error(f"{path}: top level is not a dictionary")
        return None
    return data


def check_manifest(path: Path, data: dict, rep: Report, label: str) -> dict[str, set[str]]:
    declared: dict[str, set[str]] = {}
    if data.get("NSPrivacyTracking") is not False:
        rep.error(f"{label}: NSPrivacyTracking must be present and false (got {data.get('NSPrivacyTracking')!r})")
    domains = data.get("NSPrivacyTrackingDomains")
    if not isinstance(domains, list) or domains:
        rep.error(f"{label}: NSPrivacyTrackingDomains must be present and empty (got {domains!r})")
    collected = data.get("NSPrivacyCollectedDataTypes")
    if not isinstance(collected, list) or collected:
        rep.error(f"{label}: NSPrivacyCollectedDataTypes must be present and empty for 'Data Not Collected' (got {collected!r})")
    apis = data.get("NSPrivacyAccessedAPITypes", [])
    if not isinstance(apis, list):
        rep.error(f"{label}: NSPrivacyAccessedAPITypes must be an array")
        return declared
    for k, entry in enumerate(apis):
        if not isinstance(entry, dict):
            rep.error(f"{label}: NSPrivacyAccessedAPITypes[{k}] is not a dictionary")
            continue
        cat = entry.get("NSPrivacyAccessedAPIType")
        reasons = entry.get("NSPrivacyAccessedAPITypeReasons")
        if cat not in REASONS:
            rep.error(f"{label}: unknown API category {cat!r}")
            continue
        if cat in declared:
            rep.error(f"{label}: {short(cat)} declared twice")
        if not isinstance(reasons, list) or not reasons:
            rep.error(f"{label}: {short(cat)} has no reason codes")
            reasons = []
        for r in reasons:
            if r in SDK_ONLY.get(cat, set()):
                rep.error(f"{label}: {short(cat)} reason {r} is for third-party SDKs only, not an app")
            elif r not in REASONS[cat]:
                rep.error(f"{label}: {short(cat)} reason {r!r} is not a valid code ({', '.join(sorted(REASONS[cat]))})")
        declared.setdefault(cat, set()).update(reasons)
    return declared


def short(cat: str) -> str:
    return cat.replace(CAT, "")


def scan_sources(root: Path, rep: Report) -> tuple[dict[str, list[str]], list[tuple[str, int, str]], dict[Path, tuple[str, str]], set[str]]:
    uses: dict[str, list[str]] = {c: [] for c in PATTERNS}
    literals: list[tuple[str, int, str]] = []
    cache: dict[Path, tuple[str, str]] = {}
    networked: set[str] = set()
    for path in source_files(root):
        raw = path.read_text(encoding="utf-8", errors="replace")
        code, strings = (strip_swift if path.suffix == ".swift" else strip_c)(raw)
        cache[path] = (raw, code)
        rel = str(path.relative_to(root))
        if NETWORK_API.search(code):
            networked.add(rel)
        raw_lines = raw.splitlines()
        own_funcs = set(re.findall(r"\bfunc\s+(\w+)\s*[(<]", code))
        for number, ln in enumerate(code.splitlines(), 1):
            if number <= len(raw_lines) and IGNORE_MARK in raw_lines[number - 1]:
                continue
            for cat, regs in COMPILED.items():
                for reg in regs:
                    m = reg.search(ln)
                    if not m:
                        continue
                    name = re.match(r"\w+", m.group(0).lstrip("@[. "))
                    if name and name.group(0) in own_funcs and reg.pattern.startswith(LIBC):
                        continue  # the file's own function, not libc
                    uses[cat].append(f"{rel}:{number}: {raw_lines[number - 1].strip()[:110]}")
                    break
        for number, s in strings:
            literals.append((rel, number, s))
    return uses, literals, cache, networked


def check_hosts(literals: list[tuple[str, int, str]], networked: set[str], rep: Report) -> list[str]:
    seen = []
    links: dict[str, list[str]] = {}
    for rel, number, s in literals:
        for scheme, host in URL_RE.findall(s):
            host = host.lower().rstrip(".")
            if host in INERT_HOSTS:
                continue
            where = f"{rel}:{number}"
            if host not in KNOWN_HOSTS and rel not in networked:
                links.setdefault(host, []).append(where)
                continue
            if host not in KNOWN_HOSTS:
                rep.error(f"{where}: unreviewed network host {host!r}; add it to KNOWN_HOSTS after a privacy review")
                continue
            if scheme == "http" and host not in {"127.0.0.1", "localhost"}:
                rep.error(f"{where}: plain HTTP to {host} (ATS would block it; use HTTPS)")
            seen.append(f"{scheme}://{host} ({KNOWN_HOSTS[host]}) at {where}")
    for host, wheres in sorted(links.items()):
        rep.note(f"link-only host {host} (no request API in {', '.join(sorted({w.split(':')[0] for w in wheres}))}; opened outside Aurora)")
    return seen


def check_project(root: Path, rep: Report) -> None:
    pbx = root / "Aurora.xcodeproj/project.pbxproj"
    if not pbx.exists():
        rep.warn(f"{pbx.relative_to(root)} not found; skipped project checks")
        return
    text = pbx.read_text(encoding="utf-8", errors="replace")
    for block in re.findall(r"membershipExceptions\s*=\s*\((.*?)\);", text, flags=re.S):
        if "PrivacyInfo.xcprivacy" in block:
            rep.error("project.pbxproj: PrivacyInfo.xcprivacy is in membershipExceptions, so it won't be bundled")
    if "XCRemoteSwiftPackageReference" in text:
        rep.warn("project.pbxproj: remote Swift packages found; each third-party SDK needs its own privacy manifest/signature review")
    for f in ("Podfile", "Cartfile", "Package.resolved"):
        for p in root.rglob(f):
            if not set(p.relative_to(root).parts) & SKIP_DIRS:
                rep.warn(f"{p.relative_to(root)}: third-party dependencies present; review their privacy manifests")




def locate_app(path: Path, tmp: Path) -> Path | None:
    if path.suffix == ".ipa":
        with zipfile.ZipFile(path) as z:
            z.extractall(tmp)
        apps = sorted(tmp.glob("Payload/*.app"))
        return apps[0] if apps else None
    if path.suffix == ".xcarchive":
        apps = sorted((path / "Products/Applications").glob("*.app"))
        return apps[0] if apps else None
    if path.suffix == ".app":
        return path
    return None


def check_app(app_arg: Path, source_manifest: dict | None, declared: dict[str, set[str]], args, rep: Report) -> None:
    with tempfile.TemporaryDirectory() as td:
        try:
            app = locate_app(app_arg, Path(td))
        except (zipfile.BadZipFile, OSError) as exc:
            rep.error(f"{app_arg}: cannot open ({exc})")
            return
        if app is None or not app.is_dir():
            rep.error(f"{app_arg}: no .app bundle found (pass a .app, .xcarchive or .ipa)")
            return
        manifest = app / "PrivacyInfo.xcprivacy"
        if not manifest.exists():
            rep.error(f"{app.name}: PrivacyInfo.xcprivacy is not bundled")
        else:
            built = load_plist(manifest, rep)
            if built is not None:
                check_manifest(manifest, built, rep, f"{app.name}/PrivacyInfo.xcprivacy")
                if source_manifest is not None and built != source_manifest:
                    rep.error(f"{app.name}/PrivacyInfo.xcprivacy differs from {APP_MANIFEST}")
        info = load_plist(app / "Info.plist", rep) or {}
        ats = info.get("NSAppTransportSecurity")
        if ats is not None:
            bad = {k for k in ats if k != "NSAllowsLocalNetworking"} if isinstance(ats, dict) else {"?"}
            if bad:
                rep.error(f"{app.name}/Info.plist: NSAppTransportSecurity contains {sorted(bad)}")
            if not args.allow_local_networking:
                rep.error(f"{app.name}/Info.plist: NSAppTransportSecurity present in a device build ({ats}); see PR #48")
        for sub in sorted(list(app.glob("Frameworks/*.framework")) + list(app.glob("PlugIns/*.appex"))):
            if not (sub / "PrivacyInfo.xcprivacy").exists():
                (rep.warn if sub.name.startswith("libswift") else rep.error)(
                    f"{app.name}/{sub.relative_to(app)}: no PrivacyInfo.xcprivacy (each bundle needs its own)")
        exe = app / info.get("CFBundleExecutable", app.stem)
        if exe.exists():
            blob = exe.read_bytes()
            hints = {
                CAT + "SystemBootTime": [b"_mach_absolute_time", b"systemUptime"],
                CAT + "DiskSpace": [b"volumeAvailableCapacity", b"_statfs", b"NSFileSystemFreeSize"],
                CAT + "ActiveKeyboards": [b"activeInputModes"],
                CAT + "FileTimestamp": [b"NSFileModificationDate", b"NSFileCreationDate", b"NSURLContentModificationDateKey"],
            }
            for cat, needles in hints.items():
                hit = [n.decode() for n in needles if n in blob]
                if hit and cat not in declared:
                    rep.warn(f"{exe.name}: references {', '.join(hit)} but {short(cat)} isn't declared (check; system code can cause this)")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("app", nargs="?", type=Path, help="optional built .app, .xcarchive or .ipa")
    ap.add_argument("--root", type=Path, default=ROOT, help="repository root (default: this repo)")
    ap.add_argument("--allow-local-networking", action="store_true", help="accept NSAllowsLocalNetworking (simulator builds)")
    ap.add_argument("--strict", action="store_true", help="treat warnings as errors")
    ap.add_argument("-v", "--verbose", action="store_true", help="list every API use and host found")
    args = ap.parse_args(argv)
    root = args.root.resolve()
    rep = Report()

    manifests = find_manifests(root)
    if not manifests:
        rep.error("no PrivacyInfo.xcprivacy found")
    if (root / APP_MANIFEST) not in manifests:
        rep.error(f"{APP_MANIFEST} is missing")
    declared: dict[str, set[str]] = {}
    source_manifest = None
    for m in manifests:
        data = load_plist(m, rep)
        if data is None:
            continue
        d = check_manifest(m, data, rep, str(m.relative_to(root)))
        if m == root / APP_MANIFEST:
            declared, source_manifest = d, data
        else:
            rep.note(f"extra manifest {m.relative_to(root)} (only valid inside its own bundle)")

    uses, literals, cache, networked = scan_sources(root, rep)
    for cat, hits in uses.items():
        if hits and cat not in declared:
            rep.error(f"{short(cat)} API used but not declared in {APP_MANIFEST}:\n      " + "\n      ".join(hits))
        elif not hits and cat in declared:
            rep.warn(f"{short(cat)} declared ({', '.join(sorted(declared[cat]))}) but no use found in {', '.join(map(str, SOURCE_DIRS))}")
    hosts = check_hosts(literals, networked, rep)
    check_project(root, rep)
    if args.app:
        if not args.app.exists():
            print(f"error: {args.app} does not exist", file=sys.stderr)
            return 2
        check_app(args.app, source_manifest, declared, args, rep)

    print(f"Manifests: {', '.join(str(m.relative_to(root)) for m in manifests) or 'none'}")
    for cat in PATTERNS:
        state = "declared " + ",".join(sorted(declared[cat])) if cat in declared else "not declared"
        print(f"  {short(cat):16} uses={len(uses[cat]):3}  {state}")
        if args.verbose:
            for h in uses[cat]:
                print(f"      {h}")
    print(f"Network hosts in code: {len(hosts)}")
    if args.verbose:
        for h in hosts:
            print(f"      {h}")
    for n in rep.notes:
        print(f"note: {n}")
    for w in rep.warnings:
        print(f"warning: {w}")
    for e in rep.errors:
        print(f"error: {e}")
    failed = bool(rep.errors) or (args.strict and bool(rep.warnings))
    print("Privacy manifest check " + ("FAILED" if failed else "passed") +
          f" ({len(rep.errors)} errors, {len(rep.warnings)} warnings)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

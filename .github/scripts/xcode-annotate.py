"""Turn xcodebuild errors and failed tests into GitHub annotations.

Job logs are not always reachable, but annotations are, so the first
failures of a run stay readable from the checks API.
"""
import re
import sys

LOCATED = re.compile(r"^(/[^:]+):(\d+):(?:\d+:)? error: (.*)$")
PLAIN = re.compile(r"(?:^|\s)error: (.*)$")
FAILED = re.compile(r"(Test Case .* failed.*|Test case .* failed.*|✘ .*|.*Suite .* failed.*)")


def escape(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(path):
    seen, lines = set(), []
    with open(path, errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            match = LOCATED.match(line)
            if match:
                file, number, message = match.groups()
                key = f"{file.split('/Aurora/', 1)[-1] if '/Aurora/' in file else file}:{number}: {message}"
            elif PLAIN.search(line) or FAILED.search(line):
                key = line.strip()
            else:
                continue
            if key not in seen:
                seen.add(key)
                lines.append(key)
    if not lines:
        return
    # A step keeps only ten error annotations, so the full list goes in one.
    for chunk_start in range(0, min(len(lines), 120), 40):
        chunk = lines[chunk_start:chunk_start + 40]
        print(f"::error title=xcodebuild ({chunk_start + 1}-{chunk_start + len(chunk)} of {len(lines)})::" + escape("\n".join(chunk)))


if __name__ == "__main__":
    main(sys.argv[1])

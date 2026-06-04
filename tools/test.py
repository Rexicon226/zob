#!/usr/bin/env python3

import argparse
import concurrent.futures as cf
import difflib
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
SNAPS = TESTS / "snapshots"
AROCC = ROOT / "zig-out/bin/arocc"

ZIG = os.getenv("ZIG", "zig")
COLOR = sys.stdout.isatty() and "NO_COLOR" not in os.environ


def c(text, color):
    if not COLOR:
        return text
    return f"\033[{dict(red=31,green=32,yellow=33,blue=34,grey=90)[color]}m{text}\033[0m"


def directives(src):
    d = {"expect": None, "asm": [], "asm_not": [], "skip": None}
    for line in src.splitlines():
        m = re.match(r"\s*//\s*(EXPECT|ASM|ASM-NOT|SKIP)\s*:\s*(.*)", line)
        if not m:
            continue

        kind, body = m.groups()
        if kind == "EXPECT":
            d["expect"] = body
        elif kind == "ASM":
            d["asm"].append(body)
        elif kind == "ASM-NOT":
            d["asm_not"].append(body)
        else:
            d["skip"] = body or "skipped"

    return d


def regex(pattern):
    return re.compile(re.sub(r"\{\{(.*?)\}\}", r"(\1)", re.escape(pattern)))


def snapshot(name, asm, bless):
    path = SNAPS / f"{name}.s"

    if bless:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(asm)
        return None

    if not path.exists():
        return "missing snapshot (--bless)"

    want = path.read_text()
    if want == asm:
        return None

    diff = "".join(
        difflib.unified_diff(
            want.splitlines(True),
            asm.splitlines(True),
            fromfile="expected",
            tofile="actual",
        )
    )

    return "snapshot mismatch:\n" + diff


def test_file(path, args):
    name = path.relative_to(TESTS).with_suffix("").as_posix()

    d = directives(path.read_text())

    if d["skip"]:
        return ("SKIP", name, d["skip"])

    p = subprocess.run(
        [str(AROCC), str(path)],
        capture_output=True,
        text=True,
    )

    if p.returncode:
        return ("FAIL", name, p.stderr or p.stdout)

    asm = p.stdout
    lines = asm.splitlines()

    pos = 0
    for pat in d["asm"]:
        rx = regex(pat)

        for i in range(pos, len(lines)):
            if rx.search(lines[i]):
                pos = i + 1
                break
        else:
            return ("FAIL", name, f"ASM not found: {pat}")

    for pat in d["asm_not"]:
        rx = regex(pat)

        for line in lines:
            if rx.search(line):
                return ("FAIL", name, f"ASM-NOT matched: {pat}")

    err = snapshot(name, asm, args.bless)
    if err:
        return ("FAIL", name, err)

    return ("PASS", name, "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tests", nargs="*")
    ap.add_argument("-k")
    ap.add_argument("-j", type=int, default=os.cpu_count())
    ap.add_argument("--bless", action="store_true")
    args = ap.parse_args()

    print(c("building arocc...", "grey"))

    if subprocess.run([ZIG, "build"], cwd=ROOT).returncode:
        return 1

    tests = [
        p
        for p in TESTS.rglob("*.c")
        if not p.name.startswith("_")
        and SNAPS not in p.parents
        and (
            not args.tests
            or any(t in p.stem or t in str(p) for t in args.tests)
        )
        and (not args.k or args.k in str(p))
    ]

    with cf.ThreadPoolExecutor(max_workers=args.j) as ex:
        results = list(ex.map(lambda p: test_file(p, args), tests))

    counts = {"PASS": 0, "FAIL": 0, "SKIP": 0}

    for status, name, detail in results:
        counts[status] += 1

        tag = {
            "PASS": c("PASS", "green"),
            "FAIL": c("FAIL", "red"),
            "SKIP": c("SKIP", "yellow"),
        }[status]

        print(f"{tag} {name}")

        if status == "FAIL" and detail:
            print(c(detail, "grey"))

    print()
    print(
        c(
            f"{counts['PASS']} passed, "
            f"{counts['FAIL']} failed, "
            f"{counts['SKIP']} skipped",
            "green" if counts["FAIL"] == 0 else "red",
        )
    )

    return counts["FAIL"] != 0


if __name__ == "__main__":
    raise SystemExit(main())
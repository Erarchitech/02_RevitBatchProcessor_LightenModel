# -*- coding: utf-8 -*-
import argparse
import os
import re
import sys
from typing import Optional


HEADER_PATTERNS = [
    re.compile(rb"Revit\s*Build[:\s]+(\d{4})", re.IGNORECASE),
    re.compile(rb"Revit\s*Version[:\s]+(\d{4})", re.IGNORECASE),
    re.compile(rb"Autodesk\s+Revit\s+(\d{4})", re.IGNORECASE),
]

NAME_PATTERNS = [
    re.compile(r"[_\-]r(\d{2})(?:[_\-]|\.|$)", re.IGNORECASE),
    re.compile(r"\b(20\d{2})\b"),
]


def normalize_line(line: str) -> str:
    if not line:
        return ""
    s = line.replace("\ufeff", "").replace("\u200b", "").strip()
    if s.startswith('"') and s.endswith('"') and len(s) > 1:
        s = s[1:-1].strip()
    return s


def is_remote_path(path: str) -> bool:
    upper = path.upper()
    return upper.startswith("RSN:") or upper.startswith("HTTP://") or upper.startswith("HTTPS://")


def detect_year_from_name(path: str) -> Optional[int]:
    base = os.path.basename(path)
    for pat in NAME_PATTERNS:
        m = pat.search(base)
        if not m:
            continue
        value = m.group(1)
        try:
            year = int(value)
        except ValueError:
            continue
        if year < 100:
            year = 2000 + year
        if 2000 <= year <= 2099:
            return year
    return None


def detect_year_from_header(path: str, max_bytes: int) -> Optional[int]:
    try:
        with open(path, "rb") as f:
            read_total = 0
            tail = b""
            while read_total < max_bytes:
                chunk = f.read(min(256 * 1024, max_bytes - read_total))
                if not chunk:
                    break
                read_total += len(chunk)
                blob = tail + chunk
                for pat in HEADER_PATTERNS:
                    m = pat.search(blob)
                    if m:
                        try:
                            return int(m.group(1))
                        except ValueError:
                            return None
                tail = blob[-1024:]
    except Exception:
        return None
    return None


def write_list(path: str, items) -> None:
    if not items:
        if os.path.exists(path):
            try:
                os.remove(path)
            except OSError:
                pass
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for item in items:
            f.write(item + "\n")


def main(argv) -> int:
    parser = argparse.ArgumentParser(description="Detect Revit versions and split file list by year.")
    parser.add_argument("--list", required=True, help="Path to source file list (UTF-8).")
    parser.add_argument("--out_prefix", required=True, help="Prefix for output lists, e.g. C:\\Lists\\List_RVT-models_.")
    parser.add_argument("--years", nargs="+", type=int, default=[], help="Allowed Revit years.")
    parser.add_argument("--unknown", default="", help="Path to write unknown-version list.")
    parser.add_argument("--max_bytes", type=int, default=2 * 1024 * 1024, help="Max bytes to scan per file.")
    args = parser.parse_args(argv)

    try:
        lines = open(args.list, "r", encoding="utf-8-sig").read().splitlines()
    except Exception as exc:
        print("ERROR: failed to read list: {0}".format(exc))
        return 2

    allowed = set(args.years) if args.years else set()
    grouped = {}
    unknown = []

    for raw in lines:
        path = normalize_line(raw)
        if not path or path.startswith("#"):
            continue

        year = None
        if not is_remote_path(path):
            year = detect_year_from_header(path, args.max_bytes)
        if year is None:
            year = detect_year_from_name(path)

        if year is None or (allowed and year not in allowed):
            unknown.append(path)
            continue

        grouped.setdefault(year, []).append(path)

    for year, items in grouped.items():
        out_path = "{0}{1}.txt".format(args.out_prefix, year)
        write_list(out_path, items)

    if args.unknown:
        write_list(args.unknown, unknown)

    for year in sorted(grouped.keys()):
        print("Detected {0}: {1}".format(year, len(grouped[year])))
    if unknown:
        print("Unknown: {0}".format(len(unknown)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
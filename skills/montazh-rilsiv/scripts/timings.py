#!/usr/bin/env python3
"""Print how long each stage of a reel took, from <reel>/timings.log ("<unix-seconds> <stage>:start|end" lines).
Usage: python3 timings.py <reel-folder>"""
import os as _os, sys as _sys; _sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__))); import _utf8  # Windows: UTF-8 mode
import sys
from pathlib import Path

starts, rows = {}, []
for line in (Path(sys.argv[1]).expanduser() / "timings.log").read_text().split("\n"):
    if not line.strip(): continue
    t, tag = line.split(" ", 1); stage, edge = tag.rsplit(":", 1)
    if edge == "start": starts[stage] = int(t)
    elif stage in starts: rows.append((stage, int(t) - starts.pop(stage)))
for stage, s in rows: print(f"  {stage:<10} {s // 60}m {s % 60:02d}s")
print(f"  {'total':<10} {sum(s for _, s in rows) // 60}m {sum(s for _, s in rows) % 60:02d}s")

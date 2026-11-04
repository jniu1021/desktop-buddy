#!/usr/bin/env python3
"""Measure one macOS process's CPU-time delta and RSS. No screen/audio collection."""
import argparse
import json
import subprocess
import time
from pathlib import Path


def cpu_seconds(value):
    days = 0
    if '-' in value:
        day, value = value.split('-', 1)
        days = int(day)
    parts = [float(x) for x in value.split(':')]
    result = 0.0
    for part in parts:
        result = result * 60 + part
    return days * 86400 + result


def read(pid):
    fields = subprocess.check_output(['ps', '-p', str(pid), '-o', 'time=,rss='], text=True).split()
    if len(fields) != 2:
        raise RuntimeError('Process not found or metrics unavailable')
    return cpu_seconds(fields[0]), int(fields[1]) / 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--duration', type=int, default=30, choices=range(5, 301), metavar='5..300')
    parser.add_argument('--condition', required=True, choices=['diary_off', 'metadata', 'screen', 'audio', 'combined', 'observed_uncontrolled'])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    start = time.monotonic()
    first, rss = read(args.pid)
    memory = [rss]
    latest = first
    for _ in range(args.duration):
        time.sleep(1)
        latest, rss = read(args.pid)
        memory.append(rss)
    wall = time.monotonic() - start
    report = dict(condition=args.condition, wallSeconds=wall,
                  cpuSeconds=max(0, latest - first),
                  cpuPercentOneCore=max(0, latest - first) / wall * 100,
                  rssMiBStart=memory[0], rssMiBEnd=memory[-1], rssMiBMax=max(memory),
                  limitation='Single process only; RSS is not Instruments physical footprint or energy. Short runs can miss intermittent inference. User must configure the named condition.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

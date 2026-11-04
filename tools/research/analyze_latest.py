#!/usr/bin/env python3
"""Analyze the most recently modified completed local session."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from evaluate import load


def latest_completed(directory):
    completed = []
    for path in directory.glob('session-*.jsonl'):
        try:
            events = load(path)
            if events[0].get('kind') == 'session_start' and events[-1].get('kind') == 'session_end':
                completed.append(path)
        except (ValueError, OSError):
            continue
    return max(completed, key=lambda p: p.stat().st_mtime) if completed else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--no-open', action='store_true')
    args = parser.parse_args()
    recording = latest_completed(args.directory)
    if recording is None:
        print('还没有已停止的完整记录。请先开始采集、预约候选、保存标注，然后点击停止。')
        return 1
    stem = recording.with_suffix('')
    output = Path(str(stem) + '-report.json')
    html = Path(str(stem) + '-report.html')
    subprocess.run([sys.executable, str(Path(__file__).with_name('evaluate.py')),
                    str(recording), '--output', str(output), '--html', str(html)], check=True)
    report = json.loads(output.read_text())
    values = report['policies']['A']
    if values['candidates'] == 0:
        print('注意：本次没有候选，报告只验证了采集，不能比较政策。')
    elif values['labeled'] == 0:
        print('注意：本次没有标注，不能评价与用户偏好的一致性。')
    if not args.no_open:
        subprocess.run(['open', str(html)], check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

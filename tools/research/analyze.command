#!/bin/zsh
set -eu
RESEARCH_ROOT="${0:A:h:h:h}"
python3 "$RESEARCH_ROOT/tools/research/analyze_latest.py" "$RESEARCH_ROOT/research-data"

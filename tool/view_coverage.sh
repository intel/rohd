#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d coverage/html ]; then
	"${SCRIPT_DIR}/generate_coverage.sh"
fi

cd coverage/html
python3 -m http.server 8000 --bind 0.0.0.0

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(pwd -P)"
COVERAGE_DIR="${TARGET_DIR}/coverage/html"
REGENERATE=false

usage() {
	cat << EOF
Usage: $(basename "$0") [--regenerate]

Serve the coverage HTML report for the current package directory.

Options:
  -f, --force, --regenerate  Regenerate coverage before serving.
  -h, --help                 Show this help text.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-f|--force|--regenerate)
			REGENERATE=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			usage
			exit 2
			;;
	esac
	shift
done

if [ "${REGENERATE}" = true ] || [ ! -f "${COVERAGE_DIR}/index.html" ]; then
	(
		cd "${TARGET_DIR}"
		"${SCRIPT_DIR}/generate_coverage.sh"
	)
fi

COVERAGE_DIR="${TARGET_DIR}/coverage/html"
if [ ! -f "${COVERAGE_DIR}/index.html" ]; then
	echo "Coverage HTML not found at ${COVERAGE_DIR}/index.html"
	exit 1
fi

PORT="${PORT:-8000}"
MAX_PORT=$((PORT + 20))
while ! python3 -c 'import socket, sys; server = socket.socket(); server.bind(("127.0.0.1", int(sys.argv[1]))); server.close()' "${PORT}" 2>/dev/null
do
	PORT=$((PORT + 1))
	if [ "${PORT}" -gt "${MAX_PORT}" ]; then
		echo "No available HTTP port found between $((MAX_PORT - 20)) and ${MAX_PORT}."
		exit 1
	fi
done

printf 'Serving coverage from %s\n' "${COVERAGE_DIR}"
URL="http://127.0.0.1:${PORT}/index.html"
printf 'Open %s\n' "${URL}"

python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${COVERAGE_DIR}" &
SERVER_PID=$!

cleanup() {
	if kill -0 "${SERVER_PID}" 2>/dev/null; then
		kill "${SERVER_PID}"
	fi
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 50); do
	if python3 -c 'import socket, sys; client = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.1); client.close()' "${PORT}" 2>/dev/null
	then
		break
	fi
	sleep 0.1
done

if [ -n "${BROWSER:-}" ]; then
	"${BROWSER}" "${URL}" >/dev/null 2>&1 &
else
	echo 'BROWSER is not set; open the URL above manually.'
fi

wait "${SERVER_PID}"

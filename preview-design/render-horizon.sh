#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_html="${script_dir}/horizon.html"
output_dir="${script_dir}/png/horizon"
large_png="${output_dir}/large.png"
small_png="${output_dir}/small.png"
session_name="anyupright-horizon-render-$$"

if [[ ! -f "${source_html}" ]]; then
  echo "Missing source HTML: ${source_html}" >&2
  exit 1
fi

for required_command in python3 curl sips; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Missing required command: ${required_command}" >&2
    exit 1
  fi
done

playwright_command=()
if [[ -n "${PLAYWRIGHT_CLI:-}" ]]; then
  playwright_command=("${PLAYWRIGHT_CLI}")
elif command -v playwright-cli >/dev/null 2>&1; then
  playwright_command=("$(command -v playwright-cli)")
else
  codex_base="${CODEX_HOME:-${HOME}/.codex}"
  bundled_wrapper="${codex_base}/skills/playwright/scripts/playwright_cli.sh"
  if [[ -x "${bundled_wrapper}" ]]; then
    playwright_command=("${bundled_wrapper}")
  elif command -v npx >/dev/null 2>&1; then
    playwright_command=(npx --yes --package @playwright/cli playwright-cli)
  else
    echo "Missing Playwright CLI. Install Node.js/npm or set PLAYWRIGHT_CLI." >&2
    exit 1
  fi
fi

server_port="$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
server_log="$(mktemp -t anyupright-horizon-render.XXXXXX)"
server_pid=""

cleanup() {
  set +e
  "${playwright_command[@]}" --session "${session_name}" close >/dev/null 2>&1
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" >/dev/null 2>&1
    wait "${server_pid}" >/dev/null 2>&1
  fi
  rm -f "${server_log}"
}
trap cleanup EXIT INT TERM

python3 -m http.server "${server_port}" \
  --bind 127.0.0.1 \
  --directory "${script_dir}" \
  >"${server_log}" 2>&1 &
server_pid=$!

preview_url="http://127.0.0.1:${server_port}/horizon.html"
for _ in {1..50}; do
  if curl --fail --silent --show-error "${preview_url}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

if ! curl --fail --silent --show-error "${preview_url}" >/dev/null; then
  echo "Failed to start preview server:" >&2
  cat "${server_log}" >&2
  exit 1
fi

mkdir -p "${output_dir}"

"${playwright_command[@]}" --session "${session_name}" open "${preview_url}" >/dev/null
"${playwright_command[@]}" --session "${session_name}" resize 640 360 >/dev/null
"${playwright_command[@]}" --session "${session_name}" screenshot \
  --filename "${large_png}" >/dev/null

sips --resampleHeightWidth 108 192 "${large_png}" --out "${small_png}" >/dev/null

echo "Rendered ${large_png} (640x360)"
echo "Rendered ${small_png} (192x108)"

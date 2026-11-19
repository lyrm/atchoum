#!/bin/sh
# Run the plugin evals against a minimal copy of the plugin.
#
# The checkout holds _opam/ and _build/, more entries than `claude plugin eval`
# accepts in a plugin directory, so the evals run on a staging directory with
# only the manifest, the eval cases and the server executable. Extra arguments
# are passed to `claude plugin eval` (e.g. --case NAME, --runs N).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
exe="$root/_build/default/server/main.exe"
if [ ! -x "$exe" ]; then
  echo "atchoum-mcp is not built: run 'dune build' first" >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$root/.claude-plugin" "$stage/"
cp -R "$root/evals" "$stage/"
rm -rf "$stage/evals/results"
mkdir -p "$stage/_build/install/default/bin"
cp "$exe" "$stage/_build/install/default/bin/atchoum-mcp"

out="$root/evals/results/$(date -u +%Y-%m-%dT%H-%M-%SZ)"
mkdir -p "$out"

claude plugin eval "$stage" \
  --scaffold \
  --mocks off \
  --allow-tools 'mcp__plugin_atchoum_merlin__*' \
  --trust-plugin \
  --no-publish \
  --output-dir "$out" \
  --json "$out/result.json" \
  --keep-temp \
  "$@" || status=$?

# Copy the traces and summarize tokens, then remove the run directories that
# --keep-temp left behind (read-only and partly sealed, hence the chmod).
python3 "$root/evals/summarize.py" "$out/result.json"
python3 - "$out/result.json" <<'EOF' | while read -r dir; do
import json, os, sys
dirs = set()
for case in json.load(open(sys.argv[1]))["cases"]:
    for runs in case["arms"].values():
        for run in runs:
            trace = run.get("tracePath") or ""
            top = os.path.dirname(os.path.dirname(trace))
            if os.path.basename(top).startswith("claude-eval-"):
                dirs.add(top)
print("\n".join(sorted(dirs)))
EOF
  [ -n "$dir" ] && chmod -R u+rwx "$dir" && rm -rf "$dir"
done
exit "${status:-0}"

#!/bin/sh
# Like aliased-create, at scale: 80 modules m00..m79 each define `create`,
# Registry holds 80 aliases, and Demo calls the one behind Registry.Store (M37).
set -e
command -v dune >/dev/null || { echo "scaffold: dune not found in PATH" >&2; exit 1; }
printf '(lang dune 3.0)\n' > dune-project
mkdir -p lib
printf '(library\n (name app))\n' > lib/dune
: > lib/registry.ml
i=0
while [ "$i" -lt 80 ]; do
  m=$(printf 'm%02d' "$i")
  case $((i % 4)) in
    0) body='x + 1' ;;
    1) body='(x, x)' ;;
    2) body='[ x ]' ;;
    *) body='Some x' ;;
  esac
  printf 'let name = "%s"\n\nlet create x = %s\n' "$m" "$body" > "lib/$m.ml"
  target=$(( (i * 7 + 3) % 80 ))
  if [ "$i" -eq 40 ]; then
    printf 'module Store = M37\n' >> lib/registry.ml
  fi
  printf 'module Alias%02d = M%02d\n' "$i" "$target" >> lib/registry.ml
  i=$((i + 1))
done
cat > lib/demo.ml <<'ML'
module S = Registry.Store

let s = S.create 42
ML
dune build 2>&1

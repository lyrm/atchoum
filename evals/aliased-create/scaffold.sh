#!/bin/sh
# Eight modules each define `create`; Registry aliases them under other names
# and Demo calls the one behind Registry.Store (Gamma).
set -e
command -v dune >/dev/null || { echo "scaffold: dune not found in PATH" >&2; exit 1; }
printf '(lang dune 3.0)\n' > dune-project
mkdir -p lib
printf '(library\n (name app))\n' > lib/dune
module() { printf 'let name = "%s"\n\nlet create x = %s\n' "$1" "$2" > "lib/$1.ml"; }
module alpha 'x + 1'
module beta '[ x ]'
module gamma '(x, x)'
module delta 'Some x'
module epsilon 'string_of_int x'
module zeta 'Array.make 3 x'
module eta 'ref x'
module theta 'fun () -> x'
cat > lib/registry.ml <<'ML'
module Index = Alpha
module Table = Beta
module Store = Gamma
module Queue = Delta
module Cache = Epsilon
module Pool = Zeta
module Cell = Eta
module Thunk = Theta
ML
cat > lib/demo.ml <<'ML'
module S = Registry.Store

let s = S.create 42
ML
dune build 2>&1

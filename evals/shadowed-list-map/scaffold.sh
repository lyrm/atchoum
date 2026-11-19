#!/bin/sh
# List is shadowed through Util (module List) and Prelude (include Util).
set -e
command -v dune >/dev/null || { echo "scaffold: dune not found in PATH" >&2; exit 1; }
printf '(lang dune 3.0)\n' > dune-project
mkdir -p lib
printf '(library\n (name app))\n' > lib/dune
cat > lib/util.ml <<'ML'
module List = struct
  include Stdlib.List

  let map f (a, b) = (f a, f b)
end
ML
printf 'include Util\n' > lib/prelude.ml
cat > lib/demo.ml <<'ML'
open Prelude

let lengths = List.length [ 1; 2; 3 ]
let both = List.map
ML
dune build 2>&1

#!/bin/sh
# A single file with an unannotated function mixing optional and labelled
# arguments with polymorphic variants. No build needed: Merlin types one file.
set -e
printf '(lang dune 3.0)\n' > dune-project
mkdir -p lib
printf '(library\n (name app))\n' > lib/dune
cat > lib/demo.ml <<'ML'
let f ?(k = 1) ~g = function `A n -> g (n + k) | `B s -> String.length s
ML

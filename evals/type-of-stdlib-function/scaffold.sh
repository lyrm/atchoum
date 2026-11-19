#!/bin/sh
# Creates a tiny dune project whose lib/demo.ml uses a stdlib function.
set -e
printf '(lang dune 3.0)\n' > dune-project
mkdir -p lib
printf '(library\n (name demo))\n' > lib/dune
printf 'let unfold = Seq.unfold\n' > lib/demo.ml

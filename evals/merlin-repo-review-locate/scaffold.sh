#!/bin/sh
# Copies a prebuilt clone of Merlin (tag v5.9.1-505, built with atchoum's
# local switch) into the run's workspace. See README, section Evals.
set -e
bench=/home/lyrm/src/merlin-bench
if [ ! -d "$bench/_build/default/src" ]; then
  echo "scaffold: no prebuilt Merlin clone in $bench" >&2
  exit 1
fi
tar -C "$bench" --exclude=.git -cf - . | tar -xf -
# Inject two logic bugs that still type-check, keeping line numbers:
# - line 177: an .mli is preferred exactly when an .ml is (instead of the
#   opposite);
# - line 476: the heuristic sort of find_source is reversed, so the least
#   likely candidate file is picked.
f=src/analysis/locate.ml
sed -i '177s/| Some (MLI _) -> not !prioritize_impl/| Some (MLI _) -> !prioritize_impl/' "$f"
sed -i '476s/let tmp = compare j i in/let tmp = compare i j in/' "$f"

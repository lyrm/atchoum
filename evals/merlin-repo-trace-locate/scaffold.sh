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

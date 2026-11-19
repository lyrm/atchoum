#!/usr/bin/env python3
"""Summarize token usage per case and arm from a `claude plugin eval` run.

Usage: summarize.py RESULT_JSON

Reads each run's trace (kept with --keep-temp), copies it next to the result as
traces/<case>-<arm>-<n>.jsonl, writes tokens.json and prints a table of mean
tokens, cost and turns per case and arm.
"""

import json
import os
import shutil
import sys

FIELDS = ["input", "cache_write", "cache_read", "output", "cost_usd", "turns"]


def run_usage(trace):
    """Usage of the run's final `result` event, or None."""
    with open(trace) as f:
        for line in f:
            event = json.loads(line)
            if event.get("type") == "result":
                u = event.get("usage") or {}
                return {
                    "input": u.get("input_tokens", 0),
                    "cache_write": u.get("cache_creation_input_tokens", 0),
                    "cache_read": u.get("cache_read_input_tokens", 0),
                    "output": u.get("output_tokens", 0),
                    "cost_usd": event.get("total_cost_usd", 0.0),
                    "turns": event.get("num_turns", 0),
                }
    return None


def main(result_path):
    out_dir = os.path.dirname(os.path.abspath(result_path))
    traces_dir = os.path.join(out_dir, "traces")
    os.makedirs(traces_dir, exist_ok=True)
    with open(result_path) as f:
        result = json.load(f)

    summary = {}
    for case in result["cases"]:
        for arm, runs in case["arms"].items():
            usages = []
            for n, run in enumerate(runs):
                trace = run.get("tracePath")
                if not trace or not os.path.exists(trace):
                    continue
                shutil.copy(trace, os.path.join(traces_dir, f"{case['name']}-{arm}-{n}.jsonl"))
                usage = run_usage(trace)
                if usage:
                    usages.append(usage)
            if usages:
                mean = {k: sum(u[k] for u in usages) / len(usages) for k in FIELDS}
                summary.setdefault(case["name"], {})[arm] = {"runs": usages, "mean": mean}

    with open(os.path.join(out_dir, "tokens.json"), "w") as f:
        json.dump(summary, f, indent=2)

    header = f"{'case':<28} {'arm':<8} {'runs':>4} " + " ".join(f"{k:>11}" for k in FIELDS)
    print(header)
    for name, arms in summary.items():
        for arm, data in arms.items():
            m = data["mean"]
            cells = " ".join(
                f"{m[k]:>11.4f}" if k == "cost_usd" else f"{m[k]:>11.1f}" for k in FIELDS
            )
            print(f"{name:<28} {arm:<8} {len(data['runs']):>4} {cells}")
    print("(means per run; input, cache_write and cache_read are input tokens)")


if __name__ == "__main__":
    main(sys.argv[1])

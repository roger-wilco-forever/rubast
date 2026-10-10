#!/usr/bin/env python3
"""Compare arena reclamation with stage 21 using a native runtime harness on Linux."""

import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess

from synthetic import ROOT, run, version
from practical import digest


BASELINE = "b8978ebb0b1155a6b659b8ef3e3e5bf23f0e1515"
INSTRUMENTATION = """
impl Runtime {
    pub fn heap_stats(&self) -> (usize, usize) { (self.objects.len(), self.objects.len()) }
    pub fn collect_garbage(&mut self) -> usize { 0 }
}
"""


def build(destination, revision):
    runtime = destination / "rubast_runtime"
    if revision:
        paths = run(["git", "ls-tree", "-r", "--name-only", revision, "runtime/rubast_runtime/src",
                     "runtime/rubast_runtime/Cargo.toml"], cwd=ROOT, capture_output=True, text=True).stdout.splitlines()
        for path in paths:
            target = destination / path.removeprefix("runtime/")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(run(["git", "show", f"{revision}:{path}"], cwd=ROOT, capture_output=True).stdout)
        with (runtime / "src/lib.rs").open("a") as output:
            output.write(INSTRUMENTATION)
    else:
        shutil.copytree(ROOT / "runtime/rubast_runtime/src", runtime / "src")
        shutil.copyfile(ROOT / "runtime/rubast_runtime/Cargo.toml", runtime / "Cargo.toml")
    (destination / "src").mkdir()
    shutil.copyfile(ROOT / "benchmarks/memory_workload.rs", destination / "src/main.rs")
    (destination / "Cargo.toml").write_text(
        '[package]\nname = "memory_workload"\nversion = "0.1.0"\nedition = "2021"\n'
        '[dependencies]\nrubast_runtime = { path = "rubast_runtime" }\n')
    run(["cargo", "build", "--release", "--offline", "--quiet"], cwd=destination, capture_output=True)
    binary = destination / "target/release/memory_workload"
    files = [runtime / "Cargo.toml", *(runtime / "src").rglob("*.rs")]
    return binary, {str(path.relative_to(destination)): digest(path) for path in sorted(files)}


def check(result, engine, count, mode):
    assert result["checksum"] == count * 2 and result["root"] == 7, result
    expected = 1 if engine == "after" and mode == "discard" else count * 3 + 1
    assert result["retained_objects"] == expected, result
    if engine == "after" and mode == "discard":
        assert result["arena_slots"] <= 262, result
        assert all(live <= 262 and slots <= 262 for _, live, slots in result["checkpoints"]), result
    assert result["arena_slots"] >= result["retained_objects"], result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default=BASELINE)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    if output.exists():
        raise RuntimeError(f"results already exist: {output}")
    retained = ROOT / "target" / output.stem
    retained.mkdir(parents=True)
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    report = {"created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "native runtime harness, not compiled Ruby; unchanged analysis limits",
              "baseline_revision": arguments.baseline, "baseline_instrumentation": INSTRUMENTATION,
              "cpu": cpu, "cpu_model": next(line.split(":", 1)[1].strip() for line in
                                            Path("/proc/cpuinfo").read_text().splitlines()
                                            if line.startswith("model name")),
              "platform": platform.platform(), "rust": version(["rustc", "--version"]),
              "cargo": version(["cargo", "--version"]), "python": platform.python_version(),
              "build_flags": ["--release", "--offline"], "payload_bytes_per_cycle": 4096,
              "harness_sha256": digest(ROOT / "benchmarks/memory_workload.rs"),
              "runner_sha256": digest(Path(__file__)), "engines": {}, "cases": {}}
    binaries = {}
    for engine, revision in (("before", arguments.baseline), ("after", None)):
        destination = retained / engine
        destination.mkdir()
        binaries[engine], sources = build(destination, revision)
        report["engines"][engine] = {"binary": str(binaries[engine].relative_to(ROOT)),
                                     "binary_sha256": digest(binaries[engine]), "sources_sha256": sources}
    rng = random.Random(42)
    for mode, count in (("discard", 1000), ("discard", 10000), ("discard", 50000),
                        ("retain", 1000), ("retain", 10000)):
        samples = {engine: {"peak_rss_kib": [], "observations": []} for engine in binaries}
        for _ in range(3):
            order = list(binaries)
            rng.shuffle(order)
            for engine in order:
                rss = retained / "rss.txt"
                observed = run(["/usr/bin/time", "-f", "%M", "-o", str(rss), str(binaries[engine]),
                                str(count), mode], cwd=ROOT, capture_output=True, text=True)
                assert observed.stderr == "", observed.stderr
                result = json.loads(observed.stdout)
                check(result, engine, count, mode)
                peak = int(rss.read_text())
                assert peak > 0, peak
                samples[engine]["peak_rss_kib"].append(peak)
                samples[engine]["observations"].append(result)
        for sample in samples.values():
            sample["median_peak_rss_kib"] = statistics.median(sample["peak_rss_kib"])
        report["cases"][f"{mode}_{count}"] = samples
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(output)


if __name__ == "__main__":
    main()

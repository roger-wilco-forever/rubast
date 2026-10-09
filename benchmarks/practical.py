#!/usr/bin/env python3
"""Measure sustained application-shaped workloads and their release binaries on Linux."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import statistics
import subprocess
import time

from synthetic import ROOT, INPUTS, run, version


CASES = ("startup", "quote_requests", "invoice_summaries", "receipt_labels")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory():
    paths = [path for directory in ("app", "lib", "runtime/rubast_runtime/src", "benchmarks/workloads",
                                    "examples/workloads") for path in (ROOT / directory).rglob("*")
             if path.is_file() and path.suffix in (".rb", ".rs", ".json")]
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(paths)}


def check(commands, case):
    for data in INPUTS:
        observations = [subprocess.run(command, input=data, capture_output=True, cwd=ROOT) for command in commands.values()]
        reference = observations[0]
        for observed in observations:
            if (observed.stdout, observed.stderr, observed.returncode) != (reference.stdout, reference.stderr, 0):
                raise RuntimeError(f"CRuby comparison failed: {case}, stdin={data!r}")


def samples(commands, output, count, memory_count):
    times = {engine: [] for engine in commands}
    memory = {engine: [] for engine in commands}
    order = list(commands)
    rng = random.Random(42)
    input_file = output / "stdin.txt"
    input_file.write_bytes(INPUTS[-1])
    with input_file.open("rb") as stdin:
        for _ in range(3):
            for command in commands.values():
                stdin.seek(0)
                measure(command, stdin)
        for _ in range(count):
            rng.shuffle(order)
            for engine in order:
                stdin.seek(0)
                times[engine].append(measure(commands[engine], stdin))
        for _ in range(memory_count):
            rng.shuffle(order)
            for engine in order:
                stdin.seek(0)
                memory_file = output / "rss.txt"
                run(["/usr/bin/time", "-f", "%M", "-o", str(memory_file), *commands[engine]],
                    stdin=stdin, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
                peak = int(memory_file.read_text())
                if peak <= 0:
                    raise RuntimeError("GNU time returned no usable peak RSS")
                memory[engine].append(peak)
    return times, memory


def measure(command, stdin):
    start = time.perf_counter_ns()
    run(command, stdin=stdin, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=ROOT)
    return (time.perf_counter_ns() - start) / 1e6


def build(source, destination, ruby):
    binary = destination / "target/release/rubast_program"
    start = time.perf_counter()
    run(["bundle", "exec", ruby, str(ROOT / "bin/rubast"), "emit-rust", str(source), "-o", str(destination)],
        cwd=ROOT, capture_output=True)
    emit = time.perf_counter() - start
    start = time.perf_counter()
    run(["cargo", "build", "--release", "--offline", "--quiet"], cwd=destination, capture_output=True)
    compile_time = time.perf_counter() - start
    return binary, {"emit_s": emit, "cargo_s": compile_time, "total_s": emit + compile_time}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=21)
    parser.add_argument("--build-samples", type=int, default=3)
    parser.add_argument("--rss-samples", type=int, default=7)
    parser.add_argument("--compare", type=Path, help="Re-measure retained baseline binaries in the same sample pairs")
    args = parser.parse_args()
    if min(args.samples, args.build_samples, args.rss_samples) < 1:
        parser.error("sample counts must be positive")
    # shortcut: Linux process RSS and affinity, port these measurements when another OS is supported.
    if platform.system() != "Linux" or not Path("/usr/bin/time").is_file():
        parser.error("Linux and GNU /usr/bin/time are required")
    ruby = version(["ruby", "-rrbconfig", "-e", "puts RbConfig.ruby"])
    if version([ruby, "-e", "puts RUBY_VERSION"]) != (ROOT / ".ruby-version").read_text().strip():
        parser.error("the pinned CRuby version is required")
    original_affinity = sorted(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {original_affinity[0]})
    baseline = json.loads(args.compare.read_text()) if args.compare else None
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    source_inventory = inventory()
    if baseline and any(baseline["sources"][path] != value for path, value in source_inventory.items()
                        if path.startswith(("benchmarks/workloads/", "examples/workloads/"))):
        parser.error("baseline and current workload/dependency sources must match")
    report = {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "compiler_commit": version(["git", "rev-parse", "HEAD"]),
        "compiler_dirty": bool(version(["git", "status", "--porcelain"])),
        "runner_sha256": digest(Path(__file__)), "sources": source_inventory,
        "ruby": version([ruby, "--version"]), "rustc": version(["rustc", "--version"]),
        "cargo": version(["cargo", "--version"]), "python": platform.python_version(),
        "platform": platform.platform(),
        "cpu": next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith("model name")),
        "original_affinity": original_affinity, "affinity": sorted(os.sched_getaffinity(0)),
        "rubyopt": os.environ.get("RUBYOPT", ""), "rustflags": os.environ.get("RUSTFLAGS", ""),
        "cargo_target_dir": os.environ.get("CARGO_TARGET_DIR", ""),
        "samples": args.samples, "build_samples": args.build_samples,
        "rss_samples": args.rss_samples, "warmups": 3,
        "measured_stdin_bytes": len(INPUTS[-1]), "measured_stdin_sha256": hashlib.sha256(INPUTS[-1]).hexdigest(),
        "baseline_report": str(args.compare.resolve()) if baseline else None, "results": []}
    if report["cargo_target_dir"]:
        parser.error("unset CARGO_TARGET_DIR to measure fresh project builds")
    for case in CASES:
        source = ROOT / f"benchmarks/workloads/{case}.rb"
        builds = []
        for index in range(args.build_samples):
            print(f"Building {case} {index + 1}/{args.build_samples}...", flush=True)
            binary, observation = build(source, args.output / f"{case}-{index}", ruby)
            builds.append(observation)
            if index == 0:
                measured_binary = binary
        commands = {"ruby": [ruby, str(source)], "rust": [str(measured_binary)]}
        if baseline:
            previous = next(row for row in baseline["results"] if row["case"] == case)
            baseline_binary = Path(previous["binary"])
            if digest(baseline_binary) != previous["binary_sha256"]:
                raise RuntimeError(f"baseline binary changed: {case}")
            commands["baseline_rust"] = [str(baseline_binary)]
        check(commands, case)
        times, memory = samples(commands, args.output, args.samples, args.rss_samples)
        row = {"case": case, "iterations": 0 if case == "startup" else 1_000_000,
               "builds": builds, "binary": str(measured_binary), "binary_sha256": digest(measured_binary),
               "binary_bytes": measured_binary.stat().st_size, "wall_ms": times, "peak_rss_kib": memory,
               "matched_inputs": len(INPUTS)}
        report["results"].append(row)
        (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print(case, {engine: round(statistics.median(values), 3) for engine, values in times.items()}, "ms", flush=True)
    print(f"Raw measurements: {args.output / 'results.json'}")


if __name__ == "__main__":
    main()

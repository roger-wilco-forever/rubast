#!/usr/bin/env python3
"""Compare supported Ruby programs with their emitted release binaries on Linux."""

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


ROOT = Path(__file__).resolve().parents[1]
INPUTS = [b"", b"alternate\n", ("Ada λ " * 128 + "\n").encode()]


def source(case, batches, operations):
    if case == "startup":
        return "puts 0\n"
    steps = {
        "arithmetic": "value = (value * 17 + 23) % 100003",
        "conditions": "value = if value < 50000\n  value + 37\nelse\n  value - 41\nend",
        "methods": "value = step(value)",
        "fields": "step(value)",
        "strings": 'result = "#{value&.chomp}:INDEX:#{result == value}"',
    }
    helpers = {
        "methods": "def step(value)\n(value * 17 + 23) % 100003\nend",
        "fields": "def initialize\n@value = 17\nend\ndef step(value)\n@value = (@value * 17 + value) % 100003\nend",
    }
    body = "\n".join(steps[case].replace("INDEX", str(i)) for i in range(operations))
    result = {"fields": "@value", "strings": "result"}.get(case, "value")
    start = 'result = ""\n' if case == "strings" else ""
    argument = "input" if case == "strings" else "seed"
    calls = "\n".join(f"result = worker.work({argument})" for _ in range(batches))
    return f"""class SyntheticWork
{helpers.get(case, '')}
def work(value)
{start}{body}
{result}
end
end
input = gets
seed = if input == "alternate\\n"
29
else
17
end
worker = SyntheticWork.new
{calls}
puts result
"""


def run(command, **kwargs):
    try:
        return subprocess.run(command, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr.decode() if isinstance(error.stderr, bytes) else error.stderr)
        raise


def version(command):
    return run(command, capture_output=True, text=True).stdout.strip()


def measure(command, stdin):
    start = time.perf_counter_ns()
    run(command, stdin=stdin, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return (time.perf_counter_ns() - start) / 1e6


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "target/synthetic-benchmark")
    parser.add_argument("--batches", type=int, nargs="+", default=[20, 200])
    parser.add_argument("--operations", type=int, default=50)
    parser.add_argument("--samples", type=int, default=21)
    args = parser.parse_args()
    if min(*args.batches, args.operations, args.samples) < 1:
        parser.error("sizes and samples must be positive")
    # ponytail: Linux GNU time measures per-process peak RSS; port when another OS is needed.
    if platform.system() != "Linux" or not Path("/usr/bin/time").is_file():
        parser.error("Linux and GNU /usr/bin/time are required")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    ruby = version(["ruby", "-rrbconfig", "-e", "puts RbConfig.ruby"])
    report = {
        "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "compiler_commit": version(["git", "rev-parse", "HEAD"]),
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "ruby": version([ruby, "--version"]),
        "rustc": version(["rustc", "--version"]),
        "cargo": version(["cargo", "--version"]),
        "python": platform.python_version(),
        "platform": platform.platform(),
        "cpu": next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                    if line.startswith("model name")),
        "affinity": sorted(os.sched_getaffinity(0)),
        "rubyopt": os.environ.get("RUBYOPT", ""),
        "rustflags": os.environ.get("RUSTFLAGS", ""),
        "operations_per_batch": args.operations,
        "samples": args.samples,
        "warmups": 3,
        "rss_samples": 7,
        "measured_stdin_bytes": len(INPUTS[-1]),
        "measured_stdin_sha256": hashlib.sha256(INPUTS[-1]).hexdigest(),
        "results": [],
    }
    stdin_path = args.output / "stdin.txt"
    stdin_path.write_bytes(INPUTS[-1])
    for batches in args.batches:
        cases = ["arithmetic", "conditions", "methods", "fields", "strings"]
        if batches == args.batches[0]:
            cases.insert(0, "startup")
        for case in cases:
            size = 0 if case == "startup" else batches
            name = f"{case}-{size}"
            print(f"Building {name}...", flush=True)
            ruby_path = args.output / f"{name}.rb"
            ruby_path.write_text(source(case, batches, args.operations))
            project = args.output / name
            start = time.perf_counter()
            run(["bundle", "exec", ruby, str(ROOT / "bin/rubast"), "emit-rust", str(ruby_path), "-o", str(project)], cwd=ROOT)
            emit_s = time.perf_counter() - start
            start = time.perf_counter()
            run(["cargo", "build", "--release", "--offline", "--quiet"], cwd=project, capture_output=True)
            build_s = time.perf_counter() - start
            binary = project / "target/release/rubast_program"
            commands = {"ruby": [ruby, str(ruby_path)], "rust": [str(binary)]}
            for data in INPUTS:
                reference = run(commands["ruby"], input=data, capture_output=True)
                compiled = run(commands["rust"], input=data, capture_output=True)
                if (reference.stdout, reference.stderr, reference.returncode) != (compiled.stdout, compiled.stderr, compiled.returncode):
                    raise RuntimeError(f"CRuby comparison failed: {name}, stdin={data!r}")
            times = {engine: [] for engine in commands}
            rss = {engine: [] for engine in commands}
            order = list(commands)
            rng = random.Random(42)
            with stdin_path.open("rb") as stdin:
                for _ in range(3):
                    for command in commands.values():
                        stdin.seek(0)
                        measure(command, stdin)
                for _ in range(args.samples):
                    rng.shuffle(order)
                    for engine in order:
                        stdin.seek(0)
                        times[engine].append(measure(commands[engine], stdin))
                for _ in range(7):
                    rng.shuffle(order)
                    for engine in order:
                        stdin.seek(0)
                        memory_file = args.output / "rss.txt"
                        run(["/usr/bin/time", "-f", "%M", "-o", str(memory_file), *commands[engine]],
                            stdin=stdin, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        peak = int(memory_file.read_text())
                        if peak <= 0:
                            raise RuntimeError("GNU time returned no usable peak RSS")
                        rss[engine].append(peak)
            row = {"case": case, "batches": size, "emit_s": emit_s, "build_s": build_s,
                   "binary_bytes": binary.stat().st_size, "wall_ms": times, "peak_rss_kib": rss,
                   "matched_inputs": len(INPUTS),
                   "source_sha256": hashlib.sha256(ruby_path.read_bytes()).hexdigest()}
            report["results"].append(row)
            (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
            ruby_ms, rust_ms = (statistics.median(times[engine]) for engine in commands)
            print(f"{name}: Ruby {ruby_ms:.3f} ms, Rust {rust_ms:.3f} ms, {ruby_ms / rust_ms:.2f}x", flush=True)
    print(f"Raw measurements: {args.output / 'results.json'}")


if __name__ == "__main__":
    main()

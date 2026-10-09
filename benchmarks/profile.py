#!/usr/bin/env python3
"""Sample a retained release project's executable with Linux/glibc and GNU gprof."""

import argparse
import json
import os
from pathlib import Path
import platform
import resource
import shutil
import struct
import subprocess

from practical import digest
from synthetic import INPUTS, ROOT, run, version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=31)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("sample count must be positive")
    if platform.system() != "Linux" or platform.libc_ver()[0] != "glibc" or struct.calcsize("P") != 8:
        parser.error("64-bit Linux/glibc is required")
    args.project = args.project.resolve()
    args.output = args.output.resolve()
    baseline = args.project / "target/release/rubast_program"
    if not baseline.is_file() or args.output.is_relative_to(args.project):
        parser.error("a retained release project and a separate output directory are required")
    os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
    args.output.mkdir(parents=True, exist_ok=False)
    project = args.output / "project"
    shutil.copytree(args.project, project, ignore=shutil.ignore_patterns("target"))
    flags = "-C relocation-model=static -C link-arg=-no-pie -C debuginfo=1"
    env = dict(os.environ, RUSTFLAGS=flags)
    env.pop("CARGO_TARGET_DIR", None)
    run(["cargo", "build", "--release", "--offline", "--quiet"], cwd=project, env=env)
    sampler = args.output / "sample.so"
    run(["gcc", "-shared", "-fPIC", "-O2", "-Wall", "-Wextra", "-Werror",
         str(ROOT / "benchmarks/profile_cpu.c"), "-o", str(sampler), "-ldl"])
    binary = project / "target/release/rubast_program"
    for data in INPUTS:
        reference = subprocess.run([baseline], input=data, capture_output=True, check=True)
        result = subprocess.run([binary], input=data, capture_output=True, check=True)
        assert (result.stdout, result.stderr) == (reference.stdout, reference.stderr)
    env.update(LD_PRELOAD=str(sampler), GMON_OUT_PREFIX=str(args.output / "gmon"))
    cpu = []
    for _ in range(args.samples):
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        result = subprocess.run([binary], input=INPUTS[-1], capture_output=True, check=True, env=env)
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        assert (result.stdout, result.stderr) == (reference.stdout, reference.stderr)
        cpu.append(after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime)
    profiles = sorted(args.output.glob("gmon.*"))
    assert len(profiles) == args.samples, "Missing profiling records"
    sampled_seconds = 0
    for path in profiles:
        data = path.read_bytes()
        assert data[:4] == b"gmon" and data[20] == 0, "Unsupported gmon format"
        _, _, count, rate, _, _ = struct.unpack_from("=QQII15sc", data, 21)
        sampled_seconds += sum(struct.unpack_from(f"={count}H", data, 61)) / rate
    assert sampled_seconds > 0, "No usable CPU samples"
    report = run(["gprof", "-b", "-p", "--demangle=rust", str(binary), *map(str, profiles)],
                 capture_output=True, text=True).stdout
    (args.output / "flat-profile.txt").write_text(report)
    summary = {"project": str(args.project), "baseline_sha256": digest(baseline),
               "runner_sha256": digest(Path(__file__)), "rustc": version(["rustc", "--version"]),
               "platform": platform.platform(),
               "profile_binary_sha256": digest(binary), "sampler_sha256": digest(ROOT / "benchmarks/profile_cpu.c"),
               "rustflags": flags, "samples": args.samples, "affinity": sorted(os.sched_getaffinity(0)),
               "matched_inputs": len(INPUTS), "child_cpu_seconds": cpu,
               "executable_sample_seconds": sampled_seconds,
               "gprof": version(["gprof", "--version"]).splitlines()[0],
               "scope": "main executable only; shared-library samples are excluded"}
    (args.output / "profile.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(report)


if __name__ == "__main__":
    main()

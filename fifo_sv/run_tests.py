#!/usr/bin/env python3
"""Run only the FIFO/Bridge unit test with Verilator and a C++ compiler.

The delivered vectors are ready to use. --regenerate additionally needs gcc.
ModelSim users can run run_bridge.do directly without Python or C compilers.
The only instantiated DUT is du_tc_bridge. No other unit RTL is compiled.
"""
import argparse
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent


def run(command, logfile):
    result = subprocess.run(command, cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    logfile.write_text(result.stdout, encoding="utf-8")
    if result.returncode:
        print(result.stdout)
        raise SystemExit(result.returncode)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regenerate", action="store_true")
    parser.add_argument("--trace", action="store_true", help="also write VCD waveforms")
    args = parser.parse_args()
    logs = ROOT / "test_logs"
    logs.mkdir(exist_ok=True)
    exe = shutil.which("verilator") or shutil.which("verilator-cli")
    if exe:
        sim = [exe]
    elif importlib.util.find_spec("verilator"):
        sim = [sys.executable, "-m", "verilator"]
    else:
        parser.error("Install Verilator, or run run_bridge.do in ModelSim")

    with tempfile.TemporaryDirectory(prefix="bridge_sv_") as directory:
        build = Path(directory)
        if args.regenerate:
            cc = shutil.which("gcc")
            if not cc:
                parser.error("--regenerate requires gcc")
            generator = build / "generate_vectors"
            run([cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                 "c_reference/du_tc_bridge.c", "c_reference/generate_vectors.c",
                 "-o", str(generator)], logs / "c_build.log")
            print(run([str(generator), "vectors/bridge_vectors.txt"], logs / "c_model.log"), end="")

        top = "tb_bridge"
        # tensor_core_pkg contains shared types, not an instantiated TC.
        sources = ["tensor_core_pkg.sv", "du_tc_bridge_pkg.sv",
                   "du_tc_bridge.sv", "tb_bridge.sv"]
        target = build / top
        target.mkdir()
        # -O0 avoids a loop-exit counter constant-folding problem observed
        # in the available Verilator build. This changes simulator code
        # generation only; it does not alter RTL or hardware synthesis.
        # The PCH make override supports the tested Linux/GCC wheel build.
        command = sim + ["--binary", "--timing", "-O0", "-j", "2",
                         "-MAKEFLAGS", "CFG_CXXFLAGS_PCH_I=-include",
                         "--top-module", top, "--Mdir", str(target)]
        if args.trace:
            command.append("--trace")
        run(command + sources, logs / (top + "_build.log"))
        binary = [str(target / ("V" + top))]
        if args.trace:
            binary.append("+TRACE")
        output = run(binary, logs / (top + ".log"))
        if "BRIDGE RTL PASS:" not in output:
            raise SystemExit(f"Missing pass marker in {top}")
        print(output, end="")


if __name__ == "__main__":
    main()

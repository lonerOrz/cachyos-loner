#!/usr/bin/env python3
import argparse
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FLAKE_REF = f"path:{REPO_ROOT.resolve()}"


class Log:
    """Terminal logger with ANSI color formatting."""

    USE_COLOR = sys.stdout.isatty()
    RESET = "\033[0m"
    BOLD = "\033[1m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"
    DIM = "\033[2m"

    @classmethod
    def _fmt(cls, text, color, bold=False):
        if not cls.USE_COLOR:
            return text
        return f"{cls.BOLD if bold else ''}{color}{text}{cls.RESET}"

    @classmethod
    def c(cls, text, color, bold=False):
        return cls._fmt(text, color, bold)

    @classmethod
    def info(cls, text):
        print(f"{cls._fmt('[ INFO ]', cls.BLUE, bold=True)} {text}")

    @classmethod
    def skip(cls, text):
        print(f"{cls._fmt('[ SKIP ]', cls.YELLOW)} {text}")

    @classmethod
    def run(cls, text):
        print(f"{cls._fmt('[ RUN  ]', cls.CYAN, bold=True)} {text}")

    @classmethod
    def ok(cls, text):
        print(f"{cls._fmt('[  OK  ]', cls.GREEN, bold=True)} {text}")

    @classmethod
    def fail(cls, text):
        print(f"{cls._fmt('[ FAIL ]', cls.RED, bold=True)} {text}", file=sys.stderr)

    @classmethod
    def divider(cls):
        print(cls._fmt("─" * 65, cls.DIM))


def get_log_file(log_dir: Path, pkg_name: str):
    """Generate timestamped log path."""
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    return log_dir / f"{pkg_name}-{ts}.log"


def run_cmd(cmd, log_file=None, timeout=None):
    """Execute command with process group management and stream logging."""
    print(f"  │ Command: {Log.c(' '.join(cmd), Log.DIM)}")
    stdout_file = open(log_file, "w") if log_file else subprocess.DEVNULL

    try:
        env = os.environ.copy()
        env["GIT_EDITOR"] = "true"
        env["GIT_CONFIG_COUNT"] = "1"
        env["GIT_CONFIG_KEY_0"] = "commit.gpgSign"
        env["GIT_CONFIG_VALUE_0"] = "false"

        process = subprocess.Popen(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
            preexec_fn=os.setsid if os.name != "nt" else None,
        )

        for line in process.stdout:
            sys.stdout.write(f"  │ {line}")
            if stdout_file != subprocess.DEVNULL:
                stdout_file.write(line)

        ret = process.wait(timeout=timeout)
        if ret != 0:
            raise subprocess.CalledProcessError(ret, cmd)

    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        print(
            f"  │ {Log.c('Killing process group due to timeout/interrupt...', Log.RED)}"
        )
        if os.name != "nt":
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        else:
            process.kill()
        raise
    finally:
        if stdout_file != subprocess.DEVNULL:
            stdout_file.close()


def get_all_package_info():
    """Evaluate package metadata from package-info.nix."""
    expr_path = REPO_ROOT / ".github" / "scripts" / "package-info.nix"
    expr = f'import {expr_path} {{ flakeRef = "{FLAKE_REF}"; }}'
    try:
        result = subprocess.run(
            ["nix", "eval", "--expr", expr, "--json", "--impure"],
            capture_output=True,
            text=True,
            check=True,
            cwd=REPO_ROOT,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        Log.fail("Failed to get package info")
        print(e.stderr, file=sys.stderr)
        return {}


def run_update_script(script, pkg_dir, pkg_name, extra_args, log_file=None):
    """Execute custom update script command."""
    cmd = None
    if isinstance(script, str):
        parts = shlex.split(script)
        script_path_str = parts[0]
        path = Path(script_path_str)
        if not path.is_absolute():
            path = pkg_dir / path
        if path.exists():
            cmd = [str(path)] + parts[1:]
        elif shutil.which(script_path_str):
            cmd = parts
        else:
            raise RuntimeError(f"updateScript not found: {script}")
    elif isinstance(script, list):
        cmd = list(script)
    elif isinstance(script, dict):
        if "command" in script:
            cmd = list(script["command"])
        else:
            raise RuntimeError(f"Unsupported script dict: {script}")
    else:
        raise RuntimeError(f"Unsupported script type: {type(script)}")

    cmd += extra_args
    run_cmd(cmd, log_file)


def update_package(pkg_name, info, extra_args, log_dir) -> dict:
    """Perform update for a single package."""
    if not info.get("autoUpdate", True):
        Log.skip(f"{pkg_name} (autoUpdate=false)")
        return {"name": pkg_name, "status": "SKIP", "msg": "autoUpdate=false"}

    log_file = get_log_file(log_dir, pkg_name)
    args = info.get("updateArgs", []) + extra_args

    try:
        # Branch 1: execute Nix-native derivation updateScript.
        if info.get("isDerivation"):
            Log.run(f"Updating {pkg_name} via nix run...")
            cmd = ["nix", "run", f".#{pkg_name}.updateScript", "--"] + args
            run_cmd(cmd, log_file=log_file, timeout=3600)
            Log.ok(f"{pkg_name} derivation updated")
            return {"name": pkg_name, "status": "OK", "msg": "derivation updated"}

        # Branch 2: execute custom shell/python script.
        script = info.get("updateScript")
        is_nixpkgs_nix_update = False
        if script is not None:
            cmd_str = " ".join(script) if isinstance(script, list) else str(script)
            if "nix-update" in cmd_str:
                is_nixpkgs_nix_update = True

        if script is not None and not is_nixpkgs_nix_update:
            Log.run(f"Updating {pkg_name} via custom script...")
            run_update_script(script, REPO_ROOT, pkg_name, args, log_file)
            Log.ok(f"{pkg_name} script updated")
            return {"name": pkg_name, "status": "OK", "msg": "script updated"}

        # Branch 3: fallback to standard nix-update tool.
        if not shutil.which("nix-update"):
            Log.fail("nix-update not found in PATH")
            return {"name": pkg_name, "status": "FAIL", "msg": "nix-update missing"}

        Log.run(f"Updating {pkg_name} via nix-update...")
        cmd = ["nix-update", pkg_name, "--flake"] + args
        run_cmd(cmd, log_file)
        Log.ok(f"{pkg_name} nix-update done")
        return {"name": pkg_name, "status": "OK", "msg": "nix-update done"}

    except subprocess.CalledProcessError as e:
        Log.fail(f"{pkg_name} failed with exit={e.returncode} (log: {log_file})")
        return {"name": pkg_name, "status": "FAIL", "msg": f"exit={e.returncode}"}
    except Exception as e:
        Log.fail(f"{pkg_name} failed with error: {str(e)}")
        return {"name": pkg_name, "status": "FAIL", "msg": "error occurred"}


def print_summary(results):
    """Print global execution summary table."""
    if not results:
        return
    print()
    print(Log.c("=" * 65, Log.BOLD))
    print(Log.c("                      GLOBAL UPDATE SUMMARY", Log.BOLD))
    print(Log.c("=" * 65, Log.BOLD))

    for res in sorted(results, key=lambda x: x["status"]):
        name = res["name"].ljust(35)
        status = res["status"]
        msg = res["msg"]

        if status == "OK":
            status_str = Log.c("[  OK  ]", Log.GREEN, bold=True)
            icon = Log.c("✓", Log.GREEN, bold=True)
        elif status == "SKIP":
            status_str = Log.c("[ SKIP ]", Log.YELLOW)
            icon = Log.c("⚠", Log.YELLOW)
        else:
            status_str = Log.c("[ FAIL ]", Log.RED, bold=True)
            icon = Log.c("✗", Log.RED, bold=True)

        print(f" {icon}  {name} {status_str} ({msg})")
    print(Log.c("=" * 65, Log.BOLD))


def main():
    parser = argparse.ArgumentParser(
        description="Update CachyOS kernel and driver versions"
    )
    parser.add_argument("--package", help="Update only a specific package")
    parser.add_argument(
        "--commit", action="store_true", help="Commit changes after update"
    )
    parser.add_argument("--test", action="store_true", help="Run tests after update")
    parser.add_argument(
        "--build", action="store_true", help="Build package after update"
    )
    parser.add_argument(
        "--log-dir", default=".logs/update", help="Directory to store logs"
    )
    parser.add_argument(
        "extra_args", nargs="*", help="Extra arguments to pass to update scripts"
    )

    args = parser.parse_args()

    extra_args = []
    if args.commit:
        extra_args.append("--commit")
    if args.test:
        extra_args.append("--test")
    if args.build:
        extra_args.append("--build")
    extra_args += args.extra_args

    log_dir = REPO_ROOT / args.log_dir
    all_info = get_all_package_info()
    if not all_info:
        Log.fail("No packages found to evaluate")
        return

    results = []
    if args.package:
        if args.package in all_info:
            res = update_package(
                args.package, all_info[args.package], extra_args, log_dir
            )
            results.append(res)
        else:
            Log.fail(f"Unknown package: {args.package}")
    else:
        Log.info(f"Found {len(all_info)} packages to update")
        Log.divider()
        for name, info in sorted(all_info.items()):
            res = update_package(name, info, extra_args, log_dir)
            results.append(res)
            Log.divider()

        print_summary(results)


if __name__ == "__main__":
    main()

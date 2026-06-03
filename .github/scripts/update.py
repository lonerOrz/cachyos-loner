#!/usr/bin/env python3
import subprocess
import argparse
import shutil
import shlex
import json
import sys
import os
import signal
from pathlib import Path
from datetime import datetime

REPO_ROOT = Path(__file__).resolve().parents[2]
FLAKE_REF = f"path:{REPO_ROOT.resolve()}"


class Log:
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
    def c(cls, text, color_code, bold=False):
        if not cls.USE_COLOR:
            return text
        prefix = cls.BOLD if bold else ""
        return f"{prefix}{color_code}{text}{cls.RESET}"

    @classmethod
    def info(cls, text):
        print(f"{cls.c('[ INFO ]', cls.BLUE, bold=True)} {text}")

    @classmethod
    def skip(cls, text):
        print(f"{cls.c('[ SKIP ]', cls.YELLOW)} {text}")

    @classmethod
    def run(cls, text):
        print(f"{cls.c('[ RUN  ]', cls.CYAN, bold=True)} {text}")

    @classmethod
    def ok(cls, text):
        print(f"{cls.c('[  OK  ]', cls.GREEN, bold=True)} {text}")

    @classmethod
    def fail(cls, text):
        print(f"{cls.c('[ FAIL ]', cls.RED, bold=True)} {text}", file=sys.stderr)

    @classmethod
    def divider(cls):
        print(cls.c("─" * 65, cls.DIM))


def get_log_file(log_dir: Path, pkg_name: str):
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    return log_dir / f"{pkg_name}-{ts}.log"


def run_cmd(cmd, log_file=None, timeout=None):
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
            preexec_fn=os.setsid if os.name != "nt" else None
        )

        for line in process.stdout:
            sys.stdout.write(f"  │ {line}")
            if stdout_file != subprocess.DEVNULL:
                stdout_file.write(line)

        ret = process.wait(timeout=timeout)
        if ret != 0:
            raise subprocess.CalledProcessError(ret, cmd)

    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        print(f"  │ {Log.c('Killing process group due to timeout/interrupt...', Log.RED)}")
        if os.name != "nt":
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        else:
            process.kill()
        raise
    finally:
        if stdout_file != subprocess.DEVNULL:
            stdout_file.close()


def get_all_package_info():
    expr = f'''
      let
        flake = builtins.getFlake "{FLAKE_REF}";
        pkgs = flake.packages.x86_64-linux;
        packageInfo = name: let
          passthru = pkgs.${{name}}.passthru or {{}};
          updateScript = pkgs.${{name}}.updateScript or passthru.updateScript or null;
          isDrv = if updateScript == null then false
                  else (updateScript.type or "") == "derivation";
        in {{
          autoUpdate = (passthru.autoUpdate or true) != false;
          isDerivation = isDrv;
          updateScript = updateScript;
          updateArgs = passthru.updateArgs or [];
        }};
      in builtins.mapAttrs (name: _: packageInfo name) pkgs
    '''
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
        cmd = script
    elif isinstance(script, dict):
        if "command" in script:
            cmd = script["command"]
        else:
            raise RuntimeError(f"Unsupported script dict: {script}")
    else:
        raise RuntimeError(f"Unsupported script type: {type(script)}")

    cmd += extra_args
    run_cmd(cmd, log_file)


def update_package(pkg_name, info, extra_args, log_dir) -> dict:
    if not info.get("autoUpdate", True):
        Log.skip(f"{pkg_name} (autoUpdate=false)")
        return {"name": pkg_name, "status": "SKIP", "msg": "autoUpdate=false"}

    pkg_dir = (REPO_ROOT / "pkgs" / pkg_name).resolve()
    if not pkg_dir.exists():
        pkg_dir = REPO_ROOT

    log_file = get_log_file(log_dir, pkg_name)
    args = info.get("updateArgs", []) + extra_args

    try:
        if info.get("isDerivation"):
            Log.run(f"Updating {pkg_name} via nix run...")
            cmd = ["nix", "run", f".#{pkg_name}.updateScript", "--"] + args
            run_cmd(cmd, log_file=log_file, timeout=3600)
            Log.ok(f"{pkg_name} derivation updated")
            return {"name": pkg_name, "status": "OK", "msg": "derivation updated"}

        script = info.get("updateScript")
        is_nixpkgs_nix_update = False
        if script is not None:
            cmd_str = ' '.join(script) if isinstance(script, list) else str(script)
            if "nix-update" in cmd_str:
                is_nixpkgs_nix_update = True

        if script is not None and not is_nixpkgs_nix_update:
            Log.run(f"Updating {pkg_name} via custom script...")
            run_update_script(script, pkg_dir, pkg_name, args, log_file)
            Log.ok(f"{pkg_name} script updated")
            return {"name": pkg_name, "status": "OK", "msg": "script updated"}

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
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", help="Update only a specific package")
    parser.add_argument("--commit", action="store_true", help="Commit changes after update")
    parser.add_argument("--test", action="store_true", help="Run tests after update")
    parser.add_argument("--build", action="store_true", help="Build package after update")
    parser.add_argument("--log-dir", default=".logs/update", help="Directory to store logs")
    parser.add_argument("extra_args", nargs="*", help="Extra arguments to pass to update scripts")

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
            res = update_package(args.package, all_info[args.package], extra_args, log_dir)
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

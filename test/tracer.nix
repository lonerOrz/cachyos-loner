# Step 3: PKGBUILD prepare() Tracer
#
# Responsibilities:
# - Take sandbox from Step 2
# - Fake patch / make / scripts/config
# - Execute prepare()
# - Collect logs: patches.log, kconfig.log, make.log

{
  stdenvNoCC,
  pkgs,
  fetchFromGitHub,
  kernelVariant ? "linux-cachyos",
  linuxCachyosPkgbuild ? (import ./fetch.nix { inherit stdenvNoCC fetchFromGitHub; }),
}:

stdenvNoCC.mkDerivation {
  name = "linux-cachyos-pkgbuild-tracer";

  src = linuxCachyosPkgbuild;

  nativeBuildInputs = [
    pkgs.bash
    pkgs.tree
  ];

  dontBuild = false;

  buildPhase = ''
      runHook preBuild

      # 1. sandbox + logs
      mkdir -p sandbox/logs
      export TRACER_ROOT="$(pwd)/tracer"
      export LOGDIR="$TRACER_ROOT/logs"
      mkdir -p "$LOGDIR"

      # 2. PKGBUILD + SRCINFO
      cp $src/linux-cachyos/${kernelVariant}/PKGBUILD sandbox/PKGBUILD
      cp $src/linux-cachyos/${kernelVariant}/.SRCINFO sandbox/.SRCINFO

      # 3. kernel major version (e.g. 6.18)
      _major_version=$(grep -E 'pkgver = ' sandbox/.SRCINFO \
        | head -n1 | awk '{print $3}' | cut -d. -f1,2)

      # 4. kernel patches
      if [ ! -d "$src/kernel-patches/$_major_version" ]; then
        echo "kernel patches $_major_version not found" >&2
        exit 1
      fi

      cp -r $src/kernel-patches/$_major_version/* sandbox/ 2>/dev/null || true
      for d in all misc sched sched-dev; do
        if [ -d "$src/kernel-patches/$_major_version/$d" ]; then
          find "$src/kernel-patches/$_major_version/$d" -maxdepth 1 -type f \
            -exec cp {} sandbox/ \; 2>/dev/null || true
        fi
      done

      # 5. fake-bin (CRITICAL)
      mkdir -p fake-bin
      export PATH="$(pwd)/fake-bin:$PATH"

      # --- fake patch ---
      cat > fake-bin/patch <<EOF
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # 临时文件接 stdin
    tmp=\$(mktemp)
    cat > "\$tmp"
    # 计算 stdin 的 hash
    hash=\$(sha256sum "\$tmp" | awk '{print \$1}')
    {
      echo "[PATCH] args=\$*"
      echo "[PATCH] stdin-sha256=\$hash"
    } >> "''${LOGDIR}/patches.log"

    rm -f "\$tmp"
    exit 0
    EOF
      chmod +x fake-bin/patch

      # --- fake make ---
      cat > fake-bin/make <<EOF
    #!${pkgs.bash}/bin/bash
    set -e

    # Ignore stdenv driving make buildPhase/installPhase
    if [[ "\$*" == "buildPhase" || "\$*" == "installPhase" ]]; then
      exit 0
    fi
    echo "[MAKE] cwd=\$(pwd)" >> "''${LOGDIR}/make.log"
    echo "[MAKE] args=\$*" >> "''${LOGDIR}/make.log"
    # Minimal side-effects for kernel expectations
    for arg in "\$@"; do
      case "\$arg" in
        olddefconfig|defconfig)
          [ -f .config ] || echo "# fake .config" > .config
          ;;
      esac
    done
    exit 0
    EOF
      chmod +x fake-bin/make

      # --- fake yes (FIX Broken pipe) ---
      cat > fake-bin/yes <<EOF
    #!${pkgs.bash}/bin/bash
    # Print once, exit cleanly, never SIGPIPE
    echo ""
    exit 0
    EOF
      chmod +x fake-bin/yes

      # 6. srcdir
      export srcdir="$(pwd)/sandbox"
      touch "$srcdir/config"

      # 7. source PKGBUILD
      source sandbox/PKGBUILD

      if ! declare -f prepare >/dev/null; then
        echo "prepare() not found" >&2
        exit 1
      fi

      # 8. fake scripts/config
      mkdir -p "$srcdir/$_srcname/scripts"
      cat > "$srcdir/$_srcname/scripts/config" <<EOF
    #!${pkgs.bash}/bin/bash
    # Drain stdin to avoid pipe issues
    cat >/dev/null
    echo "[CONFIG] \$*" >> "''${LOGDIR}/kconfig.log"
    exit 0
    EOF
      chmod +x "$srcdir/$_srcname/scripts/config"

      # 9. trace prepare()
      cd "$srcdir"
      prepare

      runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r "$TRACER_ROOT/logs" $out/
    runHook postInstall
  '';
}

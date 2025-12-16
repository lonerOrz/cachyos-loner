# Step 2: Prepare sandbox environment and source PKGBUILD
#
# Responsibilities:
# - Take PKGBUILD from Step 1
# - Create a minimal workspace (sandbox)
# - Source the PKGBUILD to load functions, without executing prepare
#
# NO patch interception yet
# NO make interception

{
  stdenvNoCC,
  pkgs,
  fetchFromGitHub,
  linuxCachyosPkgbuild ? (import ./fetch.nix { inherit stdenvNoCC fetchFromGitHub; }),
}:

stdenvNoCC.mkDerivation {
  name = "linux-cachyos-pkgbuild-sandbox";

  # Use PKGBUILD as input
  src = linuxCachyosPkgbuild;

  nativeBuildInputs = [ pkgs.bash ];

  dontBuild = false;

  buildPhase = ''
    runHook preBuild

    # ────────────────
    # 1. 创建受控工作目录
    # ────────────────
    mkdir -p sandbox/src
    mkdir -p sandbox/logs

    # 复制 PKGBUILD 到 sandbox
    cp $src/PKGBUILD sandbox/PKGBUILD

    # 设置 makepkg 源目录语义
    export srcdir="$(pwd)/sandbox"

    # ────────────────
    # 2. source PKGBUILD
    # ────────────────
    echo "Sourcing PKGBUILD..."
    source sandbox/PKGBUILD

    # 检查 prepare 函数是否存在
    if ! declare -f prepare >/dev/null 2>&1; then
      echo "Error: prepare() function not found in PKGBUILD" >&2
      exit 1
    fi
    echo "prepare() function successfully loaded (not executed)"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    # 输出 sandbox，供后续步骤使用
    cp -r sandbox $out/
    runHook postInstall
  '';
}

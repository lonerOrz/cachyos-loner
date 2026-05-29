# 将 shared/ 和 tools/ 代码内联到调用处

## Goal

取消对 `shared/` 和 `tools/` 目录的依赖，将其代码 inline 到各调用位置（flake.nix、overlays/default.nix、dev-shells.nix），然后删除这两个目录。

## 引用关系

| 源文件 | 引用的 shared/tools 路径 | 用途 |
|--------|--------------------------|------|
| `flake.nix:25` | `./shared/utils.nix` | `utils.applyOverlay`, `inherit utils` |
| `overlays/default.nix:24` | `../shared/utils.nix` | `projectUtils` (3 个函数 + 透传给 pkgs/) |
| `dev-shells.nix:39` | `./shared/recursion-helper.nix` | `recursionHelper` |
| `dev-shells.nix:46` | `./tools/builder` | `builder` |
| `dev-shells.nix:50` | `./tools/dry-build` | `dry-build` |
| `dev-shells.nix:57` | `./tools/eval` | `evaluated` |
| `dev-shells.nix:62` | `./tools/bumper` | `bumper` |

## Inline 策略

- **flake.nix**: 将 `shared/utils.nix` 的整个 `rec` 集直接定义为 `let utils = rec { ... }`
- **overlays/default.nix**: 将 `shared/utils.nix` 的整个 `rec` 集内联为 `projectUtils`
- **dev-shells.nix**: 将所有 `callPackage ./shared/...` 和 `callPackage ./tools/...` 替换为内联表达式
  - `recursion-helper.nix` → 内联 let binding
  - `tools/dry-build` → 内联表达式
  - `tools/eval` → 内联表达式
  - `tools/bumper` → 内联表达式 + `lib.sh` 的 bash 函数内联到 script
  - `tools/builder` → 内联表达式 + `lib.sh` 的 bash 函数内联到 script
- 完成后删除 `shared/` 和 `tools/` 目录
- **`overlays/default.nix`** → 内联到 `flake.nix` 的 let 中，删除 `overlays/` 目录
- **`dev-shells.nix`** → 内联到 `flake.nix` 的 let 中，删除 `dev-shells.nix`
- **`formatter.nix`** → 内联到 `flake.nix` 的 outputs 中，删除 `formatter.nix`
- **`garnix.yaml`** → 直接删除

## Acceptance Criteria

- [ ] `flake.nix` 不再 import `./shared/`、`./dev-shells.nix`、`./formatter.nix`、`./overlays`
- [ ] `overlays/default.nix` 不再 import `../shared/`
- [ ] `dev-shells.nix` 不再 `callPackage` shared/ 或 tools/
- [ ] `shared/` `tools/` `overlays/` `dev-shells.nix` `formatter.nix` `garnix.yaml` 全部删除
- [ ] `nix flake check` 通过

## Out of Scope

- 不修改 `pkgs/` 下的任何文件（它们继续通过 `projectUtils` 参数获取 utility 函数）
- 不修改 flake.lock

## Technical Notes

- `utils.nix`（184 行）需要完整内联到两个位置（flake.nix 和 overlays/default.nix），因为 `projectUtils` 作为完整 attrset 透传给下游 package
- `recursion-helper.nix`（94 行）内联到 dev-shells.nix
- tools 中的 `lib.sh`（builder 有 240 行 bash，bumper 有 62 行 bash）需要转为内联的 bash heredoc/字符串

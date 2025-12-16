step:
[x] update.nix 在获取到 CachyOS/linux-cachyos 仓库后，不再忽略 PKGBUILD，而是将其视为一个重要的输入。
[x] 创建一个临时的、受控的沙箱构建环境。
[x] 在这个环境中，source 这个 PKGBUILD 文件（它本质上是一个 shell 脚本）。
[ ] 用一个“假的”patch 命令替换掉系统真正的 patch 命令。这个假命令不执行打补丁的操作，而是仅仅记录“哪个补丁文件被调用了”。
[ ] 同样，可以对 scripts/config 进行包装，来记录所有被应用的 kconfig 参数。
[ ] 执行 PKGBUILD 中的 prepare() 函数。
[ ] 函数执行完毕后，从我们“假的”命令中收集记录下来的信息——也就是一份精确的、上游作者意图应用的补丁列表和配置列表。

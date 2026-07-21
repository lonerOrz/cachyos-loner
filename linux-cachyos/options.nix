{ lib }:

let
  # 枚举型 tunable：值 → scripts/config flag 列表
  enumFlags = {
    mArch = {
      NATIVE = [
        "-d GENERIC_CPU"
        "-d MZEN4"
        "-e X86_NATIVE_CPU"
      ];
      ZEN4 = [
        "-d GENERIC_CPU"
        "-e MZEN4"
        "-d X86_NATIVE_CPU"
      ];
    };
    cpuSched = {
      cachyos = [
        "-e SCHED_BORE"
        "-e SCHED_CLASS_EXT"
      ];
      "sched-ext" = [ "-e SCHED_CLASS_EXT" ];
      bore = [ "-e SCHED_BORE" ];
      hardened = [ "-e SCHED_BORE" ];
      bmq = [
        "-e SCHED_ALT"
        "-e SCHED_BMQ"
      ];
      eevdf = [ ];
      rt = [ "-e PREEMPT_RT" ];
      "rt-bore" = [
        "-e SCHED_BORE"
        "-e PREEMPT_RT"
      ];
    };
    tickRate = {
      periodic = [
        "-d NO_HZ_IDLE"
        "-d NO_HZ_FULL"
        "-d NO_HZ"
        "-d NO_HZ_COMMON"
        "-e HZ_PERIODIC"
      ];
      idle = [
        "-d HZ_PERIODIC"
        "-d NO_HZ_FULL"
        "-e NO_HZ_IDLE"
        "-e NO_HZ"
        "-e NO_HZ_COMMON"
      ];
      full = [
        "-d HZ_PERIODIC"
        "-d NO_HZ_IDLE"
        "-d CONTEXT_TRACKING_FORCE"
        "-e NO_HZ_FULL_NODEF"
        "-e NO_HZ_FULL"
        "-e NO_HZ"
        "-e NO_HZ_COMMON"
        "-e CONTEXT_TRACKING"
      ];
    };
    preempt = {
      full = [
        "-e PREEMPT"
        "-d PREEMPT_LAZY"
      ];
      lazy = [
        "-d PREEMPT"
        "-e PREEMPT_LAZY"
      ];
      server = [
        "-e PREEMPT_NONE"
        "-d PREEMPT_LAZY"
        "-d PREEMPT"
      ];
    };
    hugePages = {
      always = [
        "-d TRANSPARENT_HUGEPAGE_MADVISE"
        "-e TRANSPARENT_HUGEPAGE_ALWAYS"
      ];
      madvise = [
        "-d TRANSPARENT_HUGEPAGE_ALWAYS"
        "-e TRANSPARENT_HUGEPAGE_MADVISE"
      ];
    };
    lto = {
      thin = [ "-e LTO_CLANG_THIN" ];
      "thin-dist" = [ "-e LTO_CLANG_THIN_DIST" ];
      full = [ "-e LTO_CLANG_FULL" ];
      none = [ "-e LTO_NONE" ];
    };
  };

  # 布尔型 toggle：开启 → flag 列表
  toggleFlags = {
    ccHarder = [
      "-d CC_OPTIMIZE_FOR_PERFORMANCE"
      "-e CC_OPTIMIZE_FOR_PERFORMANCE_O3"
    ];
    autoFDO = [ "-e AUTOFDO_CLANG" ];
    propeller = [ "-e PROPELLER_CLANG" ];
    withDAMON = [
      "-e DAMON"
      "-e DAMON_VADDR"
      "-e DAMON_DBGFS"
      "-e DAMON_SYSFS"
      "-e DAMON_PADDR"
      "-e DAMON_RECLAIM"
      "-e DAMON_LRU_SORT"
    ];
    withNTSync = [ "-m NTSYNC" ];
    withPrivateHDR = [ "-e AMD_PRIVATE_COLOR" ];
    useKCFI = [
      "-e ARCH_SUPPORTS_CFI_CLANG"
      "-e CFI_CLANG"
      "-e CFI_AUTO_DEFAULT"
    ];
  };

  qrCodePanic = [
    "--set-str DRM_PANIC_SCREEN qr_code"
    "-e DRM_PANIC_SCREEN_QR_CODE"
    "--set-str DRM_PANIC_SCREEN_QR_CODE_URL https://panic.archlinux.org/panic_report#"
    "--set-val CONFIG_DRM_PANIC_SCREEN_QR_VERSION 40"
  ];

  # 恒开前缀
  base = [
    "--set-val NR_CPUS 320"
    "-e LRU_GEN"
    "-e LRU_GEN_ENABLED"
    "-d LRU_GEN_STATS"
    "-e PER_VMA_LOCK"
    "-d PER_VMA_LOCK_STATS"
    "-d CONFIG_SECURITY_TOMOYO"
  ]
  ++ qrCodePanic;

  bbrFlags = [
    "-m TCP_CONG_CUBIC"
    "-d DEFAULT_CUBIC"
    "-e TCP_CONG_BBR"
    "-e DEFAULT_BBR"
    "--set-str DEFAULT_TCP_CONG bbr"
    "-m NET_SCH_FQ_CODEL"
    "-e NET_SCH_FQ"
    "-d DEFAULT_FQ_CODEL"
    "-e DEFAULT_FQ"
    "--set-str DEFAULT_NET_SCH fq"
  ];

  debugOffFlags = [
    "-d DEBUG_INFO"
    "-d DEBUG_INFO_BTF"
    "-d DEBUG_INFO_DWARF4"
    "-d DEBUG_INFO_DWARF5"
    "-d PAHOLE_HAS_SPLIT_BTF"
    "-d DEBUG_INFO_BTF_MODULES"
    "-d SLUB_DEBUG"
    "-d PM_DEBUG"
    "-d PM_ADVANCED_DEBUG"
    "-d PM_SLEEP_DEBUG"
    "-d ACPI_DEBUG"
    "-d SCHED_DEBUG"
    "-d LATENCYTOP"
    "-d DEBUG_PREEMPT"
  ];

  # ticksHz 由数值驱动，非查表
  ticksHzFlags =
    n:
    if n == 300 then
      [
        "-e HZ_300"
        "--set-val HZ 300"
      ]
    else
      [
        "-d HZ_300"
        "--set-val HZ ${toString n}"
        "-e HZ_${toString n}"
      ];

  # mArch 特例：GENERIC_V[1-4] 需解析版本号
  archFlags =
    m:
    if m == null then
      [ ]
    else if m == "NATIVE" then
      enumFlags.mArch.NATIVE
    else if m == "ZEN4" then
      enumFlags.mArch.ZEN4
    else
      let
        m' = builtins.match "GENERIC_V([1-4])" m;
      in
      if m' == null then
        throw "unsupported mArch: ${m}"
      else
        [
          "-e GENERIC_CPU"
          "-d MZEN4"
          "-d X86_NATIVE_CPU"
          "--set-val X86_64_VERSION ${builtins.elemAt m' 0}"
        ];

  buildPkgbuildConfig =
    c:
    let
      cpuSchedFlags = enumFlags.cpuSched.${c.cpuSched};
      ltoFlags = enumFlags.lto.${c.useLTO};
      tickRateFlags = enumFlags.tickRate.${c.tickRate};
      preemptFlags = enumFlags.preempt.${c.preempt};
      hugePagesFlags = enumFlags.hugePages.${c.hugePages};
      perGovFlags = lib.optionals (c.perGov or false) [
        "-d CPU_FREQ_DEFAULT_GOV_SCHEDUTIL"
        "-e CPU_FREQ_DEFAULT_GOV_PERFORMANCE"
      ];
      debugOff = lib.optionals (
        (c.withoutDebug or false)
        && !(builtins.elem (c.cpuSched or "cachyos") [
          "sched-ext"
          "cachyos"
        ])
      ) debugOffFlags;
    in
    base
    ++ lib.optional (c.basicCachy or true) "-e CACHY"
    ++ (archFlags c.mArch)
    ++ cpuSchedFlags
    ++ perGovFlags
    ++ lib.optionals (c.tcpBBR3 or false) bbrFlags
    ++ ltoFlags
    ++ ticksHzFlags (c.ticksHz or 500)
    ++ tickRateFlags
    ++ preemptFlags
    ++ hugePagesFlags
    ++ lib.optionals (c.ccHarder or false) toggleFlags.ccHarder
    ++ lib.optionals (c.autoFDO or false) toggleFlags.autoFDO
    ++ lib.optionals (c.propeller or false) toggleFlags.propeller
    ++ lib.optionals (c.withDAMON or false) toggleFlags.withDAMON
    ++ lib.optionals (c.withNTSync or false) toggleFlags.withNTSync
    ++ lib.optionals (c.withPrivateHDR or false) toggleFlags.withPrivateHDR
    ++ lib.optionals (c.useKCFI or false) toggleFlags.useKCFI
    ++ debugOff;
in
{
  inherit buildPkgbuildConfig;
}

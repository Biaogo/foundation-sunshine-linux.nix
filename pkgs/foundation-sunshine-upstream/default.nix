# foundation-sunshine-upstream — the re-forked Linux build.
#
# Lineage: LizardByte/Sunshine `upstream/master` + this fork's Linux patch series, i.e. the tree of
# the fork repo's `refork/linux` branch (tag `v2026.09.25-linux`). Unlike ./foundation-sunshine
# (the AlkaidLab-based lineage), the source here is shaped like upstream Sunshine, so the
# derivation mirrors nixpkgs' `sunshine` package and adds what upstream's 2026-09 tree needs
# (libvirtualhid/libdisplaydevice/lizardbyte-common/glad submodules, SUNSHINE_SYSTEM_VULKAN_HEADERS,
# the prebuilt ffmpeg from LizardByte/build-deps, ...).
#
# Verified locally (CPU and CUDA variants): configure + compile + link + install; a real Moonlight
# session streams through KWin ScreenCast with the krfb virtual display created by the prep hooks
# (see the branch's docs/upstream-linux-resync.md).
#
# The pin block (`let` version/rev + the fetchFromGitHub hash) is machine-rewritten by
# scripts/update-pin.py — keep those line shapes.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  buildNpmPackage,
  nodejs_26,
  makeWrapper,
  autoPatchelfHook,
  autoAddDriverRunpath,
  cmake,
  ninja,
  pkg-config,
  python3,
  wayland-scanner,
  shaderc,

  # build/runtime libraries (linux)
  boost,
  curl,
  glib,
  miniupnpc,
  nlohmann_json,
  openssl,
  libopus,
  avahi,
  libevdev,
  libpulseaudio,
  libx11,
  libxcb,
  libxfixes,
  libxrandr,
  libxtst,
  libxi,
  libdrm,
  wayland,
  libffi,
  libcap,
  pcre2,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxdmcp,
  libxkbcommon,
  libepoxy,
  libglvnd,
  libva,
  libvdpau,
  numactl,
  libgbm,
  amf-headers,
  svt-av1,
  vulkan-loader,
  vulkan-headers,
  pipewire,
  libappindicator,
  libnotify,

  cudaPackages ? null,
}:
let
  version = "2026.09.29";
  rev = "2b309e616569e336918334032445c94cc33e74d5"; # tag: v2026.09.29-linux

  # Upstream's cmake downloads a prebuilt ffmpeg from LizardByte/build-deps at configure time; the
  # tag has to match the commit pinned in third-party/build-deps.
  ffmpegPrebuilt = fetchzip {
    url = "https://github.com/LizardByte/build-deps/releases/download/v2026.910.121303/Linux-x86_64-ffmpeg.tar.gz";
    hash = "sha256-1S57XfkJa+qEYQLmifWyT9ul0SASFhSk1lkk2timnOY=";
  };

  stdenv' = if cudaPackages != null then cudaPackages.backendStdenv else stdenv;
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "foundation-sunshine-upstream";
  inherit version;

  src = fetchFromGitHub {
    owner = "Biaogo";
    repo = "foundation-sunshine-linux";
    inherit rev;
    hash = "sha256-noMkfeGf+9G4ExzKv0i/7V3pQPRo/jtcIVi2eqOcJdE=";
    # Upstream's build consumes several submodules (glad, libdisplaydevice, libvirtualhid,
    # lizardbyte-common, moonlight-common-c with its nested enet/nanors, ...). Fetching the tree
    # with its gitlinks in one go is what nixpkgs' sunshine package does.
    fetchSubmodules = true;
  };

  # Web UI (vite 8 / rolldown) — needs node >= 26.7.
  ui = buildNpmPackage {
    pname = "foundation-sunshine-ui";
    inherit (finalAttrs) version src;
    nodejs = nodejs_26;
    npmDepsHash = "sha256-/rAr2PEIQmKUUkFdZQfkfn92aYTHDrGfRdpNP8Kyw2Q=";
    npmDepsFetcherVersion = 2;

    installPhase = ''
      runHook preInstall
      # npmConfigHook can leave result* convenience symlinks behind; copying those into $out trips
      # the noBrokenSymlinks hook (their openssl dev target is absent from the build closure).
      rm -f result result-* dev result-dev
      mkdir -p "$out"
      cp -a . "$out"/
      runHook postInstall
    '';
  };

  postPatch = ''
    # Build the web UI separately; do not look for npm at configure time
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail 'find_program(NPM npm REQUIRED)' ""

    # NixOS has no FHS systemd/udev discovery; the install dirs are passed via cmakeFlags below
    substituteInPlace cmake/packaging/linux.cmake \
      --replace-fail 'find_package(Systemd)' "" \
      --replace-fail 'find_package(Udev)' ""
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    makeWrapper
    # glad's generator needs Jinja2 + setuptools at configure time; GLAD_SKIP_PIP_INSTALL=ON stops
    # cmake from pip-installing them.
    (python3.withPackages (ps: [
      ps.jinja2
      ps.setuptools
    ]))
    wayland-scanner
    shaderc # glslc, needed at configure time for the shader compilation
    autoPatchelfHook
  ]
  ++ lib.optionals (cudaPackages != null) [
    autoAddDriverRunpath
    cudaPackages.cuda_nvcc
    (lib.getDev cudaPackages.cuda_cudart)
  ];

  buildInputs = [
    boost
    boost.dev # BoostConfig.cmake lives in the dev output (upstream finds Boost in CONFIG mode)
    curl
    miniupnpc
    nlohmann_json
    openssl
    libopus
    avahi
    libevdev
    libpulseaudio
    libx11
    libxcb
    libxfixes
    libxrandr
    libxtst
    libxi
    libdrm
    wayland
    libffi
    libcap
    pcre2
    libuuid
    libselinux
    libsepol
    libthai
    libdatrie
    libxdmcp
    libxkbcommon
    libepoxy
    libva
    libvdpau
    numactl
    libgbm
    amf-headers
    svt-av1
    vulkan-loader
    vulkan-headers
    pipewire
    glib # GIO for the KWin/portal capture backends
    libappindicator
    libnotify
  ]
  ++ lib.optionals (cudaPackages != null) [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_cudart
  ];

  # Sunshine dlopens libvulkan (encoder probing) and libEGL/libGL (EGL import of captured
  # DMA-BUFs); without libglvnd the binary logs "Failed to load EGL library symbols".
  runtimeDependencies = [
    avahi
    libgbm
    libxrandr
    libxcb
    libglvnd
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BOOST_USE_STATIC" false) # nixpkgs' boost ships shared libraries only
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeBool "BUILD_TESTS" false)
    (lib.cmakeBool "BUILD_WERROR" false)
    (lib.cmakeBool "GLAD_SKIP_PIP_INSTALL" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" (cudaPackages != null))
    (lib.cmakeBool "SUNSHINE_ENABLE_WAYLAND" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_X11" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_DRM" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_VAAPI" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_KWIN" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_PORTAL" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_VULKAN" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_TRAY" false)
    (lib.cmakeBool "SUNSHINE_SYSTEM_NLOHMANN_JSON" true)
    (lib.cmakeBool "SUNSHINE_SYSTEM_VULKAN_HEADERS" true)
    (lib.cmakeFeature "FFMPEG_PREPARED_BINARIES" "${ffmpegPrebuilt}")
    (lib.cmakeBool "UDEV_FOUND" true)
    (lib.cmakeBool "SYSTEMD_FOUND" true)
    (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
    (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
    (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
    (lib.cmakeFeature "SUNSHINE_EXECUTABLE_PATH" "${placeholder "out"}/bin/sunshine")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "Biaogo")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://github.com/Biaogo/foundation-sunshine-linux")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/Biaogo/foundation-sunshine-linux/issues")
  ];

  env = {
    # build_version.cmake only honours BUILD_VERSION when BRANCH == "master"
    BUILD_VERSION = finalAttrs.version;
    BRANCH = "master";
    COMMIT = lib.substring 0 8 rev;
  };

  # Place the prebuilt web UI where cmake's install step expects it
  # (${CMAKE_BINARY_DIR}/assets/web, per cmake/packaging/common.cmake).
  preBuild = ''
    mkdir -p assets
    cp -r --no-preserve=mode,ownership "${finalAttrs.ui}/build/assets/web" assets/web
  '';

  # Build only the binary; the default `all` target includes the web-ui custom target, which needs
  # npm at build time (the UI is prebuilt above; structuredAttrs does not splice buildFlags into the
  # ninja invocation, hence the explicit buildPhase).
  buildPhase = ''
    runHook preBuild
    cmake --build . --target sunshine -j $NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cmake --install .
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/sunshine" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        vulkan-loader
        libglvnd
      ]}
  '';

  meta = {
    description = "Self-hosted game stream host for Moonlight (upstream-based Linux build with virtual display support)";
    longDescription = ''
      LizardByte/Sunshine (upstream master) plus this fork's Linux patch series: a
      client-selectable dynamic virtual display (krfb-virtualmonitor driven by the
      global_prep_cmd hooks), the /displays endpoint a Moonlight client uses to list and pick
      displays, per-session display selection, and the capability/permission fixes the
      linger + SDDM setup needs. Capture backends: KWin ScreenCast, XDG portal, KMS, Wayland,
      X11; NVENC (CUDA), VAAPI and Vulkan Video encoders.
    '';
    homepage = "https://github.com/Biaogo/foundation-sunshine-linux";
    license = lib.licenses.gpl3Only;
    mainProgram = "sunshine";
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ ];
  };
})

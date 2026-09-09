# Foundation Sunshine — qiin2333/foundation-sunshine fork of LizardByte/Sunshine,
# built for Linux from the linux-support branch of Biaogo/foundation-sunshine-linux.
#
# Upstream only ships Windows binaries, so the Linux support branch restores the
# deleted Linux packaging templates, fixes the Linux build, and backports the
# KWin ScreenCast capture backend (upstream PR #5009).
#
# Every gitlink the Linux build consumes is fetched separately (pinned to the
# gitlinks recorded in the source repo); Windows-only submodules (nvapi, AMF,
# ViGEmClient, build-deps, control-panel, flatpak deps, googletest, doxyconfig)
# are deliberately skipped. AMF headers are taken from nixpkgs instead of the
# AMF submodule: the pin equals AMF v1.5.2, which nixpkgs ships as amf-headers.
#
# The prebuilt ffmpeg/boost artifacts from AlkaidLab/foundation-build-deps are
# used via FFMPEG_PREPARED_BINARIES (same trick as nixpkgs' sunshine package):
# the fork's cmake needs libavcodec/libcbs/libhdr10plus/libSvtAv1Enc static
# libs from there and cannot do network I/O at build time.
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchgit,
  fetchzip,
  makeWrapper,
  autoPatchelfHook,
  autoAddDriverRunpath,
  cmake,
  ninja,
  pkg-config,
  buildNpmPackage,
  nodejs_26,
  coreutils,
  cudaPackages ? null,

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
  pcre,
  pcre2,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxdmcp,
  libxkbcommon,
  libepoxy,
  libva,
  libvdpau,
  libglvnd,
  libgbm,
  numactl,
  amf-headers,
  svt-av1,
  vulkan-loader,
  pipewire,
  libappindicator,
  libnotify,
  wayland-scanner,
}:
let
  version = "2026.09.07";
  rev = "33051b67a353dc39ae8a419bf5f651c1c4da220d"; # tag: v2026.09.07-linux

  # Gitlink pins recorded in the source repo (git ls-tree <rev> third-party).
  # moonlight-common-c needs fetchSubmodules: it carries a nested `enet`
  # gitlink that cmake add_subdirectory's directly.
  submodules = {
    inputtino = fetchFromGitHub {
      owner = "games-on-whales";
      repo = "inputtino";
      rev = "d28ec79eb63324e68d73a7de22bcb5ff0a6f6bf8";
      hash = "sha256-xzDsJggQVX5e1twwNvqw5hDXei6OMYA4s5zU4zfp/H0=";
    };
    moonlight-common-c = fetchFromGitHub {
      owner = "qiin2333";
      repo = "moonlight-common-c";
      rev = "31a2a4589ea926988a08ca508bb317fbfbe2a177";
      hash = "sha256-XiF13Ds/3tiAS37IOfGmtGTkdXneeSM8eKLVnGfp04A=";
      fetchSubmodules = true;
    };
    moonlight-audio-haptics = fetchFromGitHub {
      owner = "AlkaidLab";
      repo = "moonlight-audio-haptics";
      rev = "21aae5018e36397d45b3dffff4005c952592ec0b";
      hash = "sha256-tK75I81TgZaid5pl8JClntmZAybNZ7F032UD6Ket6Bc=";
    };
    nanors = fetchFromGitHub {
      owner = "sleepybishop";
      repo = "nanors";
      rev = "57ee5e921bd5047bca7ad377b181b7c28ea09731";
      hash = "sha256-Bkp16K67skiaXXKUUVA1lXUfnRPP2FCSrASmjomryF4=";
    };
    Simple-Web-Server = fetchgit {
      url = "https://gitlab.com/eidheim/Simple-Web-Server.git";
      rev = "546895a93a29062bb178367b46c7afb72da9881e";
      hash = "sha256-sIuZUqpK8eiPs1wIlE8hJgtynEoYpLxMaWxQGviifME=";
    };
    TPCircularBuffer = fetchFromGitHub {
      owner = "michaeltyson";
      repo = "TPCircularBuffer";
      rev = "cc520397504bb72bc6df79ff03eb72988a6dc50d";
      hash = "sha256-GYTzjJwT0E0+gVH2oseHpc0HqrdyZkP1LZPiYc8+G+I=";
    };
    tray = fetchFromGitHub {
      owner = "LizardByte";
      repo = "tray";
      rev = "9a1c9540f10f3847c54af30d5060345e8e7634ed";
      hash = "sha256-+1fIBFVlzpPNdsypkOftOvK0owIs7RFjZSkUupeuAYA=";
    };
    wayland-protocols = fetchFromGitHub {
      owner = "LizardByte-infrastructure";
      repo = "wayland-protocols";
      rev = "1f5f2b50ea2d88a9cc307902de2c8ed6b6d86f7d";
      hash = "sha256-bOwGd36IZW8DuARkAFTGkddz0o52jJ2AEH0gbD9JaHA=";
    };
    wlr-protocols = fetchgit {
      url = "https://gitlab.freedesktop.org/wlroots/wlr-protocols.git";
      rev = "a741f0ac5d655338a5100fc34bc8cec87d237346";
      hash = "sha256-qdimOBtxgrEQDhOWHTWDRVC6p7gl8DjTgtiC+YNLEgs=";
    };
    # KWin capture backend (backported upstream PR #5009) protocols
    plasma-wayland-protocols = fetchFromGitHub {
      owner = "KDE";
      repo = "plasma-wayland-protocols";
      rev = "4c015e90ae6c88f2ffa766e899387ef431eade49";
      hash = "sha256-Cnlgvaoc6ii/XBIvksnDAYE7ec/VKJUc1Ub7KzIVAeA=";
    };
  };

  # Prebuilt ffmpeg + fork-specific static libs (libcbs, libhdr10plus,
  # libSvtAv1Enc, libx264/x265) from the fork's build-deps repo.
  buildDepsTag = "v2026.507.72908";
  ffmpegPrebuilt = fetchzip {
    url = "https://github.com/AlkaidLab/foundation-build-deps/releases/download/${buildDepsTag}/Linux-x86_64-ffmpeg.tar.gz";
    hash = "sha256-hwm+L60o6b7XGaFVdz1eqSQ1eAfF40lXqzagiOZBbAU=";
  };

  stdenv' = if cudaPackages != null then cudaPackages.backendStdenv else stdenv;
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "foundation-sunshine";
  inherit version;

  src = fetchFromGitHub {
    owner = "Biaogo";
    repo = "foundation-sunshine-linux";
    inherit rev;
    hash = "sha256-f8eKLBgOLc26NDDkQ3zK4aDXn45MjU55J/fbGWTqM+M=";
  };

  # Web UI (vite 8 / rolldown) — engines demand node >=26.7 <27.
  ui = buildNpmPackage {
    pname = "foundation-sunshine-ui";
    inherit (finalAttrs) version src;
    nodejs = nodejs_26;
    npmDepsHash = "sha256-oQoFRqo8qZCENr0Kq4CY9Z/EhIo1QWgFLylu6Tw/p6Q=";
    npmDepsFetcherVersion = 2;

    installPhase = ''
      runHook preInstall
      # npmConfigHook can leave result* convenience symlinks in the source
      # tree; copying them into $out trips the noBrokenSymlinks hook (the
      # openssl dev target does not exist in the build sandbox).
      rm -f result result-* dev result-dev
      mkdir -p "$out"
      cp -a . "$out"/
      runHook postInstall
    '';
  };

  postPatch = ''
    # Drop vendored gitlink sources in where the build expects them
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: src: ''
        rm -rf "third-party/${name}"
        cp -r --no-preserve=mode,ownership "${src}" "third-party/${name}"
      '') submodules
    )}

    # Stage full AMF SDK headers where cmake's linux.cmake expects the
    # submodule (it copies AMF/{core,components} into the build tree with
    # include priority over the older headers inside build-deps). The
    # fork's AMF pin == AMF v1.5.2 == nixpkgs' amf-headers, so reuse that
    # package instead of fetching the whole AMF repo.
    rm -rf "third-party/AMF"
    mkdir -p "third-party/AMF/amf/public/include"
    cp -r --no-preserve=mode,ownership "${amf-headers}/include/AMF/core" "${amf-headers}/include/AMF/components" \
      "third-party/AMF/amf/public/include/"

    # Build webui separately; don't look for npm (mirrors nixpkgs' sunshine)
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail 'find_program(NPM npm REQUIRED)' ""

    # Use system boost instead of FetchContent (nixpkgs boost is 1.89; the
    # fork pins 1.92 EXACT which no distro ships — rewrite the pin).
    sed -i -E 's/set\(BOOST_VERSION "[^"]*"\)/set(BOOST_VERSION "${boost.version}")/' \
      cmake/dependencies/Boost_Sunshine.cmake
    sed -i -E 's/set\(BOOST_RELEASE_VERSION "[^"]*"\)/set(BOOST_RELEASE_VERSION "${boost.version}")/' \
      cmake/dependencies/Boost_Sunshine.cmake
    echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake

    # Remove upstream dependency on systemd/udev find modules (NixOS paths
    # are provided via explicit cmakeFlags below).
    substituteInPlace cmake/packaging/linux.cmake \
      --replace-fail 'find_package(Systemd)' "" \
      --replace-fail 'find_package(Udev)' ""

    # Desktop file: launch sunshine directly instead of a systemd unit that
    # does not exist on NixOS.
    substituteInPlace packaging/linux/sunshine.desktop \
      --replace-fail '/usr/bin/env systemctl start --u sunshine' 'sunshine'

    substituteInPlace packaging/linux/sunshine.service.in \
      --replace-fail '/bin/sleep' '${lib.getExe' coreutils "sleep"}'
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    makeWrapper
    wayland-scanner
    # The vendored ffmpeg archives are built against stock glibc and need
    # their RUNPATH fixed up for the linking binary.
    autoPatchelfHook
  ]
  ++ lib.optionals (cudaPackages != null) [
    autoAddDriverRunpath
    cudaPackages.cuda_nvcc
    (lib.getDev cudaPackages.cuda_cudart)
  ];

  buildInputs = [
    boost
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
    pcre
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
    libglvnd
    libgbm
    numactl
    amf-headers
    svt-av1
    vulkan-loader
    pipewire
    glib # GIO for the KWin capture backend (pipewire.cpp)
    libappindicator
    libnotify
  ]
  ++ lib.optionals (cudaPackages != null) [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_cudart
  ];

  runtimeDependencies = [
    avahi
    libgbm
    libxrandr
    libxcb
    libglvnd
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeBool "BUILD_TESTS" false)
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" (cudaPackages != null))
    (lib.cmakeBool "SUNSHINE_ENABLE_WAYLAND" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_X11" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_DRM" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_VAAPI" true)
    (lib.cmakeBool "SUNSHINE_ENABLE_KWIN" true)
    # The fork's Linux tray implementation (tray_linux.cpp) needs Qt6 Widgets
    # via the tray submodule's CMake, which nothing add_subdirectory's on
    # Linux. Qt is a heavy dependency; WebUI covers tray functionality.
    (lib.cmakeBool "SUNSHINE_ENABLE_TRAY" false)
    (lib.cmakeBool "SUNSHINE_REQUIRE_TRAY" false)
    (lib.cmakeFeature "FFMPEG_PREPARED_BINARIES" "${ffmpegPrebuilt}")
    (lib.cmakeBool "SUNSHINE_SYSTEM_NLOHMANN_JSON" true)
    # upstream tries to use systemd/udev to find these dirs in FHS distros;
    # set them explicitly instead
    (lib.cmakeBool "UDEV_FOUND" true)
    (lib.cmakeBool "SYSTEMD_FOUND" true)
    (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
    (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
    (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
    # used in the generated systemd unit's ExecStart= line
    (lib.cmakeFeature "SUNSHINE_EXECUTABLE_PATH" "${placeholder "out"}/bin/sunshine")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "Biaogo")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://github.com/Biaogo/foundation-sunshine-linux")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/Biaogo/foundation-sunshine-linux/issues")
  ];

  env = {
    # needed to trigger CMake version configuration (cmake/prep/build_version.cmake)
    BUILD_VERSION = finalAttrs.version;
    # build_version.cmake only honours BUILD_VERSION when BRANCH=="master";
    # any other branch makes the binary version fall back to 0.0.0.<commit>.
    BRANCH = "master";
    COMMIT = lib.substring 0 8 rev;
  };

  # Place the prebuilt webui where cmake's install step expects it
  # (${CMAKE_BINARY_DIR}/assets/web, per cmake/packaging/common.cmake).
  preBuild = ''
    mkdir -p assets
    cp -r --no-preserve=mode,ownership "${finalAttrs.ui}/build/assets/web" assets/web
  '';

  # Build only the sunshine binary; the default `all` target includes the
  # web-ui custom target, which needs npm at build time (the UI is prebuilt
  # above instead). structuredAttrs passes buildFlags as a JSON array which
  # the default builder does not splice into the ninja invocation, so use an
  # explicit buildPhase.
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

  # Sunshine dlopens libvulkan (NVENC/Vulkan encoder probing)
  postFixup = ''
    wrapProgram "$out/bin/sunshine" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader ]}
  '';

  meta = {
    description = "Self-hosted game stream host for Moonlight, with HDR/HLG, remote USB and audio enhancements (Linux build)";
    longDescription = ''
      Foundation Sunshine is the qiin2333 fork of LizardByte/Sunshine, adding a
      full HDR pipeline (PQ + HLG, HDR10+/Vivid dynamic metadata, Dolby Vision),
      folder sharing, remote USB, DualSense and audio enhancements.

      This is the Linux build from the linux-support branch: KWin ScreenCast
      (including krfb-virtualmonitor virtual outputs), KMS, wlr and X11 capture;
      NVENC/VAAPI encoders. Windows-only components (ZakoVDD virtual display
      driver, vmouse, vsink, RTX HDR) are stubbed out — on Linux use
      krfb-virtualmonitor for virtual displays instead.
    '';
    homepage = "https://github.com/Biaogo/foundation-sunshine-linux";
    changelog = "https://github.com/Biaogo/foundation-sunshine-linux/releases/tag/v${version}-linux";
    license = lib.licenses.gpl3Only;
    mainProgram = "sunshine";
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ ];
  };
})

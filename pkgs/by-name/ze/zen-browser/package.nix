{
  lib,
  buildNpmPackage,
  buildPackages,
  fetchFromGitHub,
  fetchurl,
  overrideCC,

  # build time
  cargo,
  git,
  gnum4,
  nasm,
  nodejs,
  pkg-config,
  pkgsBuildBuild,
  pkgsCross,
  python3,
  runCommand,
  rsync,
  rustc,
  rust-cbindgen,
  rustPlatform,
  unzip,
  vips,
  wrapGAppsHook3,
  writeShellScript,

  # runtime
  alsa-lib,
  atk,
  cairo,
  cups,
  dbus,
  dbus-glib,
  ffmpeg,
  fontconfig,
  freetype,
  gdk-pixbuf,
  gtk3,
  glib,
  libGL,
  libGLU,
  libdrm,
  libevent,
  libffi,
  libglvnd,
  libjpeg,
  libnotify,
  libpng,
  libpulseaudio,
  libstartup_notification,
  libva,
  libvpx,
  libwebp,
  libxkbcommon,
  libxml2,
  mesa,
  pango,
  pciutils,
  pipewire,
  udev,
  xcb-util-cursor,
  xorg,
  zlib,

  generic ? false,
}:
let
  surfer = buildNpmPackage {
    pname = "surfer";
    version = "1.4.21";

    src = fetchFromGitHub {
      owner = "zen-browser";
      repo = "surfer";
      rev = "7f6da82ec44d210875b9a9c40b2169df0c88ff44";
      hash = "sha256-QfckIXxg5gUNvoofM39ZEiKkYV62ZJduHKVd171HQBw=";
    };

    patches = [ ./surfer-dont-check-update.patch ];

    npmDepsHash = "sha256-p0RVqn0Yfe0jxBcBa/hYj5g9XSVMFhnnZT+au+bMs18=";
    makeCacheWritable = true;

    SHARP_IGNORE_GLOBAL_LIBVIPS = false;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ vips ];
  };

  llvmPackages0 = rustc.llvmPackages;
  llvmPackagesBuildBuild0 = pkgsBuildBuild.rustc.llvmPackages;

  llvmPackages = llvmPackages0.override {
    bootBintoolsNoLibc = null;
    bootBintools = null;
  };
  llvmPackagesBuildBuild = llvmPackagesBuildBuild0.override {
    bootBintoolsNoLibc = null;
    bootBintools = null;
  };

  buildStdenv = overrideCC llvmPackages.stdenv (
    llvmPackages.stdenv.cc.override { bintools = buildPackages.rustc.llvmPackages.bintools; }
  );

  wasiSysRoot = runCommand "wasi-sysroot" { } ''
    mkdir -p $out/lib/wasm32-wasi
    for lib in ${pkgsCross.wasi32.llvmPackages.libcxx}/lib/*; do
      ln -s $lib $out/lib/wasm32-wasi
    done
  '';

  firefox-l10n = fetchFromGitHub {
    owner = "mozilla-l10n";
    repo = "firefox-l10n";
    rev = "cb528e0849a41c961f7c1ecb9e9604fc3167e03e";
    hash = "sha256-KQtSLDDPo6ffQwNs937cwccMasUJ/bnBFjY4LxrNGFg=";
  };
in
buildStdenv.mkDerivation rec {
  pname = "zen-browser";
  version = "1.0.1-a.5";

  src = fetchFromGitHub {
    owner = "zen-browser";
    repo = "desktop";
    rev = version;
    leaveDotGit = true;
    fetchSubmodules = true;
    hash = "sha256-ysFgGu5GiNS/jutI2fRVDccThiyD64qQATRCawA42uA=";
  };

  firefoxVersion = (lib.importJSON "${src}/surfer.json").version.version;
  firefoxSrc = fetchurl {
    url = "mirror://mozilla/firefox/releases/${firefoxVersion}/source/firefox-${firefoxVersion}.source.tar.xz";
    hash = "sha256-AnIloemwdPAHLiLHJkzyew0jZMZ1w8qBGqbCX7Abn3A=";
  };

  SURFER_COMPAT = generic;

  nativeBuildInputs = [
    cargo
    git
    gnum4
    nasm
    nodejs
    pkg-config
    python3
    rsync
    rust-cbindgen
    rustPlatform.bindgenHook
    rustc
    surfer
    unzip
    wrapGAppsHook3
    xorg.xvfb
  ];

  buildInputs =
    [
      alsa-lib
      atk
      cairo
      cups
      dbus
      dbus-glib
      ffmpeg
      fontconfig
      freetype
      gdk-pixbuf
      gtk3
      glib
      libGL
      libGLU
      libdrm
      libevent
      libffi
      libglvnd
      libjpeg
      libnotify
      libpng
      libpulseaudio
      libstartup_notification
      libva
      libvpx
      libwebp
      libxkbcommon
      libxml2
      mesa
      pango
      pciutils
      pipewire
      udev
      xcb-util-cursor
      zlib
    ]
    ++ (with xorg; [
      libxcb
      libX11
      libXcursor
      libXrandr
      libXi
      libXext
      libXcomposite
      libXdamage
      libXfixes
      libXScrnSaver
    ]);

  configureScript = writeShellScript "configureMozconfig" ''
    for flag in $@; do
      echo "ac_add_options $flag" >> mozconfig
    done
  '';

  configureFlags = [
    "--disable-bootstrap"
    "--disable-updater"
    "--with-libclang-path=${llvmPackagesBuildBuild.libclang.lib}/lib"
    "--with-wasi-sysroot=${wasiSysRoot}"
  ];

  preConfigure = ''
    export LLVM_PROFDATA=llvm-profdata
    export MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE=system
    export WASM_CC=${pkgsCross.wasi32.stdenv.cc}/bin/${pkgsCross.wasi32.stdenv.cc.targetPrefix}cc
    export WASM_CXX=${pkgsCross.wasi32.stdenv.cc}/bin/${pkgsCross.wasi32.stdenv.cc.targetPrefix}c++

    export ZEN_RELEASE=1
    surfer ci --brand alpha --display-version ${version}

    export HOME=$TMPDIR
    git config --global user.email "nixbld@localhost"
    git config --global user.name "nixbld"
    install -D ${firefoxSrc} .surfer/engine/firefox-${firefoxVersion}.source.tar.xz
    surfer download
    surfer import
    patchShebangs engine/mach engine/build engine/tools
  '';

  preBuild = ''
    cp -r ${firefox-l10n} l10n/firefox-l10n
    for lang in $(cat ./l10n/supported-languages); do
      rsync -av --progress l10n/firefox-l10n/$lang/ l10n/$lang --exclude .git
    done
    sh scripts/copy-language-pack.sh en-US
    for lang in $(cat ./l10n/supported-languages); do
      sh scripts/copy-language-pack.sh $lang
    done

    Xvfb :2 -screen 0 1024x768x24 &
    export DISPLAY=:2
  '';

  buildPhase = ''
    runHook preBuild

    surfer build

    runHook postBuild
  '';

  preInstall = ''
    cd engine/obj-*
  '';

  meta = {
    description = "Firefox based browser with a focus on privacy and customization";
    homepage = "https://www.zen-browser.app/";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ Zh40Le1ZOOB ];
    mainProgram = "zen";
  };
}

{ stdenv
, lib
, pkg-config
, pkgsCross
, bintools-unwrapped
, libffi
, libusb1
, wxGTK32
, python3
, gcc-arm-embedded
, klipper
, avrdude
, stm32flash
, removeReferencesTo
, mcu ? "mcu"
, firmwareConfig ? ./simulator.cfg
, enableBossac ? false
}: stdenv.mkDerivation rec {
  name = "klipper-firmware-${mcu}-${version}";
  version = klipper.version;
  src = klipper.src;

  nativeBuildInputs = [
    python3
    pkgsCross.avr.stdenv.cc
    gcc-arm-embedded
    bintools-unwrapped
    libffi
    libusb1
    avrdude
    stm32flash
    pkg-config
  ] ++ lib.optionals enableBossac [ wxGTK32 ]; # Required for bossac, which isn't even built by default?

  preBuild = "cp ${firmwareConfig} ./.config";

  postPatch = ''
    patchShebangs .

    # fixes building linux-process "firmware"
    substituteInPlace ./Makefile \
      --replace '-Isrc' '-iquote src'
    substituteInPlace ./src/linux/gpio.c \
      --replace '/usr/include/linux/gpio.h' 'linux/gpio.h'
    substituteInPlace ./src/linux/main.c \
      --replace '/usr/include/sched.h' 'sched.h'
  '';

  makeFlags = [
    "V=1"
    "KCONFIG_CONFIG=${firmwareConfig}"
  ] ++ lib.optionals enableBossac [ "WXVERSION=3.2" ];

  installPhase = ''
    mkdir -p $out
    cp ./.config $out/config
    cp out/klipper.bin $out/ || true
    cp out/klipper.elf $out/ || true
    cp out/klipper.uf2 $out/ || true

    # avoid pulling in toolchains as runtime dependencies
    ${removeReferencesTo}/bin/remove-references-to \
      -t ${gcc-arm-embedded} \
      -t ${pkgsCross.avr.stdenv.cc} \
      $out/klipper.elf
  '';

  dontFixup = true;

  meta = with lib; {
    inherit (klipper.meta) homepage license;
    description = "Firmware part of Klipper";
    maintainers = with maintainers; [ vtuan10 ];
    platforms = platforms.linux;
  };
}

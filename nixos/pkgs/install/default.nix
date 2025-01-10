{ craneLib
, uutils-coreutils
, stdenv
, target ? stdenv.targetPlatform.rust.cargoShortTarget
}:
craneLib.buildPackage rec {
  inherit (uutils-coreutils) version src doCheck;
  pname = "install";
  cargoExtraArgs = "-p uu_${pname} --target ${target}";
  meta = {
    inherit (uutils-coreutils.meta) homepage license platforms;
    mainProgram = pname;
  };
}

self: super: {
  nixos-secrets = self.stdenv.mkDerivation {
    name = "nixos-secrets";
    
    buildInputs = [ (self.python3.withPackages (pythonPackages: [
      pythonPackages.python-gnupg
    ]))];
    
    dontBuild = true;
    unpackPhase = ":";
    installPhase = "install -m755 -D ${./nixos-secrets.py} $out/bin/nixos-secrets";
  };
}

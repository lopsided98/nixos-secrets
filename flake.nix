{
  description = "Encrypted secrets management for NixOS";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib;
    eachSystem allSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      };
    in {
      defaultPackage = pkgs.nixos-secrets;

      defaultApp = {
        type = "app";
        program = "${self.defaultPackage.${system}}/bin/nixos-secrets";
      };

      devShell = import ./shell.nix { inherit pkgs; };
    }) //
    {
      overlay = final: prev: {
        nixos-secrets = final.python3Packages.callPackage ./. { };
      };
    };
}

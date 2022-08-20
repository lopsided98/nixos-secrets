{
  description = "Encrypted secrets management for NixOS";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    with flake-utils.lib;
    eachSystem allSystems (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in {
      packages.default = pkgs.nixos-secrets;

      apps.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/nixos-secrets";
      };

      devShell = import ./shell.nix { inherit pkgs; };
    }) //
    {
      overlays.default = final: prev: {
        nixos-secrets = final.python3Packages.callPackage ./. { };
      };
      nixosModules.default = import ./secrets.nix;
    };
}

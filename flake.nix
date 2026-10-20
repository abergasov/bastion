{
  description = "Bastion NixOS platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere/1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      disko,
      nixos-anywhere,
      ...
    }:
    let
      system = "x86_64-linux";
      patchedNixosAnywhere = nixos-anywhere.packages.${system}.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/nixos-anywhere-host-key-checking.patch ];
      });
    in
    {
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;

      packages.${system}.nixos-anywhere = patchedNixosAnywhere;

      nixosConfigurations.bastion = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./modules/platform.nix
          ./hosts/bastion
        ];
      };
    };
}

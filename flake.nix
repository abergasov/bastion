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

    sops-nix = {
      url = "github:Mic92/sops-nix/44931708c62937c2b1bf7953902989fa5bb9ee1b";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      disko,
      nixos-anywhere,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      patchedNixosAnywhere = nixos-anywhere.packages.${system}.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/nixos-anywhere-host-key-checking.patch ];
      });
    in
    {
      formatter.${system} = nixpkgs.legacyPackages.${system}.writeShellApplication {
        name = "format-nix";
        runtimeInputs = with nixpkgs.legacyPackages.${system}; [ findutils nixfmt ];
        text = ''
          root="''${PRJ_ROOT:-.}"
          find -- "$root" -path "$root/.git" -prune -o -type f -name '*.nix' -print0 | xargs -0 -r nixfmt --
        '';
      };

      packages.${system}.nixos-anywhere = patchedNixosAnywhere;

      nixosConfigurations.bastion = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          hostInput = null;
          sopsFile = null;
        };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./modules/platform.nix
          ./modules/secrets-administration.nix
          ./hosts/bastion
        ];
      };

      checks.${system}.admin-security = import ./tests/admin-security.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        sopsModule = sops-nix.nixosModules.sops;
      };
    };
}

{ ... }:
{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./disko.nix
  ];

  networking.hostName = "bastion";
  system.stateVersion = "26.05";
}

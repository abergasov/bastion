{ lib, ... }:
let
  hostInput =
    if builtins.pathExists ./host-input.nix then
      import ./host-input.nix
    else
      import ./host-input.nix.example;
  configured =
    hostInput.ipv4Address != null
    && hostInput.ipv4Gateway != null
    && hostInput.ipv6Address != null
    && hostInput.ipv6Gateway != null;
in
{
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = lib.mkIf configured {
    matchConfig.Name = "ens3";
    networkConfig.DHCP = "no";
    address = [
      "${hostInput.ipv4Address}/${toString hostInput.ipv4PrefixLength}"
      "${hostInput.ipv6Address}/${toString hostInput.ipv6PrefixLength}"
    ];
    routes = [
      { routeConfig.Gateway = hostInput.ipv4Gateway; }
      { routeConfig.Gateway = hostInput.ipv6Gateway; }
    ];
  };
}

{ config, lib, hostInput ? null, sopsFile ? null, ... }:
let
  resolvedHostInput =
    if hostInput != null then hostInput else if builtins.pathExists ../hosts/bastion/host-input.nix then
      import ../hosts/bastion/host-input.nix
    else
      import ../hosts/bastion/host-input.nix.example;
  productionConfigured =
    (resolvedHostInput.adminAuthorizedKey or null) != null
    && (resolvedHostInput.ownerAgeRecipient or null) != null
    && (resolvedHostInput.vpsAgeRecipient or null) != null
    && (resolvedHostInput.vpsAgeIdentityFile or null) != null
    && (resolvedHostInput.sopsSecretsFile or null) != null;
in
{
  options.bastion.serverSecrets = {
    openvpnServerKey = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/openvpn-server-key";
      readOnly = true;
    };
    wireguardServerKey = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/wireguard-server-key";
      readOnly = true;
    };
    sshNotifyConfig = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/ssh-notify-config";
      readOnly = true;
    };
  };


  config = lib.mkIf productionConfigured {
    users.mutableUsers = false;

    assertions = [
      {
        assertion = sopsFile != null || (lib.hasPrefix "secrets/" resolvedHostInput.sopsSecretsFile && !lib.hasInfix ".." resolvedHostInput.sopsSecretsFile);
        message = "sopsSecretsFile must name an encrypted file under secrets/.";
      }
    ];

    sops = {
      defaultSopsFile = if sopsFile != null then sopsFile else ../. + "/${resolvedHostInput.sopsSecretsFile}";
      validateSopsFiles = sopsFile == null;
      age.keyFile = "/var/lib/sops-nix/age/key.txt";
      secrets = {
        admin-password-hash.neededForUsers = true;
        root-password-hash.neededForUsers = true;
        openvpn-server-key = { };
        wireguard-server-key = { };
      };
    };

    users.users = {
      root.hashedPasswordFile = config.sops.secrets.root-password-hash.path;
      admin = {
        isNormalUser = true;
        hashedPasswordFile = config.sops.secrets.admin-password-hash.path;
        openssh.authorizedKeys.keys = [ resolvedHostInput.adminAuthorizedKey ];
      };
    };

    services.openssh = {
      enable = true;
      settings = {
        AllowUsers = [ "admin" ];
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PubkeyAuthentication = true;
      };
    };

    services.fail2ban.enable = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}

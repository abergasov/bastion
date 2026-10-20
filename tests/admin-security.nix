{ pkgs, sopsModule }:
pkgs.testers.nixosTest {
  name = "bastion-admin-security";

  nodes.machine = { lib, ... }: {
    imports = [ sopsModule ../modules/secrets-administration.nix ];
    _module.args = {
      hostInput = {
        adminAuthorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBastionSyntheticAdminKey000000000000000000000000 test";
        ownerAgeRecipient = "age1ownerrecipientforbastiontest0000000000000000000000000000000000";
        vpsAgeRecipient = "age1vpsrecipientforbastiontest000000000000000000000000000000000000";
        vpsAgeIdentityFile = "/run/vps-age-key";
        sopsSecretsFile = "secrets/runtime.yaml";
      };
      sopsFile = "/run/bastion-secrets.yaml";
    };
    boot.consoleLogLevel = lib.mkForce 3;
    environment.systemPackages = [ pkgs.age pkgs.expect pkgs.openssh pkgs.openssl pkgs.sops ];
  };

  nodes.client = { lib, ... }: {
    boot.consoleLogLevel = lib.mkForce 3;
    environment.systemPackages = [ pkgs.age pkgs.openssh pkgs.sops ];
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("sshd.service")
    machine.wait_for_unit("fail2ban.service")
    client.wait_for_unit("multi-user.target")
    machine.succeed("install -d -m 700 /var/lib/sops-nix/age")
    machine.succeed("age-keygen -o /run/vps-age-key && chmod 600 /run/vps-age-key && install -m 600 /run/vps-age-key /var/lib/sops-nix/age/key.txt")
    client.succeed("age-keygen -o /run/owner-age-key")
    owner_recipient = client.succeed("age-keygen -y /run/owner-age-key").strip()
    vps_recipient = machine.succeed("age-keygen -y /run/vps-age-key").strip()
    machine.succeed("admin_hash=$(openssl passwd -6 -salt bastion-admin synthetic-test-admin-password); root_hash=$(openssl passwd -6 -salt bastion-root synthetic-test-root-password); printf 'admin-password-hash: \"%s\"\\nroot-password-hash: \"%s\"\\nopenvpn-server-key: synthetic-openvpn-key\\nwireguard-server-key: synthetic-wireguard-key\\n' \"$admin_hash\" \"$root_hash\" > /run/bastion-secrets.plain.yaml")
    machine.succeed("sops --encrypt --age {},{} --input-type yaml --output /run/bastion-secrets.yaml /run/bastion-secrets.plain.yaml && rm /run/bastion-secrets.plain.yaml".format(owner_recipient, vps_recipient))
    machine.succeed("test \"$(stat -c %a /run/vps-age-key)\" = 600 && test ! -e /run/owner-age-key")
    ciphertext = machine.succeed("base64 -w0 /run/bastion-secrets.yaml").strip()
    client.succeed("printf %s {} | base64 -d > /run/bastion-secrets.yaml".format(shlex.quote(ciphertext)))
    client.succeed("SOPS_AGE_KEY_FILE=/run/owner-age-key sops --decrypt /run/bastion-secrets.yaml >/dev/null")
    client.succeed("age-keygen -o /run/rejected-age-key")
    client.fail("SOPS_AGE_KEY_FILE=/run/rejected-age-key sops --decrypt /run/bastion-secrets.yaml >/dev/null")
    machine.succeed("/run/current-system/bin/switch-to-configuration test")
    machine.succeed("test \"$(stat -c %a /var/lib/sops-nix/age/key.txt)\" = 600")
    machine.succeed("for secret in admin-password-hash root-password-hash; do test \"$(stat -c '%u %a' /run/secrets-for-users/$secret)\" = '0 400'; done")
    machine.fail("runuser -u admin -- cat /run/secrets-for-users/root-password-hash")
    machine.succeed("install -d -m 700 -o admin -g users /home/admin/.ssh")
    client.succeed("ssh-keygen -q -t ed25519 -N \"\" -f /tmp/admin-key")
    client.succeed("ssh-keygen -q -t ed25519 -N \"\" -f /tmp/rejected-key")
    import shlex
    admin_key = client.succeed("cat /tmp/admin-key.pub").strip()
    machine.succeed("printf '%s\\n' {} > /home/admin/.ssh/authorized_keys".format(shlex.quote(admin_key)))
    machine.succeed("chown admin:users /home/admin/.ssh/authorized_keys && chmod 600 /home/admin/.ssh/authorized_keys")
    client.succeed("ssh -i /tmp/admin-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@machine true")
    client.fail("ssh -i /tmp/admin-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@machine true")
    client.fail("ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@machine true")
    machine.succeed("runuser -u admin -- expect -c 'spawn su -c \"id -u\"; expect \"Password:\"; send \"synthetic-test-root-password\\r\"; expect \"0\"; expect eof'")
    machine.succeed("runuser -u admin -- expect -c 'spawn su -c \"id -u\"; expect \"Password:\"; send \"wrong-password\\r\"; expect \"Authentication failure\"; expect eof; exit 0'")

    machine.succeed("fail2ban-client status sshd")
    machine.succeed("test \"$(fail2ban-client get sshd backend)\" = systemd")
    machine.succeed("test \"$(fail2ban-client get sshd findtime)\" = 600")
    machine.succeed("test \"$(fail2ban-client get sshd bantime)\" = 600")
    maxretry = int(machine.succeed("fail2ban-client get sshd maxretry").strip())
    assert maxretry == 3
    client_ipv4 = client.succeed("ip -4 -o addr show dev eth1 | awk '{print $4}' | cut -d/ -f1").strip()
    for _ in range(maxretry):
      client.fail("ssh -4 -i /tmp/rejected-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@machine true")
    machine.wait_until_succeeds("fail2ban-client get sshd banip | grep -Fx {}".format(client_ipv4))
    client.fail("ssh -i /tmp/admin-key -o ConnectTimeout=2 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@machine true")
    machine.succeed("fail2ban-client set sshd unbanip {}".format(client_ipv4))
    machine.succeed("! fail2ban-client get sshd banip | grep -Fqx {}".format(client_ipv4))
    client.succeed("ssh -i /tmp/admin-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@machine true")

    machine.succeed("ip -6 addr add fd00::1/64 dev eth1")
    client.succeed("ip -6 addr add fd00::2/64 dev eth1")
    for _ in range(maxretry):
      client.fail("ssh -6 -i /tmp/rejected-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@fd00::1 true")
    machine.wait_until_succeeds("fail2ban-client get sshd banip | grep -Fx fd00::2")
    client.fail("ssh -6 -i /tmp/admin-key -o ConnectTimeout=2 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@fd00::1 true")
    machine.succeed("fail2ban-client set sshd unbanip fd00::2")
    machine.succeed("! fail2ban-client get sshd banip | grep -Fqx fd00::2")
    client.succeed("ssh -6 -i /tmp/admin-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@fd00::1 true")
  '';
}

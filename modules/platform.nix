{ ... }:
{
  time.timeZone = "UTC";

  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=30day
  '';

  # Future text auth-log rotation belongs to implement-ssh-notifications.
}

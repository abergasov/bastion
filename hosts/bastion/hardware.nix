{ ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "usbhid"
    "virtio_pci"
    "virtio_scsi"
  ];
}

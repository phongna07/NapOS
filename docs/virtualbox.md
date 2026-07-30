# VirtualBox Installation Checklist

Copy the final ISO to Windows after building it in WSL's Linux filesystem:

```bash
cp ~/napos/dist/NapOS-0.1.0-dev-cinnamon-amd64.iso \
  /mnt/c/Users/Phong/Downloads/
```

## VM settings

- Type: Linux / Ubuntu 64-bit.
- Memory: 4–8 GiB.
- CPUs: 2–4, no more than half the host's logical processors.
- Graphics: VMSVGA with 128 MiB video memory.
- Disk: dynamically allocated VDI, 30–40 GiB.
- Network: NAT.
- Unattended installation: disabled.
- Secure Boot: disabled; it is not a NapOS 0.1.0 release promise.

## Legacy BIOS test

1. Leave EFI disabled and attach the development ISO.
2. Boot the live desktop and confirm the NapOS wallpaper.
3. Open `Install NapOS` and install to the VDI.
4. Shut down, eject the ISO, and boot the installed system.
5. Confirm applications, DNS, `apt update`, English locale, Bangkok timezone,
   reboot, and shutdown.

## UEFI test

Create a second disposable VM, or erase the first virtual disk:

1. Enable EFI and keep Secure Boot disabled.
2. Repeat the live boot and installation.
3. Eject the ISO and confirm the installed system boots through EFI.
4. Run the same application, package, locale, network, reboot, and shutdown
   checks.

## Release gate

Build `make release` only after both development-ISO installations pass. Keep
screenshots or notes for the boot menu, live desktop, installer, first installed
boot, application menu, and About/System Information page.

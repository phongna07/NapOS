# vnmint

> A customized Linux Mint installation image with software and defaults prepared for Vietnamese users

![Linux Mint desktop preview](public/vnmint-preview.png)

## Linux Mint dành cho người dùng Việt Nam

`vnmint` là tên của một hệ điều hành linux tuỳ chỉnh. Hệ điều hành gốc vẫn giữ nguyên tên, biểu tượng, hình nền và giao diện nhận diện của Linux Mint 22.3 Cinnamon.

File ISO bổ sung các ứng dụng và thiết lập thực tế để người dùng Việt Nam, đặc biệt là người mới làm quen với Linux, có thể bắt đầu nhanh hơn:

- **Sẵn sàng gõ tiếng Việt.** Fcitx5 Lotus được cài đặt và cấu hình sẵn với
  bàn phím tiếng Anh đứng trước bộ gõ Lotus. (Chuyển đổi giữa tiếng Việt và tiếng Anh bằng tổ hợp phím Ctrl + Space)
- **Giao diện làm việc thuận tiện.** Thanh taskbar được căn giữa, giao diện ứng
  dụng Windows 10 Dark, con trỏ Yaru và các biểu tượng desktop hữu ích được cấu
  hình sẵn.
- **Ứng dụng thiết yếu.** Google Chrome, ONLYOFFICE, VLC, Flameshot và CopyQ
  được cài đặt cùng các thiết lập mặc định phù hợp.
- **Phông chữ quen thuộc.** Bộ phông chữ Microsoft thông dụng giúp tài liệu giữ
  hình thức nhất quán hơn khi trao đổi với người dùng Windows.
- **Nguồn gốc uy tín.** Distro gốc Linux Mint và các gói bên thứ ba được
  xác thực bằng chữ ký, fingerprint và checksum đã ghim trước khi build.

**[Tải file ISO cài đặt mới nhất từ SourceForge →](https://sourceforge.net/projects/vnmint/)**

## Familiar Linux Mint, useful from the first boot

The generated image boots and installs as Linux Mint. Its GRUB and ISOLINUX
menus, Cinnamon menu icon, wallpaper, Plymouth splash, installer launcher, and
operating-system metadata are inherited from the authenticated Linux Mint 22.3
Cinnamon image.

The customization is limited to bundled software and practical desktop
defaults. Web links open in Chrome, common Microsoft Office formats open in
ONLYOFFICE, VLC handles common media formats, CopyQ is available with
`Super+V`, and Vietnamese input is ready through Fcitx5 Lotus.

Boot the image into the Linux Mint live environment to evaluate it before
installing. **Install Linux Mint** occupies the top-left desktop slot, and the
standard installer opens automatically after the live Cinnamon desktop starts.
Close it to continue evaluating the live environment; the desktop shortcut
remains available whenever you are ready to install.

## Download

Images are published on the
**[Download vnmint ISO from SourceForge](https://sourceforge.net/projects/vnmint/)**. The
current build targets 64-bit PCs (`amd64`). Back up important files before
installing any operating system.

## For contributors

The repository contains the authenticated ISO-remaster workflow, package
policy, desktop configuration, and non-networked test suite.

```bash
make help
```

`make help` lists the supported commands. See the
[contributor build guide](docs/building.md) for native Ubuntu and WSL2 host
requirements and complete ISO build commands.

## License

The vnmint build scripts and configuration are licensed under
[GPL-3.0-only](LICENSE). Linux Mint and bundled applications retain their own
licenses. The image includes third-party software and fonts, including Google
Chrome and Microsoft core fonts, which are governed by separate terms; review
those terms before redistributing the image.

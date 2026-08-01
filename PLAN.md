- [ ] github action
- [ ] versioning and branching
- [x] Change background
- [ ] Change logo
- [ ] Remove firefox
- [ ] Remove libreoffice
- [x] Chrome
- [ ] fcitx5-lotus
- [ ] OBS Studio
- [ ] OnlyOffice
- [ ] Zalo appimage
- [ ] zsh shell
- [ ] remove celluloid media player
- [ ] config vlc media player as the default
- [ ] clipboard history
- [ ] add desktop icons and taskbar icons
- [ ] center the taskbar
"""
current=$(gsettings get org.cinnamon enabled-applets)
updated=$(echo "$current" | sed -e 's/:[a-z]*:[0-9]*:menu@cinnamon.org/:center:0:menu@cinnamon.org/' -e 's/:[a-z]*:[0-9]*:grouped-window-list@cinnamon.org/:center:1:grouped-window-list@cinnamon.org/')
gsettings set org.cinnamon enabled-applets "$updated"
"""
- [ ] add some kind of system monitor to the left of the taskbar
- [ ] set "Intall multimedia codecs as the default"
- [ ] Change GRUB boot name (currently Linux Mint)
- [ ] OTA update
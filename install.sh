#!/bin/bash

cd "$(dirname "$0")"

[[ ! -f /etc/arch-release ]] && echo "this is for arch btw" && exit 1
[[ ! -d .config ]] && echo "can't find .config" && exit 1

install_deps() {
  sudo pacman -S --needed \
    hyprlock \
    hypridle \
    kitty \
    cava \
    fastfetch \
    starship \
    grim \
    slurp \
    mpd \
    mpc \
    ttf-jetbrains-mono-nerd \
    alsa-utils \
    networkmanager \
    bluez \
    bluez-utils \
    wireplumber \
    brightnessctl \
    playerctl \
    imagemagick \
    python \
    inotify-tools \
    neovim || exit 1

  local aur_helper=""
  if command -v yay &>/dev/null; then
    aur_helper="yay"
  elif command -v paru &>/dev/null; then
    aur_helper="paru"
  fi

  if [[ -n "$aur_helper" ]]; then
    $aur_helper -S --needed \
      mangowm-git \
      quickshell-git \
      awww \
      rmpc \
      mpd-mpris \
      tiramisu \
      gpu-screen-recorder \
      pokemon-colorscripts-go || echo "some aur packages failed, continuing"
  else
    echo "no aur helper found (yay/paru)"
    echo "install manually: yay -S mangowm-git quickshell-git awww rmpc mpd-mpris tiramisu gpu-screen-recorder pokemon-colorscripts-go"
  fi

  sudo systemctl enable --now NetworkManager 2>/dev/null
  sudo systemctl enable --now bluetooth 2>/dev/null
  systemctl --user enable --now mpd 2>/dev/null
  systemctl --user enable --now mpd-mpris 2>/dev/null
}

install_configs() {
  mkdir -p \
    ~/.config \
    ~/.local/bin \
    ~/wallpapers \
    ~/screenshots \
    ~/screen-recordings \
    ~/.cache/wallpaper-thumbs \
    ~/.config/mpd/playlists

  touch ~/.config/mpd/database 2>/dev/null
  touch ~/.config/mpd/state 2>/dev/null
  touch ~/.config/mpd/sticker.sql 2>/dev/null

  backup=~/.dotfiles-backup-$(date +%s)
  mkdir -p "$backup"

  for dir in mango hypr kitty quickshell fastfetch cava rmpc nvim; do
    [[ -e ~/.config/"$dir" ]] && mv ~/.config/"$dir" "$backup"/
    [[ -d .config/"$dir" ]] && cp -r .config/"$dir" ~/.config/
  done

  [[ -e ~/.config/starship.toml ]] && mv ~/.config/starship.toml "$backup"/
  [[ -f .config/starship.toml ]] && cp .config/starship.toml ~/.config/

  if [[ -d wallpapers ]] && [[ -n "$(ls -A wallpapers 2>/dev/null)" ]]; then
    cp -n wallpapers/* ~/wallpapers/ 2>/dev/null
    local first_wall
    first_wall=$(find ~/wallpapers -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) | head -1)
    [[ -n "$first_wall" ]] && ln -sf "$first_wall" ~/wallpapers/current
  fi

  chmod +x ~/.config/scripts/* 2>/dev/null
  chmod +x ~/.config/quickshell/iris/iris.py 2>/dev/null

  cat > ~/.local/bin/start-quickshell.sh << 'EOF'
#!/bin/bash
pkill -9 quickshell 2>/dev/null
sleep 0.3
nohup quickshell &>/dev/null &
EOF
  chmod +x ~/.local/bin/start-quickshell.sh
}

case "$1" in
  deps)
    install_deps
    echo "deps installed"
    ;;
  configs)
    install_configs
    echo "configs installed, log out and back in"
    ;;
  *)
    echo "first time? [y/n]"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      install_deps
      install_configs
      echo ""
      echo "done, log out and back in"
      echo "then run: ~/.config/scripts/random-wallpaper.sh"
      echo "THANK YOU FOR INSTALLING :)"
    else
      install_configs
      echo ""
      echo "configs updated, log out and back in"
    fi
    ;;
esac
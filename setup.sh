sudo apt update && sudo apt install -y curl git
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply https://github.com/LilianBoulard/dotfiles

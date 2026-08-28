# dotfiles

Neovim + tmux config managed with [GNU Stow](https://www.gnu.org/software/stow/).
Works on macOS and Ubuntu.

## Setup

```bash
brew install stow        # macOS
sudo apt install stow    # Ubuntu

./install.sh             # desktop (tmux prefix C-b)
./install.sh --server    # servers (tmux prefix C-a)
```

- `nvim/` — symlinked as a whole dir; plugins pinned in `nvim/lazy-lock.json`,
  run `:Lazy restore` after cloning on a new machine.
- `tmux/` vs `tmux-server/` — only one gets linked (both want `~/.config/tmux/tmux.conf`).
  Shared settings live in `tmux-common/`.
- tmux plugins (tpm) are machine-local in `~/.config/tmux/plugins`;
  press `prefix + I` inside tmux to install them.

## Manual stow

Packages mirror the `$HOME` layout (`<pkg>/.config/...`), so stow targets `$HOME`:

```bash
stow --restow -t ~ nvim tmux tmux-common             # desktop
stow --restow -t ~ nvim tmux-server tmux-common      # server
```

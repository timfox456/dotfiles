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

## Ubuntu servers

Ubuntu 24.04 ships neovim 0.9.5 (too old for this config) and an old tmux.
`install-deps.sh` checks installed versions and installs modern ones —
neovim from the official release tarball, tmux built from source (uses
`sudo`, or `--user` for a `~/.local` install). If the outdated binary came
from apt, the owning packages are removed first so it doesn't shadow the
new install:

```bash
./install-deps.sh --check    # report only
./install-deps.sh            # upgrade whatever is below minimum
./install.sh --server
```

Defaults: nvim `0.12.4`, tmux `3.7c` (override: `NVIM_VERSION=x.y.z TMUX_VERSION=3.7c ./install-deps.sh`).

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

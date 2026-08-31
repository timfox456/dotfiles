# dotfiles

Neovim + tmux + ghostty + opencode config managed with
[GNU Stow](https://www.gnu.org/software/stow/). Works on macOS, Linux
desktops (i3) and Ubuntu servers.

## Setup

```bash
brew install stow        # macOS
sudo apt install stow    # Ubuntu

./install.sh             # desktop (tmux prefix C-b; stows i3 on Linux)
./install.sh --server    # servers (tmux prefix C-a)
```

Or bootstrap a fresh machine in one shot:

```bash
curl -fsSL https://raw.githubusercontent.com/timfox456/dotfiles/main/bootstrap.sh | bash -s -- --server
```

- `nvim/` — plugins pinned in `nvim/lazy-lock.json`; run `:Lazy restore` after
  cloning on a new machine. Low-RAM instances (< 2GB) automatically skip
  heavyweight LSP servers (pyright/ts_ls) and Codeium; override with
  `NVIM_TINY=1` or `NVIM_TINY=0`.
- `tmux/` vs `tmux-server/` — only one gets linked (both want
  `~/.config/tmux/tmux.conf`). Shared settings in `tmux-common/`.
  Sessionizer: `M-s` (no prefix) or the `s` alias switches/creates a project
  session from `~/timfox456` (override: `PROJECTS_DIR`). Script lives in
  `bin/.local/bin/`.
- `ghostty/` — auto-attaches tmux, Catppuccin Mocha theme.
- `opencode/` — opencode Go/Zen config. Auth keys are per-machine in
  `~/.local/share/opencode/auth.json` (`opencode auth login`).
- **zerostack** — tiny Rust agent for small instances (opencode is too heavy
  for 1GB boxes). `install-deps.sh` installs it via the official script; its
  stowed config is secret-free by design (key resolves from
  `OPENROUTER_API_KEY` in your shell rc — never add keys to the stowed file).
- tmux plugins (tpm) are machine-local in `~/.config/tmux/plugins`;
  press `prefix + I` inside tmux to install them.

## Ubuntu / tooling

`install-deps.sh` installs and pins what the setup needs:

```bash
./install-deps.sh --check    # report only
./install-deps.sh            # upgrade whatever is below minimum
```

Covers: neovim (tarball), tmux (source build), stow, tree-sitter CLI,
typescript@5 + typescript-language-server (npm global), the base
toolchain (`git curl wget mosh jq htop gh glab unzip build-essential ruby
ripgrep fzf nodejs npm python3 python3-pip python3-venv` — macOS gets the same via
`Brewfile`), forge CLIs (`gh glab`), cloud CLIs (`aws az gcloud` — vendor
installers on Linux, Brewfile on macOS), plus tpm with plugins installed
non-interactively.

## Manual stow

Packages mirror the `$HOME` layout (`<pkg>/.config/...`):

```bash
stow --restow -t ~ nvim tmux tmux-common ghostty opencode    # desktop
stow --restow -t ~ nvim tmux-server tmux-common ghostty opencode
```

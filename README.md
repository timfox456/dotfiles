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

- `nvim/` — plugins pinned in `nvim/lazy-lock.json`; run `:Lazy restore` after
  cloning on a new machine. Low-RAM instances (< 2GB) automatically skip
  heavyweight LSP servers (pyright/ts_ls) and Codeium; override with
  `NVIM_TINY=1` or `NVIM_TINY=0`.
- `tmux/` vs `tmux-server/` — only one gets linked (both want
  `~/.config/tmux/tmux.conf`). Shared settings in `tmux-common/`.
  Sessionizer: `M-s` (no prefix) switches/creates a project session from
  `~/timfox456` (override: `PROJECTS_DIR`).
- `ghostty/` — auto-attaches tmux, Catppuccin Mocha theme.
- `opencode/` — opencode Go/Zen config. Auth keys are per-machine in
  `~/.local/share/opencode/auth.json` (`opencode auth login`).
- **zerostack** — tiny Rust agent for small instances (opencode is too heavy
  for 1GB boxes). `install-deps.sh` installs it via the official script and
  seeds a machine-local `~/.config/zerostack/config.toml` from
  `zerostack/config.toml.template`. Auth: `export OPENROUTER_API_KEY=...` in
  your shell rc (per machine — never committed).
- tmux plugins (tpm) are machine-local in `~/.config/tmux/plugins`;
  press `prefix + I` inside tmux to install them.

## Ubuntu / tooling

`install-deps.sh` installs and pins what the setup needs:

```bash
./install-deps.sh --check    # report only
./install-deps.sh            # upgrade whatever is below minimum
```

Covers: neovim (tarball), tmux (source build), stow, tree-sitter CLI,
typescript@5 + typescript-language-server (npm global), and the editor
toolchain (`git curl unzip build-essential ripgrep fzf nodejs npm
python3-pip python3-venv`), plus tpm with plugins installed
non-interactively. macOS: tree-sitter CLI installs via
`brew install tree-sitter-cli`.

## Manual stow

Packages mirror the `$HOME` layout (`<pkg>/.config/...`):

```bash
stow --restow -t ~ nvim tmux tmux-common ghostty opencode    # desktop
stow --restow -t ~ nvim tmux-server tmux-common ghostty opencode
```

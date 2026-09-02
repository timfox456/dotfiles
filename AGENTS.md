# AGENTS.md

Conventions for AI agents (and humans) working in this dotfiles repo.

## What this repo is

Personal dotfiles for Tim Fox: neovim, tmux, ghostty, opencode, zerostack,
git, shell — managed with **GNU Stow**, supporting **macOS**, **Linux
desktops (i3)** and **Ubuntu servers**.

## Structure rules (do not break these)

- Every package mirrors the `$HOME` layout: `pkg/.config/app/file` → stowed
  with `stow -t ~ pkg`. Never create package files at the package root
  (stow would link them to `$HOME` directly — this bug already happened).
- `install.sh` is the only thing that runs stow. Desktop = default,
  `--server` = headless. `i3` stows only on Linux desktops.
- `tmux/` and `tmux-server/` both want `~/.config/tmux/tmux.conf` — only one
  may be stowed. Shared settings live in `tmux-common/`.
- Scripts (`install.sh`, `install-deps.sh`, `bin/`) must pass
  `bash -n` and `shellcheck`; nvim lua must pass `luac -p`. CI (`.github/
  workflows/ci.yml`) enforces this on ubuntu + macOS runners with a full
  dogfood — keep it green.
- New tooling for macOS goes in the `Brewfile`; Linux apt packages go in
  `TOOL_DEPS` in `install-deps.sh`.

## Secrets policy (critical — repo is PUBLIC)

- **Never commit API keys, tokens, or credentials.** Not in configs, not in
  comments as "examples" with real values, not in tests.
- Per-machine secrets live in:
  - `~/.config/shell/secrets.local` (sourced by `~/.bash_aliases`; ships as
    `shell/.config/shell/secrets.local.example`)
  - environment variables (`OPENROUTER_API_KEY` for zerostack; opencode auth
    lives in `~/.local/share/opencode/auth.json`)
- Files that must stay secret-free: `zerostack/.config/zerostack/config.toml`
  is a stowed symlink into this public repo — keys resolve from env via
  zerostack's `api_key_env` mechanism instead.
- Machine-local state (opencode `node_modules`, tpm plugins, lazy-lock live
  copies) stays out of git via stow file-links and `.stow-local-ignore`.

## Neovim notes

- Plugins are pinned in `nvim/.config/nvim/lazy-lock.json` — update via
  `:Lazy sync` deliberately, never by hand.
- Treesitter uses the **main-branch API** (`require("nvim-treesitter")`);
  the legacy `nvim-treesitter.configs` module is gone upstream. Parser
  compilation needs the `tree-sitter` CLI.
- Low-memory instances (< 2GB RAM, or `NVIM_TINY=1`) skip pyright/ts_ls/
  codeium via `lua/lowmem.lua` — keep new heavyweight servers behind that
  gate.
- **The lazy lockfile lives in the state dir** (`~/.local/state/nvim/
  lazy-lock.json`), not in this repo — lazy's install/update passes write
  there and never touch the repo. The repo copy is the canonical seed:
  `install.sh` copies repo → state on every run; after DELIBERATE plugin
  updates run `bin/lazy-lock-sync` to copy state → repo, then commit.
  Never hand-edit the repo lockfile from a machine's live state.

## Testing

```bash
bash -n install.sh install-deps.sh bootstrap.sh bin/.local/bin/tmux-sessionizer shell/.bash_aliases shell/.bashrc
shellcheck install.sh install-deps.sh bootstrap.sh bin/.local/bin/tmux-sessionizer shell/.bash_aliases shell/.bashrc
find nvim/.config/nvim/lua -name '*.lua' -print0 | xargs -0 -n1 luac -p
./install-deps.sh --check          # version report, changes nothing
tmux -L test -f tmux/.config/tmux/tmux.conf new-session -d   # then kill-server
```
CI runs all of this plus a full dogfood on clean ubuntu + macOS runners.

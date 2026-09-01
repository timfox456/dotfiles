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

- `nvim/` — plugins pinned via the lockfile: `install.sh` converges each
  machine's state lockfile to the repo copy; deliberate plugin updates are
  synced back with `lazy-lock-sync` (then commit + push). The recurring
  `git restore lazy-lock.json` pull ritual is retired. Low-RAM instances
  (< 2GB) automatically skip heavyweight LSP servers (pyright/ts_ls) and
  Codeium; override with `NVIM_TINY=1` or `NVIM_TINY=0`.
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
toolchain (`git curl wget mosh jq htop gh glab lazygit fd tree unzip build-essential ruby
ripgrep fzf nodejs npm python3 python3-pip python3-venv` — macOS gets the same via
`Brewfile`), forge CLIs (`gh glab`), cloud CLIs (`aws az gcloud` — vendor
installers on Linux, Brewfile on macOS), plus tpm with plugins installed
non-interactively.

### Runtime managers: nvm now, fnm/mise as the documented future option

Node version management uses **nvm** (installed here, LTS node + default
alias auto-provisioned when no node versions exist). It works and is
CI-covered — but two alternatives are worth knowing:

- **fnm** — Rust single-binary node manager; ~5ms shell startup vs nvm's
  ~50–100ms, no environment-variable quirks, reads `.nvmrc`. The swap is
  small (one zip binary + `eval "$(fnm env --use-on-cd)"` in the shell rc)
  and becomes worth it if shell startup on tiny instances ever annoys you.
- **mise** — the bigger consolidation: one Rust tool replacing nvm **and**
  pyenv **and** rbenv **and** uv's version management. Consider when the
  multi-version-manager sprawl across machines becomes the pain point.

Deliberate design note: two node runtimes coexist on servers by design —
nvm node for interactive use, the apt `nodejs` package as the
non-interactive fallback for `install-deps.sh`'s npm-global installs.
Keep that split if you ever migrate managers.

## Gmail via aerc (OAuth — no app passwords, no 2FA requirement)

`aerc/.config/aerc/` holds a working Gmail-over-XOAUTH2 setup. Google requires
OAuth for IMAP (app passwords need 2FA, and Workspace is dropping password
IMAP entirely), so the flow uses a vendored token helper:

1. [Google Cloud Console](https://console.cloud.google.com/) → create a
   project → OAuth consent screen (External is fine for personal use) →
   Credentials → **OAuth client ID → Desktop app**.
2. Copy the client ID/secret into `aerc/.config/aerc/mutt_oauth2.py`
   (the `google:` block — installed-app client secrets are not confidential,
   safe to commit).
3. One-time authorize per machine (opens browser, token stored encrypted in
   `~/.local/share/aerc/` — never synced):
   ```bash
   aerc/.config/aerc/mutt_oauth2.py --verbose --authorize \
     --authflow localhostauthcode ~/.local/share/aerc/token.gmail
   ```
4. Edit `aerc/.config/aerc/accounts.conf` (replace `you@gmail.com`) and
   restart aerc. Field reference: `man aerc-accounts`.

Workspace accounts additionally need IMAP enabled by the admin.

### Headless servers

The authorize step needs a browser only for the *approval click* — two ways
to do it for a server:

1. **Authorize on a desktop, copy the encrypted token file** (most reliable):
   ```bash
   # on the Mac, after authorizing:
   scp ~/.local/share/aerc/token.gmail server:~/.local/share/aerc/token.gmail
   ```
   The file is passphrase-encrypted by mutt_oauth2.py — use the *same
   passphrase* when creating it on each machine and the copy decrypts fine.
2. **Device code flow, on the server itself**:
   ```bash
   aerc/.config/aerc/mutt_oauth2.py --verbose --authorize \
     --authflow devicecode ~/.local/share/aerc/token.gmail
   ```
   It prints a URL + code; open the URL in any browser, log in, enter the
   code. Note: Google's device flow can require an OAuth client of type
   *"TV and Limited Input devices"* — if the Desktop client rejects it,
   either create that second client type or use option 1.

**Important (personal accounts):** while the OAuth consent screen is in
*"Testing"* status, Google expires refresh tokens after **7 days** — you'd
re-authorize weekly. Press **"Publish app"** on the consent screen to avoid
it (unverified-app warning on first login is expected and harmless).

## Docker (opt-in, macOS only)

Docker is deliberately **not** in the default setup: the daemon is a
non-starter on small servers, Docker Desktop is a resource hog with paid
corporate licensing, and older Macs shouldn't carry it at all. When a Mac
actually needs containers:

```bash
./install-deps.sh --docker      # installs colima + docker + compose
colima start                    # VM runs only while started (colima stop frees it)
docker run --rm hello-world
```

colima is free, works on Intel and Apple Silicon, and the VM consumes
nothing until started. Apple Silicon users preferring a GUI can swap
colima for OrbStack (edit `Brewfile.docker`).

## Manual stow

Packages mirror the `$HOME` layout (`<pkg>/.config/...`):

```bash
stow --restow -t ~ nvim tmux tmux-common ghostty opencode    # desktop
stow --restow -t ~ nvim tmux-server tmux-common ghostty opencode
```

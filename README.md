# dotfiles

Neovim + tmux + ghostty + opencode config managed with
[GNU Stow](https://www.gnu.org/software/stow/). Works on macOS, Linux
desktops (i3) and Ubuntu servers.

## Setup

```bash
brew install stow        # macOS
sudo apt install stow    # Ubuntu

./install.sh             # variant autodetected: headless Linux (no DISPLAY)
                         # = server (prefix C-a); everything else = desktop
./install.sh --server    # force server variant
./install.sh --desktop   # force desktop variant
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
  `OPENROUTER_API_KEY` in `~/.config/shell/secrets.local` — never add keys to
  the stowed file).
- tmux plugins (tpm) are machine-local in `~/.config/tmux/plugins`;
  press `prefix + I` inside tmux to install them.

## Manual steps on a new machine

Everything else is automated by `install.sh` + `install-deps.sh`. Exactly two
things are per-machine on purpose — they contain secrets or identity
information that must never live in this public repo:

### 1. Secrets — `~/.config/shell/secrets.local`

```bash
cp ~/.config/shell/secrets.local.example ~/.config/shell/secrets.local
chmod 600 ~/.config/shell/secrets.local
# edit: API keys — OPENROUTER_API_KEY (zerostack), OPENAI_API_KEY,
# ANTHROPIC_API_KEY, GEMINI_API_KEY, ...
```

Sourced last by both `.bashrc`/`.bash_aliases` (servers) and `.zshrc` (Macs).
Never synced, never committed.

### 2. Git identity — `~/.config/git/gitconfig.local` (work machines)

```bash
cp ~/.config/git/gitconfig.local.example ~/.config/git/gitconfig.local
# edit: name + the email for that employer
```

The stowed `.gitconfig` includes this file last, so it overrides the personal
default identity. Personal machines: skip this step entirely.
Verify per machine: `git config --show-origin --global --includes user.email`

### 3. Gmail OAuth (aerc) — one-time per machine

See the "Gmail via aerc" section below: paste the OAuth client id/secret into
`mutt_oauth2.py`, then authorize (desktop flow, or device flow / token copy
on headless servers). Tokens live in `~/.local/share/aerc/` — machine-local.

### 4. SSH keys — GitHub / GitLab

Private keys are per-machine and never leave it (same rule as secrets.local).
Generate one per machine, publish the public half to the forge, and pin the
mapping in `~/.ssh/config`:

```bash
# generate (one key per machine, distinct file per forge)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "tfox@$(hostname -s)" -f ~/.ssh/id_ed25519_github -N ""
ssh-keygen -t ed25519 -C "tfox@$(hostname -s)" -f ~/.ssh/id_ed25519_gitlab -N ""
```

`~/.ssh/config` (create if absent, `chmod 600`):

```ssh-config
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes

Host gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_gitlab
    IdentitiesOnly yes

# self-managed GitLab at work: one Host block per instance
# Host gitlab.myemployer.com
#     User git
#     IdentityFile ~/.ssh/id_ed25519_gitlab
#     IdentitiesOnly yes
```

Publish the public keys:

```bash
# GitHub: paste ~/.ssh/id_ed25519_github.pub at
#   https://github.com/settings/keys — or via the CLI:
gh ssh-key add ~/.ssh/id_ed25519_github.pub --title "$(hostname -s)"
# GitLab: https://gitlab.com/-/user_settings/ssh-keys — or:
glab ssh-key add ~/.ssh/id_ed25519_gitlab.pub --title "$(hostname -s)"
```

Test: `ssh -T git@github.com` and `ssh -T git@gitlab.com` (both should greet
your username, not ask for a password). On work machines the employer's key
+ host block replaces the gitlab.com one, and the email in
`gitconfig.local` should match the account that key belongs to.

## Ubuntu / tooling

`install-deps.sh` installs and pins what the setup needs:

```bash
./install-deps.sh --check    # report only
./install-deps.sh            # upgrade whatever is below minimum
```

Covers: neovim (tarball), tmux (source build), stow, tree-sitter CLI,
typescript@5 + typescript-language-server (npm global), the base
toolchain (`git curl wget mosh jq htop gh glab aerc lazygit fd tree unzip build-essential ruby
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
stow --restow -t ~ nvim tmux tmux-common ghostty opencode zerostack git shell bin aerc    # desktop
stow --restow -t ~ nvim tmux-server tmux-common ghostty opencode zerostack git shell bin aerc
```

(`install.sh` is the supported entry point — it unstows the opposite tmux
variant, seeds the lazy lockfile and handles the ordering. The manual form
is for surgery.)

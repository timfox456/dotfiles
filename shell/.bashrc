# shellcheck shell=bash
# ~/.bashrc — headless Ubuntu servers (stowed via the shell package).
# The synced ~/.bash_aliases (sourced near the end) carries aliases, nvm/uv
# loading and per-machine secrets; this file provides the base environment.
# The interactive guard stays first: non-interactive shells (scp, remote
# commands) must stay light.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History: far bigger than the Ubuntu default, appended (never clobbered),
# written immediately (tmux windows share it), timestamped for servers.
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT='%F %T '
PROMPT_COMMAND='history -a'

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# colored prompt + current git branch (dependency-free, no bash-completion
# requirement — this function must be defined before PS1 uses it)
parse_git_branch() {
    git branch 2>/dev/null | sed -n 's/^\* \(.*\)$/ (\1)/p'
}

case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\[\033[01;33m\]$(parse_git_branch)\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w$(parse_git_branch)\$ '
fi
unset color_prompt

# NOTE: no xterm-ghostty downgrade hack here — install-deps.sh vendors the
# ghostty terminfo so servers speak TERM=xterm-ghostty natively.

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# ll/la/l, alert, the sessionizer alias, nvm/uv loading and the per-machine
# secrets sourcing all live in the synced ~/.bash_aliases — sourced LAST so
# its PATH setup lands after everything above.

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    # shellcheck source=/dev/null
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    # shellcheck source=/dev/null
    . /etc/bash_completion
  fi
fi

# user-local binaries
export PATH="$PATH:$HOME/bin"

# opencode (guarded — only where the CLI self-installed)
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

# synced aliases, secrets and version managers
if [ -f ~/.bash_aliases ]; then
    # shellcheck source=/dev/null
    . ~/.bash_aliases
fi

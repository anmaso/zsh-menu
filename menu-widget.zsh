# menu-widget.zsh — popup menu of shell actions, drawn at the bottom right.
#
# Usage: source this file from ~/.zshrc, then press Ctrl-K (see MENU_WIDGET_KEYS below).
# Press an item's shortcut to run it; Esc / Enter / q / Ctrl-C closes the menu.
# Whatever you had typed on the command line is left untouched.

# MENU_WIDGET_POSITION: above (default) = insert lines above the prompt;
#                       alt = draw on the alternate screen (hides output while open).
: ${MENU_WIDGET_POSITION:=above}

# ---- menu items: discovered from function names ----------------------------
# Define a function named
#
#     menu-item:[<order>:]<key>:<Label_with_underscores>
#
# and it appears in the menu. <key> is one character (case-sensitive),
# <order> is an optional integer (lower = higher in the menu; items without
# one get 500; ties are sorted by key). Underscores in the label show as spaces.
# The function body runs inside the widget, so zle -M, BUFFER etc. work.
#
#   menu-item:10:g:Git_branch() { zle -M "branch: $(git branch --show-current)" }
#
# Besides functions defined anywhere (e.g. ~/.zshrc), files named like that
# are autoloaded (file content = function body) from:
#   - $MENU_WIDGET_HOME/items          (the defaults shipped with the widget)
#   - $MENU_WIDGET_DIR                 (yours; default ~/.config/menu-widget/items)
typeset -g MENU_WIDGET_HOME=${${(%):-%x}:A:h}
: ${MENU_WIDGET_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/menu-widget/items}

# Autoload every menu-item:* file from a directory (re-run on each open, so
# new or edited files are picked up without re-sourcing).
_menu_widget_load_dir() {
  local d=$1
  [[ -d $d ]] || return 0
  (( ${fpath[(Ie)$d]} )) || fpath=($d $fpath)
  local -a files=($d/menu-item:*(N:t))
  (( $#files )) && autoload -Uz $files
}

# Fills the caller's keys/labels/fns arrays, sorted by (order, key).
# Duplicate keys: the first in sort order wins.
_menu_widget_collect() {
  local name f order key label line
  local -a fields found
  local -A seen
  for name in ${(M)${(k)functions}:#menu-item:*}; do
    fields=("${(@s.:.)name}")
    case $#fields in
      3) order=500;         key=$fields[2]; label=$fields[3] ;;
      4) order=$fields[2];  key=$fields[3]; label=$fields[4] ;;
      *) continue ;;
    esac
    [[ $order == <-> && ${#key} == 1 && -n $label ]] || continue
    found+=("${(l:6::0:)order}:${key}:${name}")
  done
  for line in ${(o)found}; do
    name=${line#*:*:}; key=${${line#*:}%%:*}
    [[ -n ${seen[$key]} ]] && continue
    seen[$key]=1
    fields=("${(@s.:.)name}")
    keys+=($key)
    labels+=("${${fields[-1]}//_/ }")
    fns+=($name)
  done
}

# Helper for items: pick an exported variable with fzf and insert it at the
# cursor as <prefix>NAME<suffix>.  Usage: menu-widget-pick-env [prefix [suffix]]
menu-widget-pick-env() {
  (( $+commands[fzf] )) || { zle -M "fzf not found"; return 0 }
  local name
  name=$(print -rl -- ${(ko)parameters[(R)*export*]} |
    fzf --height=40% --reverse --prompt='env> ' \
        --preview 'printenv {}' --preview-window=down:3:wrap) </dev/tty
  zle reset-prompt
  [[ -n $name ]] && LBUFFER+="$1${name}$2"
  return 0
}

# Debug helper: show what the menu would contain.
menu-widget-list() {
  local -a keys labels fns
  _menu_widget_load_dir $MENU_WIDGET_HOME/items
  _menu_widget_load_dir $MENU_WIDGET_DIR
  _menu_widget_collect
  local i
  for (( i = 1; i <= $#keys; i++ )); do
    print -r -- "${keys[i]}  ${labels[i]}  ($fns[i])"
  done
}

# ---- the popup -------------------------------------------------------------
menu-widget() {
  emulate -L zsh
  setopt local_options

  local -a keys labels fns rows
  local i w=0 title=" Menu "
  _menu_widget_load_dir $MENU_WIDGET_HOME/items
  _menu_widget_load_dir $MENU_WIDGET_DIR
  _menu_widget_collect
  (( $#keys )) || { zle -M "menu-widget: no menu-item:* functions found"; return 0 }

  for (( i = 1; i <= $#keys; i++ )); do
    rows+=("${keys[i]}  ${labels[i]}")
    (( ${#rows[i]} > w )) && w=${#rows[i]}
  done
  (( w < ${#title} )) && w=${#title}

  local h=$(( $#rows + 2 ))             # box height incl. borders
  local width=$(( w + 4 ))              # "│ " + text + " │"
  local col=$(( COLUMNS - width ))      # 1-based column of left border, 1 col margin
  (( col < 1 )) && col=1

  local bold=$'\e[1;33m' dim=$'\e[2m' reset=$'\e[0m'
  local hbar="${(l:$(( w + 2 ))::─:)}"
  local pad_title="${(r:$(( w + 2 ))::─:)title}"

  # Build the box lines (no cursor movement in them)
  local -a box
  box+=("${dim}╭${pad_title}╮${reset}")
  for (( i = 1; i <= $#rows; i++ )); do
    box+=("${dim}│${reset} ${bold}${keys[i]}${reset}${(r:$(( w - 1 )):)${rows[i]#?}} ${dim}│${reset}")
  done
  box+=("${dim}╰${hbar}╯${reset}")

  local key
  case ${MENU_WIDGET_POSITION:-above} in
    alt)
      # Switch to the alternate screen (blank), draw at its bottom right, and
      # switch back on close: the main screen is restored exactly, but it is
      # hidden while the menu is open.
      local row0=$(( LINES - h ))
      (( row0 < 1 )) && row0=1
      printf '\e[?1049h'
      for (( i = 1; i <= h; i++ )); do
        printf '\e[%d;%dH%s' $(( row0 + i - 1 )) $col "${box[i]}"
      done
      read -rsk 1 key
      printf '\e[?1049l'
      ;;
    *)
      # above: scroll in h lines at the bottom (so the prompt can move down),
      # go back, then insert h blank lines at the cursor row. The prompt shifts
      # down h rows; the box goes into the gap and nothing is overwritten.
      for (( i = 1; i <= h; i++ )); do printf '\eD'; done   # index: scroll, keep column
      printf '\e[%dA\e[%dL' $h $h
      printf '\e7'
      printf '\e[%dG%s' $col "${box[1]}"
      for (( i = 2; i <= h; i++ )); do
        printf '\n\e[%dG%s' $col "${box[i]}"
      done
      printf '\e8\e[%dB' $h     # back to the prompt line while waiting
      read -rsk 1 key
      printf '\e[%dA\e[%dM' $h $h   # remove the gap; the prompt moves back up
      ;;
  esac

  # Repaint the prompt (IL/DL reset the cursor column) *before* running the
  # action, so a zle -M message from the action isn't wiped by the redraw.
  zle redisplay

  # Dispatch; BUFFER and CURSOR are never modified here
  for (( i = 1; i <= $#keys; i++ )); do
    if [[ $key == ${keys[i]} ]]; then
      "${fns[i]}"
      break
    fi
  done
}
zle -N menu-widget

# Key bindings: set MENU_WIDGET_KEYS before sourcing to change them, e.g.
#   MENU_WIDGET_KEYS=('^@')        # Ctrl-Space only
#   MENU_WIDGET_KEYS=('\e,' '^K')  # Alt-comma and Ctrl-K
#   MENU_WIDGET_KEYS=()            # bind nothing, do it yourself
# Default: Ctrl-K.
(( ${+MENU_WIDGET_KEYS} )) || typeset -ga MENU_WIDGET_KEYS=('^K')
() {
  local k m
  for k in $MENU_WIDGET_KEYS; do
    for m in viins emacs; do
      bindkey -M $m $k menu-widget
    done
  done
}

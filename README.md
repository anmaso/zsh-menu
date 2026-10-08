# zsh-menu-widget

A popup menu for zsh, opened with a key binding. Press an item's shortcut to run it. Whatever you had typed on the command line is left untouched, and items can insert text into it.

```
╭ Menu ────────────────────────────────╮
│ c  Print working directory           │
│ C  Copy working directory            │
│ e  Insert env variable name          │
│ E  Insert env variable reference     │
│ f  Insert file real path             │
╰──────────────────────────────────────╯
```

## Install

Source the widget from `~/.zshrc`:

```zsh
source ~/personal/zsh-widgets/zsh-menu-widget/menu-widget.zsh
```

Press **Ctrl-K** to open the menu. Esc, Enter, `q` or any unbound key closes it.

Requires zsh on macOS (`pbcopy`). The `e`, `E` and `f` items need [fzf](https://github.com/junegunn/fzf). `f` uses [fd](https://github.com/sharkdp/fd) when available and falls back to `find`.

## Built-in items

| Key | Action |
|-----|--------|
| `c` | Show the working directory (`PWD: …`) |
| `C` | Copy the working directory to the clipboard |
| `e` | Pick an exported variable with fzf, insert `NAME` at the cursor |
| `E` | Same, inserted as `${NAME}` |
| `f` | Pick a file with fzf, insert its full real path (symlinks resolved, shell-quoted) |

## Adding items

Items are discovered from **function names**. Define a function called:

```
menu-item:[<order>:]<key>:<Label_with_underscores>
```

- `<key>` is one character, case-sensitive (`c` and `C` are different items).
- `<order>` is an optional integer. Lower numbers appear higher in the menu. Items without one get 500. Ties are sorted by key.
- Underscores in the label are shown as spaces.
- The function runs inside the widget, so `zle -M`, `BUFFER`, `LBUFFER` and so on work.
- If two items share a key, the first in sort order wins. Give your own item a lower order to override a built-in.
- Names that don't fit the format are ignored.

Functions can be defined anywhere, for example in `~/.zshrc`:

```zsh
menu-item:50:g:Git_branch() { zle -M "branch: $(git branch --show-current)" }
```

### Item files (autoloaded)

Files named like the function are autoloaded from two directories:

1. `items/` next to the widget (the shipped defaults)
2. `~/.config/menu-widget/items/` (yours; set `MENU_WIDGET_DIR` to change it)

A file's content is the function **body only**, with no `name() { … }` wrapper:

```bash
echo 'zle -M "branch: $(git branch --show-current)"' \
  > ~/.config/menu-widget/items/menu-item:50:g:Git_branch
```

Directories are re-scanned every time the menu opens, so new or edited files take effect without re-sourcing. Nothing in them runs until you press the item's key.

### Helpers for items

`menu-widget-pick-env [prefix [suffix]]` lets the user pick an exported variable with fzf and inserts `<prefix>NAME<suffix>` at the cursor. The `e` and `E` items are one-liners that call it.

To insert text from your own item, append to `LBUFFER` (text before the cursor). If your item opens fzf or anything else that draws on the terminal, call `zle reset-prompt` afterwards.

### Debugging

`menu-widget-list` prints the items the menu would show, in order, with the function behind each.

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `MENU_WIDGET_POSITION` | `above` | `above`: insert lines above the prompt, nothing is overwritten. `alt`: draw on the alternate screen, which restores the main screen exactly on close but hides it while the menu is open. |
| `MENU_WIDGET_DIR` | `~/.config/menu-widget/items` | Your item files directory. |

Set these before sourcing the widget (or change `MENU_WIDGET_POSITION` any time, it is read on each open).

### Key binding

Ctrl-K is bound in the `viins` and `emacs` keymaps at the end of `menu-widget.zsh`. To use a different key, edit those lines or add your own after sourcing:

```zsh
bindkey '\e,' menu-widget
```

Ctrl-I can't be used: it is the same byte as Tab in a terminal.

## How it works

- The popup is drawn with raw escape sequences, right-aligned on the screen.
- In `above` mode the widget scrolls in blank lines, inserts blank lines at the cursor row (pushing the prompt down), draws the box in the gap, and deletes the lines on close.
- One key is read with `read -k`, the popup is removed, the prompt is repainted, and then the matching function runs. `BUFFER` and `CURSOR` are never modified by the widget itself.
- The prompt is repainted *before* the action runs so a `zle -M` message from the action isn't wiped.

## Limitations

- The popup is placed relative to the prompt, not pinned to the bottom of the screen. A terminal can't report what is on screen, so drawing over existing output couldn't be undone. The `alt` mode trades that for a blank screen while the menu is open.
- With a multi-line command or prompt, the box appears above the line the cursor is on.
- Shortcuts are single characters.

## Layout

```
menu-widget.zsh     the widget: popup, item discovery, helpers, key binding
items/              default items, one autoloaded file each
```

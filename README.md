# tvim

Neovim config, extracted from the `dot_config/nvim` directory of
[Takuya Matsuyama's dotfiles](https://github.com/craftzdog/dotfiles) so it can be
cloned on its own. The upstream commit history for that directory is preserved.

## Requirements

- Neovim >= 0.12 (plugins are managed with the built-in `vim.pack`)
- Git, and a C compiler for `nvim-treesitter` (the tree-sitter CLI is installed
  through Mason if missing)
- [lazygit](https://github.com/jesseduffield/lazygit) _(optional)_
- ripgrep (live grep) and fd (find files) for the snacks.nvim picker
- a terminal that supports true color and undercurl, such as [Ghostty](https://ghostty.org/)
- fish shell: the `os.edit` commands passed to lazygit are written in fish syntax

## Install

```sh
git clone https://github.com/qapquiz/tvim.git ~/.config/nvim
```

## Layout

```
init.lua
after/lsp/            per-server LSP settings
lua/craftzdog/
  config/             options, keymaps, autocmds, commands, workarounds
  plugins/            plugin list and per-plugin setup
  utils/              project-root lookup, tabline, lualine helpers, lazygit, editor helpers, icons
scripts/snapshot.lua  dumps the config's observable state
```

If `lua/craftzdog/plugins/local.lua` exists, it is loaded as well. Use it for
machine-specific overrides without committing them.

## Snapshot a change

`scripts/snapshot.lua` writes the config's options, keymaps, commands, plugin
settings, and helper outputs as JSON. Two runs on the same checkout produce the
same output, so a diff between two snapshots lists every behavior that differs.

If `~/.config/nvim` is a checkout of this repository, compare two branches:

```sh
git switch main && nvim --headless -S scripts/snapshot.lua > before.json
git switch my-branch && nvim --headless -S scripts/snapshot.lua > after.json
diff before.json after.json
```

Run both commands from the same directory. The output also depends on the
plugins installed in `~/.local/share/nvim`, so compare snapshots from one
machine.

## Syncing with upstream

`upstream` points at the full dotfiles repository. This lifts its Neovim
directory to the root and merges it into this history:

```sh
git fetch upstream
git merge "$(git subtree split --prefix=dot_config/nvim upstream/master)"
```

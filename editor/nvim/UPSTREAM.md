# LazyVim snapshot

This directory is based on the official
[LazyVim Starter](https://github.com/LazyVim/starter) at commit
`803bc181d7c0d6d5eeba9274d9be49b287294d99`, captured on 2026-08-04.

The repository intentionally adds only:

- `lazy-lock.json` and `lazyvim.json` from the working local LazyVim setup;
- `vim.opt.ambiwidth = "single"` in `lua/config/options.lua`.

The Starter's nested `.git` directory and Neovim cache, data, and state
directories are not vendored. To refresh the snapshot, clone the Starter into
a temporary directory, review the upstream diff, preserve the local additions
above, then run `:Lazy sync` and `:LazyHealth` with this directory as the active
Neovim config.

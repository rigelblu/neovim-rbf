---
title: neovim-rbf RBF Changelog
---

Flavour releases use `rbf/VERSION`; upstream's release history stays in the root `CHANGELOG.md`.

# 🔵⋯ [Unreleased]
(empty)

# 🔵⋯ v0.1.1 (2026-11-04)

## 🟠⋯ Fixed for End Users
- 2026-11-04 - fix | edit a concealed buffer without an "Index out of bounds" error when lines are deleted or a plugin shrinks it. Moves the base to upstream master `1332ed9027`, which merged [PR #42370](https://github.com/neovim/neovim/pull/42370) and fixed its `conceal_line` error in [PR #42634](https://github.com/neovim/neovim/pull/42634). The fork now carries no upstream commits.

Deleting a markdown file's last line, or a notification redraw, no longer stops you at a stack trace and a "Press ENTER" prompt. Links still read one row per entry. Files, options and config stay compatible.

# 🔵⋯ v0.1.0 (2026-10-22)

## 🟠⋯ Fixed for End Users
- 2026-10-22 - fix | read a list of links without a blank row under each entry. Carries upstream Neovim [PR #42370](https://github.com/neovim/neovim/pull/42370), pinned at `624dfb6136`, on upstream master `d714648b8e`.

A plan now fits about half again as much text on one screen. Files, options and config stay compatible. Screen positions, mouse clicks and `nvim_win_text_height()` follow the reflowed rows; the two stale ymd layout expectations have been updated and both affected suites pass on the fork and Homebrew.

---
title: neovim-rbf
---

neovim-rbf runs upstream Neovim's own unreleased fixes when our plugins need them. It carries no editor code of its own. Fork documentation, scripts and version metadata live in `rbf/`; the root files stay upstream's.

# 🔵⋯ Use

This is Tom's local editor build, with his existing configuration and plugins. It is not a public binary, a Homebrew formula, or the Neovim 0.13 release. Issues and contributions concerning the carried fix belong with upstream's PR.

# 🔵⋯ Current carry

Upstream [PR #42370](https://github.com/neovim/neovim/pull/42370), four commits pinned at head `624dfb6136`, makes text hidden by persistent extmarks stop taking screen width when lines wrap. A long hidden link target no longer leaves a blank row under its label. It also makes screen positions and mouse clicks follow the drawing.

The stack is upstream master `d714648b8e` → our setup, measurement scripts and release files → the four carried commits. Bookmark `nv-1` names the tip. The LSP completion conflict resolutions retain master's plaintext documentation behaviour and the PR's markdown screen expectations; `runtime/lua/vim/lsp/completion.lua` is byte-identical to master's.

`:syntax`, `matchadd()` and ephemeral conceal still wrap as upstream documents. Tab stops after hidden text are unchanged. ymd and typeless need no runtime changes. The two stale ymd layout expectations were updated; both affected suites pass on the fork and Homebrew.

# 🔵⋯ Build and install

Use macOS on Apple silicon with CMake, Ninja, the Xcode toolchain and Homebrew gettext. Run builds at utility priority. The example below assumes a jj workspace at `$EXTERNAL_DRIVE/src/worktrees/neovim-rbf/nv-1`. Run Git commands from the main colocated checkout, never from a jj workspace.

1. Reuse that workspace, or create it from the main checkout with `jj workspace add "$EXTERNAL_DRIVE/src/worktrees/neovim-rbf/nv-1" -r nv-1`. Set `W` to the workspace and `MAIN` to the main checkout.
2. Keep `rbf/VERSION`, this README and the changelog committed beneath the carry before verification. Then obtain the build id:
   ```sh
   ID=$(git -C "$MAIN" rev-parse --short=10 nv-1)
   cd "$W"
   ```
   This is the hash shown after `+g` in `nvim --version`. After verifying that build, a change may still land beneath the carry only if it touches nothing outside rbf/ — `git diff --stat <verified tip> nv-1 -- . ':(exclude)rbf'` must print nothing — and then the new tip is rebuilt and installed.
3. Build the dependencies and test binary:
   ```sh
   taskpolicy -c utility make CMAKE_BUILD_TYPE=RelWithDebInfo
   ```
4. Configure, build and install the Release binary:
   ```sh
   taskpolicy -c utility cmake -S . -B build-release -G Ninja \
     -DCMAKE_BUILD_TYPE=Release -DDEPS_PREFIX="$W/.deps/usr" \
     -DCMAKE_INSTALL_PREFIX="$HOME/.local/nvim-rbf/$ID"
   taskpolicy -c utility cmake --build build-release
   taskpolicy -c utility cmake --install build-release
   ```
   Each build has its own prefix, so open sessions retain their matching runtime. The Release build is used daily; functional tests use RelWithDebInfo. typeless exposes a pre-existing upstream assertion in the latter.
5. Once, build the fixed oracle without the carry. From the main checkout, `jj workspace add "$EXTERNAL_DRIVE/src/worktrees/neovim-rbf/nv-1-oracle" -r d714648b8e`. In that workspace run `taskpolicy -c utility make deps`, then repeat step 4 with its own `.deps/usr` and `-DCMAKE_INSTALL_PREFIX="$HOME/.local/nvim-rbf/oracle-d714648b8e"`.
6. After the human check passes, unlink Homebrew without uninstalling its keg, then activate the verified build:
   ```sh
   brew unlink neovim
   ln -sf "$HOME/.local/nvim-rbf/$ID/bin/nvim" "$HOME/local/bin/nvim.new"
   mv -f "$HOME/local/bin/nvim.new" "$HOME/local/bin/nvim"
   rehash
   ```
   This replaces the link atomically. Tom's login PATH places `~/.local/bin` first, `~/local/bin` before `~/homebrew/bin`. Keep the name `nvim` free in `~/.local/bin`.
7. Check a new login shell: `zsh -lic 'command -v nvim; nvim --version | head -2'`. It should report `~/local/bin/nvim`, the tip hash, and `Build type: Release`.

To go back, `brew link neovim && rm ~/local/bin/nvim && rehash`. New sessions start Homebrew's `nvim`, whatever version it is; existing sessions keep their build. Swap files recover with either build. Remove an old install prefix only after `lsof +D <prefix>` shows nothing using it.

If the wrong binary answers, run `rehash` and `command -v nvim` in a login shell. If runtime startup fails, `unset VIMRUNTIME`: build-tree tests require `VIMRUNTIME="$W/runtime"`, while an installed binary finds its own runtime. ymd itself still needs the SSD, just as it does with Homebrew's `nvim`.

# 🔵⋯ Check a base move

The next base move targets the `v0.13.0` tag. At every base move check PR #42370: merged → drop our four carried commits; open → rebase them; closed unmerged → keep carrying while ymd needs it. Drop each carry once upstream merges it. Stop and ask Tom if a rebase conflicts in C. Read the diff again before rebuilding.

Move the base by hand: `rbf/scripts/upstream-sync.sh` cannot target a tag yet and expects an `upstream` remote this repo does not have. `nv-1~4..nv-1` is exactly the carry in Git revision syntax; abandon those four commits with jj when dropping it.

Run the measurement before installing or switching a new build:

```sh
rbf/scripts/measure-blank-rows.sh --nvim "$W/build-release/bin/nvim" \
  --ymd <nvim.ymd> <ymd-projects-dir> <fork-projects-dir>
```

Requires Python 3. It walks markdown files, skipping `.git/` and `.jj/`, and measures text widths 80, 100, 120 and 160. `--nvim` defaults to `nvim` on PATH; `--oracle` defaults to `~/.local/nvim-rbf/oracle-d714648b8e/bin/nvim`. Build-tree binaries get their own runtime. `--widths "80 120"` chooses other widths. `--timeout <seconds>` bounds each binary's run (default 900); a timeout names the last width and file being measured. `--verbose` shows per-file progress on stderr, plus the oracle's per-file hits on stdout. `--verbose` also shows ymd's `Invalid pattern` config warnings. Any other `[ymd]` message containing `error`, in any case, fails its file, with or without `--verbose`; other ymd messages always print.

A wrapped row counts as blank when its drawn text cells are all blank and its line is drawn on more rows than its visible text needs: `ceil(visible width / width)`, where visible width is the line's display width with hidden ranges removed, plus conceal replacements and inline virtual text. A row of real spaces is visible text, so it's never excess. Width means text columns.

On the measured build only, the script checks that estimate: a line drawn on fewer rows than its visible text supposedly needs fails with `ERR <file>:<line>: visible-width estimate exceeds rows drawn` and exit 1. This canary catches an estimate running high on lines the build lays out correctly. It can't catch a high estimate on a line whose layout regressed: then the estimate equals the rows drawn, and that line's blank rows read 0. Each line is measured on a page where the cursor isn't on it. The oracle is exempt from the self-check; its total count must be above 0.

A clean run prints only the oracle summary, the build and file count, and one count per width. Offending `file:line`s appear under their width. Files that cannot be measured fail the run. Exit codes: 0 clean, 1 rows remain or measurement failed, 2 bad arguments, 3 the oracle counted nothing. Running with no arguments prints the full usage with defaults once to stderr and exits 2, with nothing on stdout. `--ymd` is required.

A nonzero result keeps the old build installed. Repeat the check even after upstream merges the fix: its final form may differ.

# 🔵⋯ Versions

The fork's version is in `rbf/VERSION`, its release history in `rbf/CHANGELOG.md`. Upstream's version files continue to track upstream.

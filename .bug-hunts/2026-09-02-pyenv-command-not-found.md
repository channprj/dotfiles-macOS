# Pyenv command not found in Zsh

## Defect observation

- **Symptom:** Running `pyenv` from the reporter's Zsh session returns `zsh: command not found: pyenv`. An installer also warns that `pyenv` has not been added to the load path.
- **Expected:** A new Zsh session should resolve the installed `pyenv` executable and initialize pyenv without startup warnings.
- **Environment:** macOS 26.6.2 (25G83), Zsh 5.9, pyenv 2.8.5 installed at `$HOME/.pyenv`, dotfiles commit `32c619a`. Both `~/.zshenv` and `~/.zshrc` are symlinks to this repository.
- **First seen:** Reported on 2026-09-02. The last known working version is unknown.

## Reproduction

- **Command:** `/bin/zsh -lic 'command -v pyenv; pyenv --version'`
- **Result:** `zsh:1: command not found: pyenv`, exit 127. The login-shell banner was omitted from this record because it is unrelated to command resolution.

## Minimal reproduction

`env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" /bin/zsh -dfc 'source "$HOME/dotfiles/sh/.zshenv"; whence -p pyenv || exit 127'` exits 127. An explicit inspection of Zsh's `path` array prints `MISSING` for `$HOME/.pyenv/bin`.

## Hypothesis ledger

| # | Hypothesis | Falsified if | Observed | Verdict |
|---|---|---|---|---|
| 1 | `pyenv` is not installed on this host. | A `pyenv` executable exists in a standard installation prefix or the package manager reports it installed. | `$HOME/.pyenv/bin/pyenv` exists and is executable; Homebrew-linked locations do not exist. | Falsified. |
| 2 | `pyenv` is installed under `$HOME/.pyenv/bin`, but the repository-managed Zsh startup PATH omits that directory. | A clean shell that loads `sh/.zshenv` includes `$HOME/.pyenv/bin` in `PATH`. | The clean-shell probe printed `MISSING`; `whence -p pyenv` exited 127. | Survived. |
| 3 | `.zshrc` cannot repair the missing PATH because pyenv initialization is gated on `pyenv` already resolving as a command. | `.zshrc` adds `$PYENV_ROOT/bin` or invokes `$PYENV_ROOT/bin/pyenv` before any command-existence guard. | `.zshrc` uses `if (( $+commands[pyenv] )); then eval "$(pyenv init -)"`; it neither adds the bin directory nor invokes an absolute path first. | Survived. |
| 4 | Adding `$HOME/.pyenv/bin` would still fail because the installed executable or its Zsh initialization is broken. | A clean Zsh with only that directory prepended can run `pyenv --version` and `pyenv init -`. | The isolated probe printed `pyenv 2.8.5` and `INIT_OK`, exit 0. | Falsified. |

## Fix check

- **Regression check:** `tests/shell_startup_test.zsh` now requires `$PYENV_ROOT/bin` in the PATH established by `.zshenv`, before the pyenv shims and Homebrew, while retaining the existing uniqueness assertions.
- **Before the fix:** `/bin/zsh tests/shell_startup_test.zsh` failed with `FAIL: pyenv bin is missing from PATH`, exit 1.
- **After the fix:** The same command passed with `PASS: shell startup is quiet, portable, guarded, and PATH-idempotent`, exit 0.
- **Real login-shell verification:** `/bin/zsh -lic '... pyenv --version ...'` resolved `$HOME/.pyenv/bin/pyenv`, printed `pyenv 2.8.5`, and reported matching configured and effective pyenv roots, exit 0.
- **Full suite:** `tests/run.sh` passed every deterministic test. ShellCheck was skipped because it is not installed.
- **Instrumentation cleanup:** `rg --hidden -n 'BUGHUNT' . -g '!.git/**' -g '!.bug-hunts/**'` returned no matches.

## Closure

- **Cause:** The shared Zsh environment added `$HOME/.pyenv/shims` but omitted the actual `$HOME/.pyenv/bin` directory. Interactive initialization in `.zshrc` was guarded by `(( $+commands[pyenv] ))`, so the missing executable path caused the initializer to skip itself. The pyenv installation was healthy; the startup configuration created a command-resolution cycle.
- **Fix:** Define `PYENV_ROOT` with a HOME-relative default in `.zshenv`, and add both `$PYENV_ROOT/bin` and `$PYENV_ROOT/shims` ahead of Homebrew/system Python paths. Keep the existing interactive `pyenv init -` path in `.zshrc`.
- **Falsified:** Pyenv is not installed; the installed executable or Zsh initializer is broken.
- **Blast radius:** A repository-wide search found only the shared `.zshenv` PATH construction, the guarded `.zshrc` initializer, and the shell-startup regression test. Bash is not managed by this active dotfiles path, and no second active pyenv initialization site was found.
- **Left open:** The installation method that placed pyenv under `$HOME/.pyenv` rather than Homebrew's linked prefix was not established, but it is not needed to explain or verify this failure. The fixed configuration supports that standard per-user location and honors an existing `PYENV_ROOT` override.

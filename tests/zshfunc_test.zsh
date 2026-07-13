#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipefail

typeset -a calls=()

tccutil() {
  calls+=("$*")
}

source "${0:A:h:h}/sh/.zshfunc"

if (( ! $+functions[reset-iterm2-permissions] )); then
  print -u2 "reset-iterm2-permissions is not defined"
  exit 1
fi

reset-iterm2-permissions

typeset -a expected=(
  "reset SystemPolicyRemovableVolumes com.googlecode.iterm2"
  "reset SystemPolicyAllFiles com.googlecode.iterm2"
)

if [[ "${(j:\n:)calls}" != "${(j:\n:)expected}" ]]; then
  print -u2 "unexpected tccutil calls"
  print -u2 "expected: ${(j: | :)expected}"
  print -u2 "actual:   ${(j: | :)calls}"
  exit 1
fi

print "PASS: reset-iterm2-permissions resets both iTerm2 permissions"

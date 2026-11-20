#!/usr/bin/env bash

heredoc=$(cat <<TEXT
some text
TEXT
)
echo "${heredoc}"

quoted="$(
  if false; then
    echo never
  fi
  echo yes
)"

# Bash reports the commands of a substitution after it, Bashcov moves them back
echo "${quoted}"
echo "done"

helper() {
  echo "helper $1"
}

# commands before the substitution, called from it or nested in it stay apart
echo piped | cat
called="$(
  helper one
  if [ -n "${called:-}" ]; then
    echo never
  fi
  true >&2
  echo "$(echo nested)"
)"
echo "${called}"

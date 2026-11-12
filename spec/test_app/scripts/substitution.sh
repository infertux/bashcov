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

# Bash reports the commands of a substitution after it, not on their own lines
echo "${quoted}"
echo "done"

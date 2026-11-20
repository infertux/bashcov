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

looped="$(
  for word in a b; do
    echo "${word}"
  done
  case "${word:-}" in
    a) echo never ;;
    *) echo other ;;
  esac
)"
echo "${looped}"

first="$(
  # echo same
  true
  echo same
)"
second="$(
  echo same
)"
echo "${first}${second}"

quoted_hash="$(
  echo "before # literal
second line"
  echo after
)"
(
  inner="$(
    true
    echo same
  )"
  outer="$(
    echo same
  )"
  echo "${inner}${outer}"
)
counted="$(
  for ((count = 0; count < 1; count++)); do
    echo "${count}"
  done
)"
echo "${quoted_hash}${counted}"
(
  echo again
  echo again
)

ansi="$(
  echo $'it\'s # literal'
  echo $"loc"
)"
echo "${ansi}"

printf '%s\n' "$(
  true
  echo same
)" "$(
  if false; then
    echo same
  fi
)"
arm="$(
  case x in
    y) echo same ;;
    x) echo same ;;
  esac
)"
forever="$(
  for ((;;)); do
    echo "${arm}"
    break
  done
)"
echo "${forever}"
commented="$(
  if true; then
    # Bash 5.2 drops these lines when it rebuilds the text,
    # but older versions count them
    # as written
    echo "${forever}"
  else
    echo "${forever}"
  fi
)"
nest() {
  if (($1 > 0)); then
    inner="$(
      if false; then
        echo "${commented}"
      fi
      nest 0
    )"
  else
    echo "${commented}"
  fi
}
nest 1

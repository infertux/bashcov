#!/usr/bin/env bash

echo '
hello
there
'

echo '
Blah blah
Test
'

echo '
Try this command:

    $ fubar baz

'

echo '
Your program has been compiled successfully.
You can use "fubar" to run it:

    fubar baz

Run "fubar" for more commands.
'

synopsis='
Usage: fubar <PATH> [OPTIONS]
'

echo "$synopsis"

getTodayQuery() {
  read -rd '' query <<-SQL || true
SELECT
  CASE
    WHEN AREA.title IS NOT NULL THEN AREA.title
  END,
  TASK.title,
  "things:///show?id=" || TASK.uuid
FROM TASKTABLE as TASK
SQL
  echo "${query}"
}

getTodayQuery

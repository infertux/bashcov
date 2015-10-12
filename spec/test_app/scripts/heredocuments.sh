#!/bin/bash

cat << EOF
Showing text
EOF

cat <<- END
   Another couple
of lines
 - list 1
 - list 2
END

cat <<- FINISH
 Complex
   important
      message
FINISH


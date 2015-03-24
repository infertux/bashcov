#!/bin/bash

cd $(dirname $0)

find scripts -type f -perm -111 -exec bash '{}' \;

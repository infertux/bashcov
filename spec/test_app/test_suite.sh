#!/bin/bash

cd $(dirname $0)

# `date` is sent on stdin for each file
date | find scripts -type f -executable -exec '{}' \;


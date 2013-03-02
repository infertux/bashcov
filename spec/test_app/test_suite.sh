#!/bin/bash

cd $(dirname $0)

find scripts -type f -executable -exec '{}' \;


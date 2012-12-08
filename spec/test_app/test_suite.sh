#!/bin/bash

cd $(dirname $0)
find scripts -name "*.sh" -exec "{}" \;


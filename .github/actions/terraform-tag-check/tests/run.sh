#!/usr/bin/env bash
#
# Runs the terraform-tag-check unit and end-to-end tests.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if ! python3 -c 'import yaml' > /dev/null 2>&1; then
  PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --quiet --disable-pip-version-check --user 'pyyaml>=6,<7'
fi

python3 -m unittest discover -s . -p 'test_*.py' -v

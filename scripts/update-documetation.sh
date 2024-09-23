#!/usr/bin/env bash
#
# Copyright 2023 Appvia Ltd <info@appvia.io>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#
# Set the base directory
DIRECTORIES="${1:-"terraform-aws-*"}"
BASE_DIR=$(pwd)

for dir in ${DIRECTORIES}; do
  print "%s %-20s" "Checking is documentation is up to date in:" $dir
  cd $dir
  # step: ensure the directory is not dirty
  if [[ $(git status --porcelain) ]]; then
    echo "[DIRTY]"
    cd $BASE_DIR || {
      echo "Failed to return to the base directory"
      exit 1
    }
    continue
  fi
  # step: ensure this is a git repository
  if [[ ! -d .git ]]; then
    echo "[NOT GIT]"
    cd $BASE_DIR || {
      echo "Failed to return to the base directory"
      exit 1
    }
    continue
  fi
  # step: ensure we are on the main branch
  git checkout main > /dev/null
  # step: pull the latest changes
  git pull > /dev/null
  # step: generate the documentation
  make documentation > /dev/null
  # step: check if there is a change in the documentation
  if [[ ! $(git status --porcelain) ]]; then
    echo "[NO CHANGE]"
    cd $BASE_DIR || {
      echo "Failed to return to the base directory"
      exit 1
    }
    continue
  fi
  # step: create a new branch
  git checkout -b update-documentation > /dev/null
  # step: add the files to staging
  git add . > /dev/null
  # step: commit the change and push it to the main branch
  git commit -m "docs: updating the documentation for the terraform module" > /dev/null
  # step: push the changes and create a pull request
  gh pr create > /dev/null
  # step: print the message
  echo "[UPDATED]"
  # step: return to the base directory
  cd $BASE_DIR || {
    echo "failed to return to the base directory"
    exit 1
  }
done

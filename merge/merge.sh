#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

function home() {
  # change dir to script location
  cd "$SCRIPT_DIR"
}

function merge() {
  home
  cd docs
  local name=$1
  git remote add $name ../$name
  git fetch $name
  git merge --allow-unrelated-histories --no-edit $name/master
  git remote remove $name
  home
}

# create unified docs repository
home
rm -rf ./docs
git init docs

# process open source
rm -rf ./calico/
git clone git@github.com:projectcalico/calico.git
cd calico 
git filter-repo --path calico/ --path-rename calico/: --path-rename _data/versions.yml:calico/_data/versions.yml
merge calico

# process enterprise
rm -rf ./calico-private/
git clone git@github.com:tigera/calico-private.git
cd calico-private
git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
git filter-repo --path-glob "**/*.md" --path _includes/ --path _data/
merge calico-private

# process cloud
rm -rf ./calico-cloud/
git clone git@github.com:tigera/calico-cloud.git
cd calico-cloud
git filter-repo --to-subdirectory-filter calico-cloud/
git filter-repo --path-glob "**/*.md" --path _includes/ --path _data/
merge calico-cloud

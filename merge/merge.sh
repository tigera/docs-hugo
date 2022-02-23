#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(realpath "${SCRIPT_DIR}")"

function cdsl() {
  # change dir to script location
	cd "$SCRIPT_DIR"
}

function docs_merge() {
  cdsl
  cd docs
	local name=$1
  git remote add $name ../$name
  git fetch $name
  git merge --allow-unrelated-histories --no-edit $name/master
  git remote remove $name
	cdsl
}

# set pwd to this script location
cdsl

# create unified docs repository
rm -rf ./docs
git init docs

# process open source
rm -rf ./calico/
git clone git@github.com:projectcalico/calico.git
cd calico 
git filter-repo --path calico/
docs_merge calico

# process enterprise
rm -rf ./calico-private/
git clone git@github.com:tigera/calico-private.git
cd calico-private
git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
docs_merge calico-private

# process cloud
rm -rf ./calico-cloud/
git clone git@github.com:tigera/calico-cloud.git
cd calico-cloud
git filter-repo --to-subdirectory-filter calico-cloud/
docs_merge calico-cloud


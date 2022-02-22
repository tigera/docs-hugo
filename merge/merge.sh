#!/usr/bin/env bash
set -euo pipefail

# change dir to script location
cd "$(dirname "$0")"

# create unified docs repository
rm -rf ./docs
mkdir -p ./docs
cd docs
git init
cd -

# process open source
rm -rf ./calico/
git clone git@github.com:projectcalico/calico.git
cd calico 
git filter-repo --path calico/
cd -
cd docs
git remote add calico ../calico
git fetch calico
git merge --allow-unrelated-histories --no-edit calico/master
git remote remove calico
cd -

# process enterprise
rm -rf ./calico-private/
git clone git@github.com:tigera/calico-private.git
cd calico-private
git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
cd -
cd docs
git remote add calico-private ../calico-private
git fetch calico-private
git merge --allow-unrelated-histories --no-edit calico-private/master
git remote remove calico-private
cd -

# process cloud
rm -rf ./calico-cloud/
git clone git@github.com:tigera/calico-cloud.git
cd calico-cloud
git filter-repo --to-subdirectory-filter calico-cloud/
cd -
cd docs
git remote add calico-cloud ../calico-cloud
git fetch calico-cloud
git merge --allow-unrelated-histories --no-edit calico-cloud/master
git remote remove calico-cloud
cd -

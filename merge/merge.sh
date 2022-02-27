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
  git merge --allow-unrelated-histories --no-edit -X theirs $name/master
  git remote remove $name
  home
}

function fixup() {
  local name=$1
  git filter-repo \
          --path-glob "**/*.md" \
          --path $name/_includes/ \
          --path $name/_plugins/ \
          --path $name/_layouts/ \
          --path $name/_data/ \
          --path $name/_sass/ \
          --path-rename $name/_includes/:_includes/$name/ \
          --path-rename $name/_plugins/:_plugins/ \
          --path-rename $name/_layouts/:_layouts/$name/ \
          --path-rename $name/_data/:_data/$name/ \
          --path-rename $name/_sass/:_sass/$name/
  find . -type f -print0 | xargs -0 sed -r -i 's/\{%\s+include\s+\/(.*)\s+%}/{% include \1 %}/g'
  find . -type f -print0 | xargs -0 sed -r -i "s/\{%\s+include\s+(.*)\s+%}/{% include ${name}\/\1 %}/g"
  git add .
  git commit -m "redirect includes to global _includes"
}

# create unified docs repository
home
rm -rf ./docs
git init docs

# process open source
rm -rf ./calico/
git clone git@github.com:projectcalico/calico.git
cd calico 
git filter-repo --path calico/ --path-rename calico/:
mkdir -p calico/_data
cp _data/versions.yml calico/_data/versions.yml
cat <<EOF >./Gemfile
# frozen_string_literal: true
source "https://rubygems.org"
git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }
gem 'jekyll', '~>4.0.0'
group :jekyll_plugins do
  gem 'jekyll-redirect-from'
  gem 'jekyll-seo-tag'
  gem 'jekyll-sitemap'
  gem 'jekyll-include-cache'
end
EOF
sed -r -i "s/\s+- jekyll-sitemap/  - jekyll-sitemap\n  - jekyll-include-cache/g" ./_config.yml
git add .
git commit -m "copy versions.yml"
merge calico

# process enterprise
rm -rf ./libcalico-go
mkdir -p ./libcalico-go
rm -rf ./calico-enterprise/
git clone git@github.com:tigera/calico-private.git calico-enterprise
cd calico-enterprise
cp -r libcalico-go/* ../libcalico-go
git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
fixup calico-enterprise
merge calico-enterprise

# process cloud
rm -rf ./calico-cloud/
git clone git@github.com:tigera/calico-cloud.git
cd calico-cloud
git filter-repo --to-subdirectory-filter calico-cloud/
fixup calico-cloud
merge calico-cloud

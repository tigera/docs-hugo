#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

function home() {
  # change dir to script location
  cd "$SCRIPT_DIR"
}

function merge() {
  local repo=$1
  local name=$2
  home
  cd "$repo"
  git remote add $name ../$name
  git fetch $name
  # git merge --allow-unrelated-histories --no-edit -X theirs $name/master
  git merge --allow-unrelated-histories --no-edit $name/master
  git remote remove $name
  home
}

function jekyll_fixup() {
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
  find . -type f -print0 | xargs -0 sed -r -i 's/\{%\s*include\s+\/(.*)%}/{% include \1 %}/g'
  find . -type f -print0 | xargs -0 sed -r -i "s/\{%\s*include\s+(.*)%}/{% include ${name}\/\1 %}/g"
  find . -type f -print0 | xargs -0 sed -r -i "s/\{%\s*include_cached\s+(.*)%}/{% include ${name}\/\1 %}/g"
  git add .
  git commit -m "update content for jekyll"
}

function create_jekyll() {
  # create unified jekyll repository
  home
  rm -rf ./jekyll
  git init jekyll

  # process open source
  rm -rf ./calico/
  git clone git@github.com:projectcalico/calico.git
  cd calico
  git filter-repo --path calico/ --path-rename calico/:
  mkdir -p calico/_data
  cp _data/versions.yml calico/_data/versions.yml
  git add .
  git commit -m "copy versions.yml"
  merge jekyll calico

  # process enterprise
  rm -rf ./libcalico-go
  mkdir -p ./libcalico-go
  rm -rf ./calico-enterprise/
  git clone git@github.com:tigera/calico-private.git calico-enterprise
  cd calico-enterprise
  cp -r libcalico-go/* ../libcalico-go
  git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
  jekyll_fixup calico-enterprise
  merge jekyll calico-enterprise

  # process cloud
  rm -rf ./calico-cloud/
  git clone git@github.com:tigera/calico-cloud.git
  cd calico-cloud
  git filter-repo --to-subdirectory-filter calico-cloud/
  jekyll_fixup calico-cloud
  merge jekyll calico-cloud
}

function hugo_fixup() {
  local name=$1
  local displayName=$2
  local weight=$3
  # remove charts for now...
  git filter-repo --path $name/_includes/charts/ --invert-paths
  git filter-repo \
    --path-glob "**/*.md" \
    --path $name/_data/ \
    --path $name/images/ \
    --path $name/_includes/ \
    --path-rename $name/_data/:data/$name/ \
    --path-rename $name/images/:static/images/$name/ \
    --path-rename $name/_includes/:layouts/partials/$name/ \
    --filename-callback '
  if filename is None:
    return filename
  if filename.startswith(b"layouts/"):
    return filename
  if filename.endswith(b".md"):
    if filename.endswith(b"_index.md"):
      return b"content/en/docs/" + filename
    elif filename.endswith(b"index.md"):
      return b"content/en/docs/" + filename.removesuffix(b"index.md") + b"_index.md"
    else:
      return b"content/en/docs/" + filename
  else:
    return filename
  '

  # convert all liquid includes to partials
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%\s*include\s+\/(.*?)\s*%}/{{ partial ${name}\/\1 . }}/g"
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%\s*include\s+(.*?)\s*%}/{{ partial ${name}\/\1 . }}/g"
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%\s*include_cached\s+(.*?)\s*%}/{{ partial ${name}\/\1 . }}/g"

  # convert all comments to comments in hugo
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%\s*comment\s*%}(.*?){%\s*endcomment\s*%}/{{< comment >}}\${1}{{< \/comment >}}/gs"
  find ./layouts -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%\s*comment\s*%}(.*?){%\s*endcomment\s*%}/{{\/*\${1}*\/}}/gs"

  # convert all liquid which strip whitespace to TODO comments
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%-(.*?)-%}/{{\/\* -TODO\[merge\]-: \1 \*\/}}/gs"
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%-(.*?)%}/{{\/\* -TODO\[merge\]: \1 \*\/}}/gs"
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{%(.*?)-%}/{{\/\* TODO\[merge\]-: \1 \*\/}}/gs"

  # convert all go templates which strip whitespace to TODO comments
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{-(.*?)-}}/{{\/\* -TODO\[merge\]-: \1 \*\/}}/gs"
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{-(.*?)}}/{{\/\* -TODO\[merge\]: \1 \*\/}}/gs"
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{(.*?)-}}/{{\/\* TODO\[merge\]-: \1 \*\/}}/gs"

  # capture all else which is not a comment or shortcode
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{([^\/<%])(\s*)(.*?)\s*}}/{{\/\* TODO\[merge\]: \1\2\3 \*\/}}/gs"

  # convert illegal front-matter that hugo won't allow
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -pi -e "s/description:(.*?)\{\{\/\* TODO\[merge\]: site\.prodname \*\/}}/description:\${1}${displayName}/"

  # make sure each top-level dir has an _index.md with cascading front-matter - add prodname and weight
  if [[ -f "./content/en/docs/$name/_index.md" ]]; then
    perl -0777 -pi -e "s/^---\$(.*?)^---\$/\n---\${1}weight: ${weight}\ncascade:\n  prodname: \"${displayName}\"\n---\n/gsm" "./content/en/docs/$name/_index.md"
  else
    cat >"./content/en/docs/$name/_index.md" <<EOF
---
title: "${displayName}"
description: "${displayName}"
weight: ${weight}
cascade:
  prodname: "${displayName}"
---
EOF
  fi

  # now start selectively converting our TODO comments to what works in hugo

  # convert 'prodname'
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*site\.prodname\s*\*\/}}/{{< param prodname >}}/g"
  find ./layouts -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*site\.prodname\s*\*\/}}/{{ .Params.prodname }}/g"

  # convert partials
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*partial\s+(.*?)\s*\*\/}}/{{ partial \1 }}/gs"

  # convert images
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*site\.baseurl\s*\*\/}}\/images\/([a-zA-Z0-9_\/\.\-]+?)/\/images\/${name}\/\${1}/gs"

  git add .
  git commit -m "updating content for hugo"
}

function create_hugo() {
  # create unified hugo repository
  home
  rm -rf ./hugo
  git init hugo

  # process open source
  rm -rf ./calico/
  git clone git@github.com:projectcalico/calico.git
  cd calico
  git filter-repo --path calico/
  hugo_fixup calico "Calico" 10
  merge hugo calico

  # process enterprise
  rm -rf ./calico-enterprise/
  git clone git@github.com:tigera/calico-private.git calico-enterprise
  cd calico-enterprise
  git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
  hugo_fixup calico-enterprise "Calico Enterprise" 20
  merge hugo calico-enterprise

  # process cloud
  rm -rf ./calico-cloud/
  git clone git@github.com:tigera/calico-cloud.git
  cd calico-cloud
  git filter-repo --to-subdirectory-filter calico-cloud/
  hugo_fixup calico-cloud "Calico Cloud" 30
  merge hugo calico-cloud
}

type=${1:-}
if [[ "$type" == "hugo" ]]; then
  create_hugo
  home
  cd ..
  git remote remove hugo &>/dev/null || true
  git remote add hugo merge/hugo
  git fetch hugo
  git merge --squash --allow-unrelated-histories --no-edit hugo/master
  git remote remove hugo
  home
elif [[ "$type" == "jekyll" ]]; then
  create_jekyll
else
  echo "Need to specify either 'hugo' or 'jekyll'. For example: ./merge.sh hugo"
fi

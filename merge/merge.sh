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

function create_placeholder_index() {
  local path=$1
  local title=$2
  mkdir -p "$path"
  cat >"$path/_index.md" <<EOF
---
title: "${title}"
description: "${title}"
---
EOF
}

function create_placeholder_yaml() {
  local path=$1
  local name=$2
  mkdir -p "$path"
  cat >"$path/$name" <<EOF
description: "<PLACEHOLDER> This is a placeholder for future content"
EOF
}

function hugo_fixup() {
  local name=$1
  local displayName=$2
  local weight=$3

  # first remove some files we don't want / need
  git filter-repo \
    --path $name/_includes/charts/ \
    --path $name/AUTHORS.md \
    --path $name/DOC_STYLE_GUIDE.md \
    --path $name/CONTRIBUTING_MANIFESTS.md \
    --path $name/README.md \
    --path $name/releases.md \
    --path $name/hack/ \
    --invert-paths

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

  # add placeholders for missing pages
  create_placeholder_index "./content/en/docs/$name/reference/installation/api" "<PLACEHOLDER> ${displayName} Installation API"

  # now start selectively converting our TODO comments to what works in hugo

  # convert 'prodname'
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*site\.prodname\s*\*\/}}/{{< param prodname >}}/g"
  find ./layouts -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*site\.prodname\s*\*\/}}/{{ .Params.prodname }}/g"

  # remove page.description since the description is already displayed through the docsy theme
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*page\.description\s*\*\/}}//g"

  # convert partials
  find ./content -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*partial\s+(.*?)\s*\*\/}}/{{ partial \1 }}/gs"

  # convert images
  find . -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\{\{\/\* TODO\[merge\]:\s*site\.baseurl\s*\*\/}}\/images\/([a-zA-Z0-9_\/\.\-]+?)/\/images\/${name}\/\${1}/gs"

  # convert links
  find ./content -name "*.md" -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\[(.*?)\]\s*\(\s*\{\{\/\* TODO\[merge\]:\s*site\.baseurl\s*\*\/}}\/manifests(.*?)\s*\)/TODO[manifests]:[\${1}]({{\/* ref \"\/manifests\/${name}\${2}\" *\/}})/gs"
  find ./content -name "*.md" -not -path '*/.*' -type f -print0 | xargs -0 perl -0777 -pi -e "s/\[(.*?)\]\s*\(\s*\{\{\/\* TODO\[merge\]:\s*site\.baseurl\s*\*\/}}(.*?)\s*\)/[\${1}]({{< ref \"\/docs\/${name}\${2}\" >}})/gs"
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
  #create_placeholder_yaml "./content/en/docs/calico/manifests" "calico-etcd.yaml"
  create_placeholder_index "./content/en/docs/calico/getting-started/windows-calico/standard" "<PLACEHOLDER> This is a placeholder for future content"
  # temporarily remove s link in the manifests to libcalico-go
  # git rm ./static/manifests/calico/ocp/crds/calico
  git add .
  git commit -m "updating content for hugo"
  merge hugo calico

  # process enterprise
  rm -rf ./calico-enterprise/
  git clone git@github.com:tigera/calico-private.git calico-enterprise
  cd calico-enterprise
  git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
  hugo_fixup calico-enterprise "Calico Enterprise" 20
  #create_placeholder_yaml "./content/en/docs/calico-enterprise/manifests" "fortinet-device-configmap.yaml"
  #create_placeholder_yaml "./content/en/docs/calico-enterprise/manifests" "fortimanager-device-configmap.yaml"
  # rename one index file back because it is referenced directly
  git mv "./content/en/docs/calico-enterprise/getting-started/openshift/installation/_index.md" "./content/en/docs/calico-enterprise/getting-started/openshift/installation/index.md"
  git add .
  git commit -m "updating content for hugo"
  merge hugo calico-enterprise

  # process cloud
  rm -rf ./calico-cloud/
  git clone git@github.com:tigera/calico-cloud.git
  cd calico-cloud
  git filter-repo --to-subdirectory-filter calico-cloud/
  hugo_fixup calico-cloud "Calico Cloud" 30
  #create_placeholder_yaml "./content/en/docs/calico-cloud/manifests" "fortinet-device-configmap.yaml"
  #create_placeholder_yaml "./content/en/docs/calico-cloud/manifests" "fortimanager-device-configmap.yaml"
  git add .
  git commit -m "updating content for hugo"
  merge hugo calico-cloud
}

function create_antora_destination () {
    # Creates the destination file structure and demo configuration files.

    echo "CD to directory above script location"
    # Creates directory structure
    mkdir -p calico/modules/ROOT/pages \
	    calico/modules/ROOT/images \
    	calico-enterprise/modules/ROOT/pages \
    	calico-enterprise/modules/ROOT/images \
    	calico-cloud/modules/ROOT/pages \
    	calico-cloud/modules/ROOT/images

    echo "Created directories"

    # Creates antora-playbook.yml with demo content.
    cat > ./antora-playbook.yml <<EOF
site:
  title: Calico Docs
  start_page: calico::index.adoc
content:
  sources:
  - url: .
    branches: HEAD
    #start_path: calico
    start_paths: calico, calico-enterprise, calico-cloud

#Default UI:
ui:
  bundle:
    url: https://gitlab.com/antora/antora-ui-default/-/jobs/artifacts/HEAD/raw/build/ui-bundle.zip?job=bundle-stable
    snapshot: true

#Lisk Documentation UI:
#ui:
  #bundle:
    #url: https://github.com/LiskHQ/lisk-docs/raw/main/ui/build/ui-bundle.zip
    #snapshot: true
EOF

    echo "Created playbook"
    # Add component configurations.
    # Creates antora.yaml at the root of each component.

    # Starting with Calico ...

    cat > ./calico/antora.yml <<EOF
name: calico
title: Calico Open Source
version: 3.23
asciidoc:
  attributes:
    calico-open-source: ''
    product-name: Calico
nav:
- modules/ROOT/nav-os.adoc
EOF

    cat > ./calico-enterprise/antora.yml <<EOF
name: calico-enterprise
title: Calico Enterprise
version: 3.14
asciidoc:
  attributes:
    calico-enterprise: ''
    product-name: Calico Enterprise
nav:
- modules/ROOT/nav-ce.adoc
EOF
    cat > ./calico-cloud/antora.yml <<EOF
name: calico-cloud
title: Calico Cloud
version: ~
asciidoc:
  attributes:
    calico-enterprise: ''
    product-name: Calico Enterprise
nav:
- modules/ROOT/nav-ce.adoc
EOF
    echo "Created playbooks."

    # Creating placeholder index.adoc file.
    # Creates index in calico/modules/ROOT/ and creates symlink in other two components.

    cat > ./calico/modules/ROOT/pages/index.adoc <<EOF
= Welcome to {product-name}!

== An overview of all things Calico

== Calico, Enterprise, Cloud

asdfasdf

== Getting started

asdfasdf

=== System administrators

https://tigera.io[lksdflkj]

ifdef::calico-open-source[]
Open Source!
endif::[]

ifdef::calico-enterprise[]
Enterprise!
endif::[]

ifdef::calico-cloud[]
Cloud!
endif::[]

ifndef::calico-cloud[]
It's OS or CE!
endif::[]

ifndef::calico-enterprise[]
It's OS or CC!
endif::[]

ifndef::calico-open-source[]
It's CE or CC!
endif::[]
EOF

    # TEMP Copies index.adoc into other components.
    cp ./calico/modules/ROOT/pages/index.adoc ./calico-enterprise/modules/ROOT/pages/index.adoc
    cp ./calico/modules/ROOT/pages/index.adoc ./calico-cloud/modules/ROOT/pages/index.adoc
    # //TODO// Sort out symlinks for index
    ## Creates symlinks for index.adoc in CE and CC components.
    #ln -s ./calico/modules/ROOT/pages/index.adoc ./calico-enterprise/modules/ROOT/pages/index.adoc
    #ln -s ./calico/modules/ROOT/pages/index.adoc ./calico-cloud/modules/ROOT/pages/index.adoc

    # Creates basic nav.adoc files with index.
    cat > ./calico/modules/ROOT/nav-os.adoc <<EOF
* xref:index.adoc[]
EOF
    cat > ./calico-enterprise/modules/ROOT/nav-ce.adoc <<EOF
* xref:index.adoc[]
EOF
    cat > ./calico-cloud/modules/ROOT/nav-cc.adoc <<EOF
* xref:index.adoc[]
EOF
    git add .
    git commit -m "Added antora demo files"
    home
}

function antora_fixup () {
  local name=$1

  # Remove files from Jekyll sites we don't need.
  git filter-repo \
    --path $name/404.html \
    --path $name/DOC_STYLE_GUIDE.md \
    --path $name/AUTHORS.md \
    --path $name/_data/ \
    --path $name/scripts/ \
    --path $name/robots.txt \
    --path $name/releases.md\
    --path $name/netlify/ \
    --path $name/netlify.toml \
    --path $name/js/ \
    --path $name/index.html \
    --path $name/hack \
    --path $name/fonts/ \
    --path $name/css/ \
    --path $name/_layouts/ \
    --path $name/_sass/ \
    --path $name/_plugins/ \
    --path $name/_config_null.yml \
    --path $name/_config_dev.yml \
    --path $name/_config.yml \
    --path $name/README.md \
    --path $name/Makefile \
    --path $name/LICENSE \
    --path $name/Gemfile \
    --path $name/_includes \
    --path $name/.gitignore \
    --invert-paths

  git filter-repo \
    --path $name/CONTRIBUTING_MANIFESTS.md \
    --path $name/Dockerfile-docs \
    --path $name/Jenkinsfile \
    --path $name/docs_test/ \
    --path $name/git-hooks/ \
    --path $name/helm-tests/ \
    --path $name/htmlproofer.sh \
    --path $name/install-git-hooks \
    --path $name/manifest-templates/ \
    --path $name/release-scripts/ \
    --path $name/tests/ \
    --invert-paths

  git filter-repo \
    --path $name/index.md \
    --path $name/manifests/ \
    --path $name/workload\
    --path $name/bin/ \
    --path $name/.semaphore \
    --invert-paths

  # Delete index.md files, but not all.
  if [ "$name" == "calico" ]; then
  mv calico/calico-enterprise/index.md calico/calico-enterprise/walrus.md
  find . -type f -name "index.md" -delete
  mv calico/calico-enterprise/walrus.md calico/calico-enterprise/index.md
  else
  find . -type f -name "index.md" -delete
  fi

  # Move files to expected location in preparation for Antora merge.
  mkdir -p $name/modules/ROOT/pages
  mv $name/modules $name/.modules
  mv $name/* $name/.modules/ROOT/pages
  mv $name/.modules $name/modules

  # Move images to expected images location.
  mv $name/modules/ROOT/pages/images $name/modules/ROOT/
  # Fix heading nonsense
  # //TODO// Might benefit from a logic that checks whether a file goes from one # to three ###, then continutes.
  egrep -rl "^#{3}[[:space:]]" . | xargs sed -r -i '' -e 's/^#{3}[[:space:]]/## /g'
  egrep -rl "^#{4}[[:space:]]" . | xargs sed -r -i '' -e 's/^#{4}[[:space:]]/### /g'
  egrep -rl "^#{5}[[:space:]]" . | xargs sed -r -i '' -e 's/^3{5}[[:space:]]/#### /g'

  # Convert Markdown to Asciidoc
  find ./ -name "*.md" \
    -type f \
    -exec sh -c \
    'kramdoc --format=GFM \
        --wrap=ventilate \
        --output={}.adoc {}' \;
  # Rename converted files to .adoc and remove .md files.
  find . -type f -name "*.md.adoc" | rename -s .md.adoc .adoc
  find . -type f -name "*.md" -delete
  grep -rl '{{site.prodname}}' . | xargs sed -i "" -e 's/{{site.prodname}}/{product-name}/g'
}
function create_antora() {
  # create unified antora repository
  home
  rm -rf antora
  git init antora
  cd antora
  create_antora_destination

  # process open source

  rm -rf calico/
  git clone git@github.com:projectcalico/calico.git
  cd calico
  git filter-repo --path calico/
  antora_fixup calico
  touch test.txt # Was getting 'nothing to commit' error. This sorts it for now.
  git add .
  git commit -m "updating content for antora"
  merge antora calico

  # process enterprise
  rm -rf ./calico-enterprise/
  git clone git@github.com:tigera/calico-private.git calico-enterprise
  cd calico-enterprise
  git filter-repo --path calico/ --path-rename calico/:calico-enterprise/
  antora_fixup calico-enterprise
  touch test.txt # Was getting 'nothing to commit' error. This sorts it for now.
  git add .
  git commit -m "updating content for antora"
  merge antora calico-enterprise

  # process cloud
  rm -rf ./calico-cloud/
  git clone git@github.com:tigera/calico-cloud.git
  cd calico-cloud
  git filter-repo --to-subdirectory-filter calico-cloud/
  antora_fixup calico-cloud
  touch test.txt # Was getting 'nothing to commit' error. This sorts it for now.
  git add .
  git commit -m "updating content for antora"
  merge antora calico-cloud
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
elif [[ "$type" == "antora" ]]; then
  create_antora
  home
else
  echo "Need to specify either 'hugo' or 'jekyll'. For example: ./merge.sh hugo"
fi

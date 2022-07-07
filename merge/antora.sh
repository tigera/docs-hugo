#!/usr/bin/env bash

### NOTE ###
# This Antora-specific script will be added to merge.sh once the kinks are ironed out
# //TODO// #
# * [X] Move component image folders into modules/ROOT/
# * [X] Move component content folders into modules/ROOT/pages
# * [] New function to create Antora navigation files
# * [X] Remove index.md files before ADOC conversion (keeping some)
# * MD to ADOC conversions
# ** [] Convert `link:{{ site.baseurl }}/reference/resources/node[Node resource]` to `link:reference/resources/node.adoc[Node resource]`
# ** [] Troubleshoot grep expressions below (they're stopping the script with no error message)
# **



set -euox pipefail # This helps with debugging and dealing with errors.

SCRIPT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

echo "Directory variable set"

# for troubleshooting builds

rm -rf antora antora-demo calico calico-enterprise calico-cloud

pwd > ~/tmp/bar.txt

function home() {
    # Change directory to script location
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

echo "Home function created"
function create_antora_destination () {
    # Creates the destination file structure and demo configuration files.

    #home
    #cd ..
    #rm -rf ./antora-demo
    #git init antora-demo
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
    #cd antora-demo
    #git add .
    #git commit -m "Added files"
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
  #exit N
# These grep lines mysteriously stop the script with no error. //TODO//
#grep -rl "=== " . | xargs sed -i "" -e 's/=== /== /g'
#grep -rl "==== " . | xargs sed -i "" -e 's/==== /=== /g'
#grep -rl "===== " . | xargs sed -i "" -e 's/===== /==== /g'
  # Fix heading nonsense
  # egrep -rl "^={3}\s" . | xargs sed r -i '' -e 's/^={3}\s/== /g'
  # egrep -rl "^={4}\s" . | xargs sed -i '' -e 's/^={4}\s/=== /g'
  # egrep -rl "^={5}\s" . | xargs sed -i '' -e 's/^={5}\s/==== /g'
    # Move images to expected Antora directory.
    # mv -R $SCRIPT_DIR/antora/calico/modules/ROOT/images/* $SCRIPT_DIR/antora/calico/modules/ROOT/images
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
  #cd calico
  #mkdir -p $SCRIPT_DIR/calico/calico/modules/ROOT/pages
  #cp -R $SCRIPT_DIR/calico/calico/* $SCRIPT_DIR/calico/calico/modules/ROOT/pages/
  #mv . $SCRIPT_DIR/calico/calico/modules/ROOT/pages/
  #cd ..
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
  #cd calico-enterprise
  #mv . $SCRIPT_DIR/calico-enterprise/calico-enterprise/modules/ROOT/pages/
  #cd ..
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
  #cd calico-cloud
  #mv . $SCRIPT_DIR/calico-cloud/calico-cloud/modules/ROOT/pages/
  #cd ..
  touch test.txt # Was getting 'nothing to commit' error. This sorts it for now.
  git add .
  git commit -m "updating content for antora"
  merge antora calico-cloud
}


  create_antora
#!/bin/bash
# Who       Roger Mähler
# What      Installs Ontop CLI as a Docker container or as a user installed binary.
# Usage     ./00_install_ontop.sh [docker|locally] [version]
# License   Apache License 2.0

set -e

install_mode=${1:-docker}
ontop_version=${2:-5.3.0}

function install_ontop() {
    echo "Installing Ontop CLI..."
    pushd ${HOME}/bin &> /dev/null
    rm -rf ${HOME}/bin/ontop*
    wget https://github.com/ontop/ontop/releases/download/ontop-${ontop_version}/ontop-cli-${ontop_version}.zip
    mkdir ontop-cli-${ontop_version}
    cd ontop-cli-${ontop_version}
    unzip ../ontop-cli-${ontop_version}.zip
    cd ..
    ln -s ontop-cli-${ontop_version}/ontop ontop
    ln -s ontop-cli-${ontop_version}/ontop-completion.sh ontop-completion.sh
    popd &> /dev/null
}


if [[ "$install_mode" == "docker" ]]; then
    echo "info: creating alias (Bash function) for Docker container for Ontop CLI."
    function ontop() {
        docker run -it --rm -v $(pwd):/data ontop/ontop ontop "$@"
    }
elif [[ "$install_mode" == "local" ]]; then
    echo "info: installing Ontop CLI locally in $HOME/bin."
    install_ontop ${2:-5.3.0}
fi

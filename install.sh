#!/bin/bash
set -e 

function error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
    exit 1
}

if ! command -v git &> /dev/null; then
    error "git not found, please install git"
fi

cd /tmp
git clone https://github.com/scaratech/crosdl.git
cd crosdl

chmod +x crosdl.sh
sudo cp crosdl.sh /usr/bin/crosdl

echo "crosdl installed to /usr/bin/crosdl"

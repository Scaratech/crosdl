#!/bin/bash
set -e 

if ! command -v git &> /dev/null; then
    error "git not found, please install git"
fi

cd /tmp
git clone https://github.com/scaratech/crosdl.git
cd crosdl

chmod +x crosdl.sh
sudo cp crosdl.sh /usr/bin/crosdl

echo "crosdl installed to /usr/bin/crosdl"
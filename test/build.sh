#!/bin/bash

vboxmanage unregistervm rh2 --delete

vboxmanage unregistervm rh3 --delete

vboxmanage snapshot rh delete rhsnap

vboxmanage unregistervm rh --delete

rm -rf output-virtualbox-ovf/

packer build rh.json

vboxmanage snapshot rh take rhsnap

vboxmanage clonevm rh --snapshot rhsnap --name rh2 --options link --register

vboxmanage clonevm rh --snapshot rhsnap --name rh3 --options link --register

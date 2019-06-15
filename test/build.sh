#!/bin/bash

rm -rf output-virtualbox-ovf/

packer build test/rh.json

#!/bin/bash

# Attendre d'avoir une adresse IP
# Concrètement : attendre d'avoir une route par défaut
while true
do
  if ip route | grep default > /dev/null 2>&1
  then
    break
  fi
  sleep 2
done

# Attendre le maitre
socat UDP-LISTEN:24000 EXEC:$RH_BIN_DIR/puppet.sh

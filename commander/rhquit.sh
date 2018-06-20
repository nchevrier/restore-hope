#!/bin/bash

screen -S rh -p 1 -X stuff 'exit\n'

screen -S rh -p 0 -X stuff 'exit\n'

screen -S rh -p 2 -X stuff 'exit\n'

#!/usr/bin/env bash


source /edx/app/discovery/discovery_env
COMMAND=$1

case $COMMAND in
    start)
        /edx/app/supervisor/venvs/supervisor/bin/supervisord -n --configuration /edx/app/supervisor/supervisord.conf
        ;;
    open)
        . /edx/app/discovery/nodeenvs/discovery/bin/activate
        . /edx/app/discovery/venvs/discovery/bin/activate
        cd /edx/app/discovery/discovery

        /bin/bash
        ;;
    exec)
        shift

        . /edx/app/discovery/nodeenvs/discovery/bin/activate
        . /edx/app/discovery/venvs/discovery/bin/activate
        cd /edx/app/discovery/discovery

        "$@"
        ;;
    *)
        "$@"
        ;;
esac

#!/usr/bin/env bash


source /edx/app/discovery/discovery_env

# We exec so that celery is the child of supervisor and can be managed properly
exec /edx/app/discovery/venvs/discovery/bin/celery $@

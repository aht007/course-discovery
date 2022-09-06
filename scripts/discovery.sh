#!/usr/bin/env bash


export EDX_REST_API_CLIENT_NAME="default_env-default_deployment-discovery"

exec /edx/app/discovery/venvs/discovery/bin/gunicorn -c /edx/app/discovery/discovery_gunicorn.py --reload course_discovery.wsgi:application

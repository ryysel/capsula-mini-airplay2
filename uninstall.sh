#!/bin/sh
set -eu
export CAPSULA_ACTION=uninstall
exec sh "$(dirname "$0")/install.sh" "$@"

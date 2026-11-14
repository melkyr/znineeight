#!/usr/bin/env bash
#
# serve.sh - browse the manual locally.
#
# Serves the manual root (this directory) with Python's built-in HTTP server.
# The port is the first argument; it defaults to 8000. Works from any working
# directory. Binds all interfaces (0.0.0.0), so it is reachable on the LAN;
# the site itself fetches nothing external.
#
#   bash docs/sf/manuals/serve.sh        # http://127.0.0.1:8000/
#   bash docs/sf/manuals/serve.sh 8765   # http://127.0.0.1:8765/

exec python3 -m http.server "${1:-8000}" --directory "$(dirname "$0")"

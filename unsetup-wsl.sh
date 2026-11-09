#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo 'Run this script as root inside WSL.' >&2
    exit 1
fi
. /etc/os-release
case "$ID" in
    ubuntu|debian) ;;
    *) echo 'This uninstaller supports Ubuntu and Debian in WSL 2.' >&2; exit 1 ;;
esac

unset DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
docker_local() {
    /usr/bin/docker --host unix:///var/run/docker.sock "$@"
}
if [ ! -x /usr/bin/docker ]; then
    echo 'Docker Engine is not installed in this distribution.' >&2
    exit 1
fi
if ! docker_local info >/dev/null 2>&1; then
    echo 'Docker Engine is not running. Start it with "service docker start", then run un-setup again.' >&2
    exit 1
fi

container=despina-workshop
existing=$(docker_local ps -aq --filter "name=^/$container$")
if [ -n "$existing" ]; then
    owner=$(docker_local inspect --format '{{index .Config.Labels "com.despina.workshop"}}' "$container")
    if [ "$owner" != true ]; then
        echo 'A container named despina-workshop exists but was not created by this installer. Nothing was removed.' >&2
        exit 1
    fi
    docker_local rm --force "$container"
fi

if docker_local image inspect despina-workshop:local >/dev/null 2>&1; then
    if ! docker_local image rm despina-workshop:local; then
        echo 'The workshop container was removed, but Docker could not remove its image tag. It may be in use by another container.' >&2
    fi
fi

echo 'Workshop container removed. Docker Engine, its packages, and unrelated Docker data remain installed.'

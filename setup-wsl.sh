#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo 'Run this script as root inside WSL.' >&2
    exit 1
fi
. /etc/os-release
case "$ID" in
    ubuntu|debian) ;;
    *) echo 'This installer supports Ubuntu and Debian in WSL 2.' >&2; exit 1 ;;
esac

# Desktop integration uses a separate engine.
for path in /usr/bin/docker /var/run/docker.sock; do
    case "$(readlink -f "$path" 2>/dev/null || true)" in
        /mnt/wsl/docker-desktop/*|/mnt/wsl/shared-docker/*)
            echo 'Disable Docker Desktop WSL integration for this distribution, then run setup again.' >&2
            exit 1
            ;;
    esac
done

packages=()
command -v curl >/dev/null || packages+=(curl ca-certificates)
if [ ! -x /usr/bin/docker ] || ! command -v dockerd >/dev/null; then
    packages+=(docker.io)
fi
if [ -n "${packages[*]-}" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "${packages[@]}"
fi

# Use this distribution's local engine regardless of the user's Docker context.
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
docker_local() {
    /usr/bin/docker --host unix:///var/run/docker.sock "$@"
}
if ! docker_local info >/dev/null 2>&1; then
    echo 'Starting Docker Engine...'
    if [ "$(cat /proc/1/comm)" = systemd ]; then
        systemctl enable --now docker
    else
        service docker start
    fi
    for attempt in {1..30}; do
        if docker_local info >/dev/null 2>&1; then break; fi
        sleep 1
    done
    if ! docker_local info >/dev/null 2>&1; then
        echo 'Docker Engine did not start. Check the Docker service in WSL.' >&2
        exit 1
    fi
fi

container=despina-workshop
existing=$(docker_local ps -aq --filter "name=^/$container$")
if [ -n "$existing" ]; then
    owner=$(docker_local inspect --format '{{index .Config.Labels "com.despina.workshop"}}' "$container")
    if [ "$owner" != true ]; then
        echo 'A container named despina-workshop already exists and was not created by this installer.' >&2
        exit 1
    fi
    docker_local start "$container"
else
    workspace=$(mktemp -d)
    trap 'rm -rf -- "$workspace"' EXIT
    echo 'Downloading and building the workshop...'
    curl --fail --silent --show-error --location \
        https://github.com/thrxpt/tod/archive/refs/heads/main.tar.gz |
        tar -xz -C "$workspace"
    docker_local build --tag despina-workshop:local "$workspace/tod-main"
    docker_local run -d --name "$container" --hostname despina-control --label com.despina.workshop=true \
        --restart unless-stopped -p 127.0.0.1:7681:7681 despina-workshop:local
fi

# Update the visible prompt in existing containers while preserving their mission files.
printf '%s\n' 'PS1=${PS1//\\h/despina-control}' 'export PS1="\u@despina-control:\w\$ "' |
    docker_local exec -i --user engineer "$container" bash -c '
        set -e
        IFS= read -r desired
        IFS= read -r previous
        file=/home/engineer/.bashrc
        temporary=$(mktemp /home/engineer/.bashrc.XXXXXX)
        trap "rm -f -- \"$temporary\"" EXIT
        grep -Fvx -- "$previous" "$file" > "$temporary" || [ "$?" -eq 1 ]
        if ! grep -Fxq -- "$desired" "$temporary"; then
            printf "\n%s\n" "$desired" >> "$temporary"
        fi
        chmod --reference="$file" "$temporary"
        mv -- "$temporary" "$file"
    '

echo 'Workshop container ready. Open http://localhost:7681 from Windows.'

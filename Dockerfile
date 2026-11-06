FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ttyd nano grep curl jq fontconfig fonts-thai-tlwg fonts-liberation locales \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen th_TH.UTF-8 en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

RUN useradd -m -s /bin/bash engineer

RUN printf '%s\n' 'PS1=${PS1//\\h/despina-control}' >> /home/engineer/.bashrc

WORKDIR /home/engineer/neptune

COPY config ./config
COPY backups ./backups
COPY logs ./logs
COPY .station_vault ./.station_vault

RUN mkdir -p /opt/template && \
    cp -r /home/engineer/neptune/. /opt/template/ && \
    chown -R engineer:engineer /home/engineer/neptune

RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    station=/home/engineer/neptune \
    checkpoints=/home/engineer/.mission-checkpoints \
    'if [ "$#" -gt 1 ]; then' \
    '    echo "Usage: reset-mission [cooling|firewall|dream|--all]" >&2' \
    '    exit 1' \
    fi \
    'case "${1:-}" in' \
    '    "")' \
    '        if [ -f "$checkpoints/latest" ]; then' \
    '            IFS= read -r name < "$checkpoints/latest"' \
    '            case "$name" in cooling|firewall|dream) ;; *) echo "[ABORT] Invalid checkpoint." >&2; exit 1;; esac' \
    '            checkpoint="$checkpoints/$name.tar"' \
    '        elif [ -f /home/engineer/.mission-checkpoint.tar ]; then' \
    '            checkpoint=/home/engineer/.mission-checkpoint.tar' \
    '        else' \
    '            checkpoint=' \
    '        fi' \
    '        ;;' \
    '    cooling|firewall|dream) checkpoint="$checkpoints/$1.tar" ;;' \
    '    --all) checkpoint= ;;' \
    '    *) echo "Usage: reset-mission [cooling|firewall|dream|--all]" >&2; exit 1 ;;' \
    esac \
    'if [ -n "$checkpoint" ]; then' \
    '    if [ ! -f "$checkpoint" ]; then' \
    '        echo "[ABORT] Checkpoint not found." >&2' \
    '        exit 1' \
    '    fi' \
    '    restore=$(mktemp -d /home/engineer/.mission-restore.XXXXXX)' \
    '    trap '"'"'rm -rf -- "$restore"'"'"' EXIT' \
    '    tar -xf "$checkpoint" -C "$restore"' \
    '    source_dir=$restore' \
    '    message="Checkpoint restored."' \
    else \
    '    source_dir=/opt/template' \
    '    message="Station reset to the beginning."' \
    fi \
    'find "$station" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' \
    'cp -a "$source_dir/." "$station/"' \
    'echo "[SYSTEM RESTORED] $message"' \
    > /usr/local/bin/reset-mission && chmod +x /usr/local/bin/reset-mission

RUN printf '%s\n' \
    '# Automatically save a snapshot when each subsystem becomes ready.' \
    '_mission_record_checkpoint() {' \
    '    local name=$1 ready=$2 var="_mission_seen_$1" previous tmp marker' \
    '    previous=${!var-}' \
    '    if [ "$ready" = 1 ] && { [ "$previous" = 0 ] || [ ! -f "/home/engineer/.mission-checkpoints/$name.tar" ]; }; then' \
    '        mkdir -p /home/engineer/.mission-checkpoints || return 1' \
    '        tmp=$(mktemp /home/engineer/.mission-checkpoints/.snapshot.XXXXXX) || return 1' \
    '        if ! tar -cf "$tmp" -C /home/engineer/neptune . || ! mv -f -- "$tmp" "/home/engineer/.mission-checkpoints/$name.tar"; then' \
    '            rm -f -- "$tmp"' \
    '            echo "[CHECKPOINT] Could not save $name." >&2' \
    '            return 1' \
    '        fi' \
    '        marker=$(mktemp /home/engineer/.mission-checkpoints/.latest.XXXXXX) || { printf -v "$var" 0; return 1; }' \
    '        if ! printf '"'"'%s\n'"'"' "$name" > "$marker" || ! mv -f -- "$marker" /home/engineer/.mission-checkpoints/latest; then' \
    '            rm -f -- "$marker"' \
    '            echo "[CHECKPOINT] Could not update latest checkpoint." >&2' \
    '            printf -v "$var" 0' \
    '            return 1' \
    '        fi' \
    '        echo "[CHECKPOINT SAVED] $name"' \
    '    fi' \
    '    printf -v "$var" '"'"'%s'"'"' "$ready"' \
    '}' \
    '_mission_checkpoint_prompt() {' \
    '    local previous_status=$? cooling=0 firewall=0 dream=0' \
    '    grep -q '"'"'cooling=ON'"'"' /home/engineer/neptune/config/cooling.conf 2>/dev/null && cooling=1' \
    '    [ ! -f /home/engineer/neptune/config/virus.exe ] && firewall=1' \
    '    [ -s /home/engineer/neptune/dreams/dream.txt ] && dream=1' \
    '    _mission_record_checkpoint cooling "$cooling"' \
    '    _mission_record_checkpoint firewall "$firewall"' \
    '    _mission_record_checkpoint dream "$dream"' \
    '    return "$previous_status"' \
    '}' \
    'PROMPT_COMMAND="_mission_checkpoint_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"' \
    > /usr/local/bin/mission-checkpoints && chmod +x /usr/local/bin/mission-checkpoints

RUN printf '%s\n' '. /usr/local/bin/mission-checkpoints' >> /home/engineer/.bashrc

RUN printf '%s\n' \
    '#!/bin/bash' \
    '[ ! -t 1 ] || clear' \
    'printf '"'"'%s\n'"'"' '"'"'================================================='"'"' '"'"'    STATION DESPINA: SYSTEM HEALTH CHECK'"'"' '"'"'================================================='"'"'' \
    COOLING_OK=false \
    VIRUS_OK=false \
    DREAM_OK=false \
    'if grep -q '"'"'cooling=ON'"'"' /home/engineer/neptune/config/cooling.conf 2>/dev/null; then' \
    '    echo '"'"'[✔] Cooling System : ONLINE (35°C)'"'"'' \
    '    COOLING_OK=true' \
    else \
    '    echo '"'"'[ ] Cooling System : FAIL (run cp backups/cooling_override.conf config/cooling.conf)'"'"'' \
    fi \
    'if [ ! -f /home/engineer/neptune/config/virus.exe ]; then' \
    '    echo '"'"'[✔] Firewall Status: CLEAN'"'"'' \
    '    VIRUS_OK=true' \
    else \
    '    echo '"'"'[ ] Firewall Status: BLOCKED (remove virus files from config/)'"'"'' \
    fi \
    'if [ -s /home/engineer/neptune/dreams/dream.txt ]; then' \
    '    echo '"'"'[✔] Dream Capsule  : READY TO LAUNCH'"'"'' \
    '    DREAM_OK=true' \
    else \
    '    echo '"'"'[ ] Dream Capsule  : NOT READY (create dreams/dream.txt)'"'"'' \
    fi \
    'echo '"'"'================================================='"'"'' \
    'if [ "$COOLING_OK" = true ] && [ "$VIRUS_OK" = true ] && [ "$DREAM_OK" = true ]; then' \
    '    echo "All systems are ready! Type '"'"'launch'"'"' to launch the shuttle!"' \
    else \
    '    echo "Fix the issues above, then run '"'"'mission-status'"'"' to check again."' \
    fi \
    > /usr/local/bin/mission-status && chmod +x /usr/local/bin/mission-status

RUN printf '%s\n' \
    '#!/bin/bash' \
    'DREAM_CAPSULE_URL="https://dream-wall-six.vercel.app/api/dreams"' \
    '[ ! -t 1 ] || clear' \
    'printf '"'"'%s\n'"'"' '"'"'================================================='"'"' '"'"'       STATION DESPINA: LAUNCH SYSTEM'"'"' '"'"'================================================='"'"'' \
    'if ! grep -q '"'"'cooling=ON'"'"' /home/engineer/neptune/config/cooling.conf 2>/dev/null || \' \
    '   [ -f /home/engineer/neptune/config/virus.exe ] || \' \
    '   [ ! -s /home/engineer/neptune/dreams/dream.txt ]; then' \
    '    echo '"'"'[ABORT] Cannot launch the shuttle! Systems are not ready.'"'"'' \
    '    echo "Run '"'"'mission-status'"'"' to see what needs fixing."' \
    '    exit 1' \
    fi \
    'if [ -z "$DREAM_CAPSULE_URL" ]; then' \
    '    echo '"'"'[ABORT] Dream Capsule API URL is not configured yet.'"'"' >&2' \
    '    exit 1' \
    fi \
    'echo '"'"'[+] Verification Passed! All Subsystems Nominal.'"'"'' \
    'for i in 3 2 1; do' \
    '    echo "$i..."' \
    '    sleep 1' \
    done \
    'echo '"'"'[+] Transmitting Dream Capsule Payload...'"'"'' \
    'set -o pipefail' \
    'if ! jq -n --rawfile dream /home/engineer/neptune/dreams/dream.txt '"'"'{dream: ($dream | sub("\n+$"; ""))}'"'"' | \' \
    '    curl --fail --silent --show-error --connect-timeout 10 --max-time 30 -o /dev/null -H '"'"'Content-Type: application/json'"'"' --data-binary @- "$DREAM_CAPSULE_URL"; then' \
    '    echo '"'"'[ABORT] Could not send your dream. Please try again.'"'"' >&2' \
    '    exit 1' \
    fi \
    '[ ! -t 1 ] || clear' \
    'cat <<'"'"'ROCKET'"'"'' \
    '         /\' \
    '        /  \' \
    '       |    |' \
    '      /|====|\' \
    '     /_| || |_\' \
    '       | || |' \
    '      /      \' \
    '     /        \' \
    '    ~~~~~~~~~~~~' \
    ROCKET \
    'echo '"'"'MISSION COMPLETE: DREAM CAPSULE LAUNCHED!'"'"'' \
    'echo '"'"'Welcome to Computer Engineering at KMUTT!'"'"'' \
    > /usr/local/bin/launch && chmod +x /usr/local/bin/launch

USER engineer
EXPOSE 7681

CMD ["ttyd", "-p", "7681", "-t", "fontSize=20", "-t", "rendererType=webgl", "-t", "allowProposedApi=true", "-t", "theme={'background': '#0b0e14'}", "bash"]

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ttyd nano grep curl fontconfig fonts-thai-tlwg fonts-liberation locales \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen th_TH.UTF-8 en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

RUN useradd -m -s /bin/bash engineer

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
    'find /home/engineer/neptune -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +' \
    'cp -r /opt/template/. /home/engineer/neptune/' \
    'clear' \
    'echo "[SYSTEM RESTORED] Station reset successful"' \
    > /usr/local/bin/reset-mission && chmod +x /usr/local/bin/reset-mission

USER engineer
EXPOSE 7681

CMD ["ttyd", "-p", "7681", "-t", "fontSize=20", "-t", "rendererType=webgl", "-t", "allowProposedApi=true", "-t", "theme={'background': '#0b0e14'}", "bash"]

# Build an IB Gateway image using the official IBKR installer and IBC for
# unattended startup. Update IB_GATEWAY_VERSION and IBC_VERSION together when
# adopting a new IBKR release.
FROM ubuntu:24.04 AS install

ARG DEBIAN_FRONTEND=noninteractive
ARG IB_GATEWAY_VERSION=10.50.1e
ARG IB_GATEWAY_CHANNEL=stable
ARG IBC_VERSION=3.24.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/install
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) IB_ARCH=x64 ;; \
      arm64) IB_ARCH=arm ;; \
      *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    IB_URL="https://download2.interactivebrokers.com/installers/ibgateway/${IB_GATEWAY_CHANNEL}-standalone/ibgateway-${IB_GATEWAY_CHANNEL}-standalone-linux-${IB_ARCH}.sh"; \
    curl --fail --location --silent --show-error "$IB_URL" -o ibgateway-installer.sh; \
    chmod 755 ibgateway-installer.sh; \
    ./ibgateway-installer.sh -q -dir "/opt/ibgateway/ibgateway/${IB_GATEWAY_VERSION}"; \
    IBC_URL="https://github.com/IbcAlpha/IBC/releases/download/${IBC_VERSION}/IBCLinux-${IBC_VERSION}.zip"; \
    curl --fail --location --silent --show-error "$IBC_URL" -o ibc.zip; \
    mkdir -p /opt/ibc; \
    unzip -q ibc.zip -d /opt/ibc; \
    chmod -R a+x /opt/ibc/*.sh /opt/ibc/scripts/*.sh

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG IB_GATEWAY_VERSION=10.50.1e
ENV IB_GATEWAY_VERSION=${IB_GATEWAY_VERSION} \
    HOME=/home/ibgateway \
    DISPLAY=:1 \
    TWS_PATH=/opt/ibgateway \
    IBC_PATH=/opt/ibc

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates gettext-base socat xvfb x11vnc \
      libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 libc6 libcairo2 libcups2 \
      libdbus-1-3 libdrm2 libexpat1 libgbm1 libglib2.0-0 libgtk-3-0 \
      libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
      libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
      fonts-liberation libasound2t64 libxtst6 xdg-utils \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 ibgateway \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash ibgateway \
    && mkdir -p /data/settings /tmp/.X11-unix \
    && chmod 1777 /tmp/.X11-unix

COPY --from=install --chown=1000:1000 /opt/ibgateway /opt/ibgateway
COPY --from=install --chown=1000:1000 /opt/ibc /opt/ibc
COPY --chown=1000:1000 entrypoint.sh /usr/local/bin/ibgateway-entrypoint
COPY --chown=1000:1000 jts.ini /opt/ibgateway/jts.ini.tmpl
RUN chmod 755 /usr/local/bin/ibgateway-entrypoint \
    && chown -R 1000:1000 /data

USER 1000:1000
WORKDIR /home/ibgateway
VOLUME ["/data"]
EXPOSE 4003 4004 5901
ENTRYPOINT ["/usr/local/bin/ibgateway-entrypoint"]

LABEL org.opencontainers.image.source="https://github.com/nathan0000/ib-gateway-official"

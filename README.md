# Local IB Gateway image

This image follows the useful parts of [gnzsnz/ib-gateway-docker](https://github.com/gnzsnz/ib-gateway-docker): IBC automates the Gateway UI, Xvfb supplies a display, x11vnc provides optional GUI access, and socat forwards the loopback-only IB API ports. The Gateway installer is downloaded directly from IBKR's official `download2.interactivebrokers.com` stable/latest endpoint during the image build. IBC is downloaded from its upstream GitHub release.

## Credentials

Create three files under `secrets/`:

```sh
mkdir -p secrets
umask 077
printf '%s' 'your-ibkr-username' > secrets/ib_username.txt
printf '%s' 'your-ibkr-password' > secrets/ib_password.txt
printf '%s' 'your-vnc-password' > secrets/vnc_password.txt
```

Protect those files and never commit them. The VNC password file is mandatory; VNC will not start without it. x11vnc uses the VNC password file format, which supports at most eight password characters, so choose eight or fewer characters. The VNC listener is restricted to localhost on the host and within the container.

IBKR account credentials are supplied through Compose secret files and written only to a mode-0600 IBC configuration file inside the container at startup. IB Gateway's API socket does not authenticate clients with an API username or password. The API ports are therefore published only on host loopback (`127.0.0.1`); do not change those bindings to `0.0.0.0` or expose them to an untrusted network. Any local process that can reach the port can submit requests, including orders when `READ_ONLY_API=no`.

## Build and run

```sh
cp .env.example .env
docker compose up --build -d
docker compose logs -f ib-gateway
```

The GitHub Actions workflow in this repository builds and publishes
`ghcr.io/nathan0000/ib-gateway-official:latest` on pushes to `develop` and on
manual workflow dispatch. The image labels its source repository so GitHub can
link the GHCR package. GHCR packages may default to private; make the package
public in GitHub Packages settings if it should be pullable without
authentication.

The default is paper trading. The application connects to `127.0.0.1:4002` for paper or `127.0.0.1:4001` for live. Choose `TRADING_MODE=live` only when intended. Open a VNC client to `127.0.0.1:5900` if you need to complete or inspect login/2FA. Settings persist in the `gateway-settings` Docker volume.

## Updating

IBKR's download page provides current stable/latest builds rather than a historical installer archive. Update `IB_GATEWAY_CHANNEL` and `IB_GATEWAY_VERSION` in `.env` together with the actual release version listed by IBKR, then rebuild. `IBC_VERSION` is pinned separately so that the installer and IBC release are reproducible. The direct official download endpoint itself tracks the current release in the selected channel.

This image has not been run against an IBKR account as part of its addition. Login, 2FA, and API settings can require a first manual VNC session.

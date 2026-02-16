#!/bin/sh
set -e
exec > /dev/null 2>&1
eval "$DOTENV"


IP=$(curl -s ipinfo.io/ip)
COUNTRY=$(curl -s ipinfo.io/country | tr 'A-Z' 'a-z')
HOSTNAME="github-${COUNTRY}-$(echo "$IP" | tr '.' '-')"

sudo sysctl -qw net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1
sudo ethtool -K eth0 rx-udp-gro-forwarding on rx-gro-list off

curl -fsSL https://tailscale.com/install.sh | sudo sh
sudo tailscale up --authkey="${TS_AUTHKEY}" --advertise-exit-node --hostname="${HOSTNAME}"

if [ -n "$K3S_URL" ] && [ -n "$K3S_TOKEN" ] && [ -n "$INSTALL_K3S_VERSION" ]; then
  curl -sfL https://get.k3s.io | \
    K3S_URL="${K3S_URL}" \
    K3S_TOKEN="${K3S_TOKEN}" \
    INSTALL_K3S_VERSION="${INSTALL_K3S_VERSION}" sh -s - \
    --node-name          "${HOSTNAME}" \
    --node-label         "github-runner=" \
    --node-ip            "$(tailscale ip -4)" \
    --flannel-iface      "tailscale0"
fi

END=$(($(date +%s) + 18000))
while [ "$(date +%s)" -lt "$END" ]; do
  gh run list -w ci.yml -s in_progress --json databaseId -q ".[] | select(.databaseId > $GITHUB_RUN_ID) | .databaseId" -R "$GITHUB_REPOSITORY" | grep -q . && exit 0
  gh run list -R "$GITHUB_REPOSITORY" --status completed --limit 100 --json databaseId -q ".[] | select(.databaseId != $GITHUB_RUN_ID) | .databaseId" | xargs -I{} gh run delete {} -R "$GITHUB_REPOSITORY" &
  sleep 60
done

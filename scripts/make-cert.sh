#!/bin/sh
# Create a private certificate authority and an HTTPS certificate for this Mac,
# so a browser on another device (Vision Pro Safari) gets a secure context.
# Everything lives in the ignored .tools/tls/; scripts/serve.sh then serves the
# page over https:// and the backend over wss:// automatically.
# Rerun after the Mac's network address changes. Requires mkcert (brew install mkcert).
set -eu
cd "$(dirname "$0")/.."
command -v mkcert >/dev/null || { echo "Install mkcert first: brew install mkcert" >&2; exit 1; }
dir=.tools/tls
mkdir -p "$dir/ca"
# A project-only CA: nothing is added to this Mac's trust store.
export CAROOT="$PWD/$dir/ca"
host="$(scutil --get LocalHostName).local"
names="$host localhost 127.0.0.1"
for interface in en0 en1; do
  address=$(ipconfig getifaddr "$interface" 2>/dev/null || true)
  [ -n "$address" ] && names="$names $address"
done
# shellcheck disable=SC2086
mkcert -cert-file "$dir/cert.pem" -key-file "$dir/key.pem" $names
cp "$CAROOT/rootCA.pem" "$dir/StoneAge-Local-CA.crt"
chmod 600 "$dir/key.pem" "$CAROOT/rootCA-key.pem"
echo
echo "Certificate for: $names"
echo "Install $dir/StoneAge-Local-CA.crt on Vision Pro (once):"
echo "  1. AirDrop it to the Vision Pro (Finder: open $dir), accept it."
echo "  2. Settings > General > VPN & Device Management: install the downloaded profile."
echo "  3. Settings > General > About > Certificate Trust Settings: turn on full trust for it."
echo "Then run scripts/serve.sh and open https://$host:8780/"

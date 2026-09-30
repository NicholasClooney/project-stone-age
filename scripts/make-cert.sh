#!/bin/sh
# Create a private certificate authority and an HTTPS certificate for this Mac,
# so a browser on another device (Vision Pro Safari) gets a secure context.
# Everything lives in the ignored .tools/tls/; scripts/serve.sh then serves the
# page over https:// and the backend over wss:// automatically.
# Rerun after the Mac's network address changes. Requires mkcert (brew install
# mkcert; Linux and WSL: apt install mkcert; Windows: winget install FiloSottile.mkcert).
set -eu
cd "$(dirname "$0")/.."
. scripts/common.sh
command -v mkcert >/dev/null || { echo "Install mkcert first (macOS: brew install mkcert; Linux/WSL: sudo apt install mkcert; Windows: winget install FiloSottile.mkcert)." >&2; exit 1; }
dir=.tools/tls
mkdir -p "$dir/ca"
# A project-only CA: nothing is added to this computer's trust store.
CAROOT=$(native_path "$PWD/$dir/ca")
export CAROOT
if [ "$platform" = macos ]; then
  host="$(scutil --get LocalHostName).local"
  addresses=$(for interface in en0 en1; do ipconfig getifaddr "$interface" 2>/dev/null || true; done)
else
  host=$(hostname)
  # Linux and WSL list their addresses; on Windows only the name is used.
  addresses=$(hostname -I 2>/dev/null || true)
fi
names="$host localhost 127.0.0.1"
for address in $addresses; do names="$names $address"; done
# shellcheck disable=SC2086
mkcert -cert-file "$dir/cert.pem" -key-file "$dir/key.pem" $names
cp "$dir/ca/rootCA.pem" "$dir/StoneAge-Local-CA.crt"
chmod 600 "$dir/key.pem" "$dir/ca/rootCA-key.pem"
echo
echo "Certificate for: $names"
echo "Install $dir/StoneAge-Local-CA.crt on Vision Pro (once):"
echo "  1. AirDrop it to the Vision Pro (Finder: open $dir), accept it."
echo "  2. Settings > General > VPN & Device Management: install the downloaded profile."
echo "  3. Settings > General > About > Certificate Trust Settings: turn on full trust for it."
echo "Then run scripts/serve.sh and open https://$host:8780/"

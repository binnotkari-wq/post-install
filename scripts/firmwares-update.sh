#!/usr/bin/env bash

set -euo pipefail

echo "==> Mise à jour des firmwares."

sudo fwupdmgr refresh || true
sudo fwupdmgr get-updates || true
sudo fwupdmgr update || true

echo "✅ Firmwares à jour."
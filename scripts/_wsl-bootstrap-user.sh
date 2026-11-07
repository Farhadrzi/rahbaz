#!/bin/bash
set -euo pipefail
if ! id farha >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo farha
  echo 'farha:farha' | chpasswd
fi
echo 'farha ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/farha
chmod 440 /etc/sudoers.d/farha
printf '[user]\ndefault=farha\n' > /etc/wsl.conf
id farha
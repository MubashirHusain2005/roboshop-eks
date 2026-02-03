#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "=== Updating system ==="
dnf update -y

echo "=== Installing prerequisites ==="
dnf install -y curl unzip

echo "=== Creating vault user ==="
useradd --system --home /etc/vault.d --shell /bin/false vault || true

echo "=== Creating directories ==="
mkdir -p /opt/vault/data /etc/vault.d
chown -R vault:vault /opt/vault /etc/vault.d
chmod 750 /opt/vault

echo "=== Downloading Vault binary ==="
cd /opt
curl -fsSL https://releases.hashicorp.com/vault/1.21.2/vault_1.21.2_linux_amd64.zip -o vault.zip
unzip -o vault.zip
mv vault /usr/bin/vault
chmod +x /usr/bin/vault
rm -f vault.zip

echo "=== Writing Vault config ==="
cat <<EOF >/etc/vault.d/vault.hcl
ui = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF

echo "=== Creating systemd service ==="
cat <<EOF >/etc/systemd/system/vault.service
[Unit]
Description=HashiCorp Vault
After=network-online.target
Requires=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vault
systemctl start vault

echo "=== Vault installation complete ==="


#!/bin/bash
# This script is meant to be run as the Startup Script of each Compute Instance while it's booting. The script uses the
# run-consul and run-vault scripts to configure and start both Vault and Consul in client mode. This script assumes it's
# running in a Compute Instance based on a Google Image built from the Packer template in
# examples/vault-consul-image/vault-consul.json.

set -e

# Send the log output from this script to startup-script.log, syslog, and the console
# Inspired by https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/startup-script.log|logger -t startup-script -s 2>/dev/console) 2>&1

# The Packer template puts the TLS certs in these file paths
readonly VAULT_TLS_CERT_FILE="/opt/vault/tls/vault.crt.pem"
readonly VAULT_TLS_KEY_FILE="/opt/vault/tls/vault.key.pem"

# Note that any variables below with <dollar-sign><curly-brace><var-name><curly-brace> are expected to be interpolated by Terraform.
/opt/consul/bin/run-consul --client --cluster-tag-name "${consul_cluster_tag_name}"

# start vault auto unseal
#sudo apt-get install -y unzip libtool libltdl-dev
#curl -s -L -o ~/vault.zip https://releases.hashicorp.com/vault/1.0.2/vault_1.0.2_linux_amd64.zip
#sudo unzip ~/vault.zip
#sudo install -c -m 0755 vault /usr/bin
mkdir -p /test/vault
echo "GCLOUD_PROJECT = ${gcloud_project}" > /test/vault/thisshitwhac
echo -e '[Unit]\nDescription="HashiCorp Vault - A tool for managing secrets"\nDocumentation=https://www.vaultproject.io/docs/\nRequires=network-online.target\nAfter=network-online.target\n\n[Service]\nExecStart=/usr/bin/vault server -config=/test/vault/config.hcl\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\nKillSignal=SIGINT\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n' > /lib/systemd/system/vault.service
echo -e 'storage "file" {\n  path = "/opt/vault"\n}\n\nlistener "tcp" {\n  address     = "127.0.0.1:8200"\n  tls_disable = 1\n}\n\nseal "gcpckms" {\n  project     = "${gcloud_project}"\n  region      = "${keyring_location}"\n  key_ring    = "${key_ring}"\n  crypto_key  = "${crypto_key}"\n}\n\ndisable_mlock = true\n' > /test/vault/config.hcl
chmod 0664 /lib/systemd/system/vault.service
echo -e 'alias v="vault"\nalias vualt="vault"\nexport VAULT_ADDR="http://127.0.0.1:8200"\n' > /etc/profile.d/vault.sh
chmod 0755 /etc/profile.d/vault.sh
source /etc/profile.d/vault.sh
systemctl enable vault
systemctl start vault
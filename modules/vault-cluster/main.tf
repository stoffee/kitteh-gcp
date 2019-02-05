# ---------------------------------------------------------------------------------------------------------------------
# THESE TEMPLATES REQUIRE TERRAFORM VERSION 0.10.3 AND ABOVE
# This way we can take advantage of Terraform GCP functionality as a separate provider via
# https://github.com/terraform-providers/terraform-provider-google
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = ">= 0.10.3"
}

resource "google_service_account" "vault_kms_service_account" {
  account_id   = "kitteh-vault-svc-acct"
  display_name = "Vault KMS for auto-unseal"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A GCE MANAGED INSTANCE GROUP TO RUN VAULT
# Ideally, we would run a "regional" Managed Instance Group that spans many Zones, but the Terraform GCP provider has
# not yet implemented https://github.com/terraform-providers/terraform-provider-google/issues/45, so we settle for a
# single-zone Managed Instance Group.
# ---------------------------------------------------------------------------------------------------------------------

# Create the single-zone Managed Instance Group where Vault will run.
resource "google_compute_region_instance_group_manager" "vault" {
  name = "${var.cluster_name}-ig"

  project = "${var.gcp_project_id}"

  base_instance_name = "${var.cluster_name}"
  instance_template  = "${data.template_file.compute_instance_template_self_link.rendered}"
  region             = "${var.gcp_region}"

  # Restarting a Vault server has an important consequence: The Vault server has to be manually unsealed again. Therefore,
  # the update strategy used to roll out a new GCE Instance Template must be a rolling update. But since Terraform does
  # not yet support ROLLING_UPDATE, such updates must be manually rolled out for now.
  update_strategy = "${var.instance_group_update_strategy}"

  target_pools = ["${var.instance_group_target_pools}"]
  target_size  = "${var.cluster_size}"

  depends_on = ["google_compute_instance_template.vault_public", "google_compute_instance_template.vault_private"]
}


# Create the Instance Template that will be used to populate the Managed Instance Group.
# NOTE: This Compute Instance Template is only created if var.assign_public_ip_addresses is false.
resource "google_compute_instance_template" "vault_private" {
  count = "${1 - var.assign_public_ip_addresses}"

  name_prefix = "${var.cluster_name}"
  description = "${var.cluster_description}"
  project     = "${var.gcp_project_id}"

  instance_description = "${var.cluster_description}"
  machine_type         = "${var.machine_type}"

  tags                    = ["${concat(list(var.cluster_tag_name), var.custom_tags)}"]
  metadata_startup_script = "${var.startup_script}"
  metadata                = "${merge(map(var.metadata_key_name_for_cluster_size, var.cluster_size), var.custom_metadata)}"

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  disk {
    boot         = true
    auto_delete  = true
    source_image = "${var.source_image}"
    disk_size_gb = "${var.root_volume_disk_size_gb}"
    disk_type    = "${var.root_volume_disk_type}"
  }

  network_interface {
    network            = "${var.subnetwork_name != "" ? "" : var.network_name}"
    subnetwork         = "${var.subnetwork_name != "" ? var.subnetwork_name : ""}"
    subnetwork_project = "${var.network_project_id != "" ? var.network_project_id : var.gcp_project_id}"
  }

 # Service account with Cloud KMS roles for the Compute Instance
  service_account {
    email = "${google_service_account.vault_kms_service_account.email}"
    scopes = ["cloud-platform", "compute-rw", "userinfo-email", "storage-ro"]
  }

  metadata_startup_script = <<SCRIPT
    sudo touch /tmp/shitHEAD
    sudo mkdir -p /test/vault
    sudo echo -e '[Unit]\nDescription="HashiCorp Vault - A tool for managing secrets"\nDocumentation=https://www.vaultproject.io/docs/\nRequires=network-online.target\nAfter=network-online.target\n\n[Service]\nExecStart=/usr/bin/vault server -config=/test/vault/config.hcl\nExecReload=/bin/kill -HUP $MAINPID\nKillMode=process\nKillSignal=SIGINT\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n' > /lib/systemd/system/vault.service
    sudo echo -e 'storage "file" {\n  path = "/opt/vault"\n}\n\nlistener "tcp" {\n  address     = "127.0.0.1:8200"\n  tls_disable = 1\n}\n\nseal "gcpckms" {\n  project     = "${var.gcp_project_id}"\n  region      = "${var.keyring_location}"\n  key_ring    = "${var.key_ring}"\n  crypto_key  = "${var.crypto_key}"\n}\n\ndisable_mlock = true\n' > /test/vault/config.hcl
    sudo chmod 0664 /lib/systemd/system/vault.service
    sudo echo -e 'alias v="vault"\nalias vualt="vault"\nexport VAULT_ADDR="http://127.0.0.1:8200"\n' > /etc/profile.d/vault.sh
    source /etc/profile.d/vault.sh
    sudo systemctl enable vault
    sudo systemctl start vault
  SCRIPT

  # Per Terraform Docs (https://www.terraform.io/docs/providers/google/r/compute_instance_template.html#using-with-instance-group-manager),
  # we need to create a new instance template before we can destroy the old one. Note that any Terraform resource on
  # which this Terraform resource depends will also need this lifecycle statement.
  lifecycle {
    create_before_destroy = true
  }

# Create a KMS key ring
 resource "google_kms_key_ring" "key_ring" {
   project  = "${var.gcp_project_id}"
   name     = "${var.key_ring}"
   location = "${var.keyring_location}"
 }

# Create a crypto key for the key ring
 resource "google_kms_crypto_key" "crypto_key" {
   name            = "${var.crypto_key}"
   key_ring        = "${var.key_ring}"
   rotation_period = "100000s"
 }

# Add the service account to the Keyring
resource "google_kms_key_ring_iam_binding" "vault_iam_kms_binding" {
   # key_ring_id = "${google_kms_key_ring.key_ring.id}"
   key_ring_id = "${var.gcp_project_id}/${var.keyring_location}/${var.key_ring}"
   role = "roles/owner"

   members = [
     "serviceAccount:${google_service_account.vault_kms_service_account.email}",
   ]
}
}

# Create the Instance Template that will be used to populate the Managed Instance Group.
# NOTE: This Compute Instance Template is only created if var.assign_public_ip_addresses is true.
resource "google_compute_instance_template" "vault_public" {
  count = "${var.assign_public_ip_addresses}"

  name_prefix = "${var.cluster_name}"
  description = "${var.cluster_description}"
  project     = "${var.gcp_project_id}"

  instance_description = "${var.cluster_description}"
  machine_type         = "${var.machine_type}"

  tags                    = "${concat(list(var.cluster_tag_name), var.custom_tags)}"
  metadata_startup_script = "${var.startup_script}"
  metadata                = "${merge(map(var.metadata_key_name_for_cluster_size, var.cluster_size), var.custom_metadata)}"

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  disk {
    boot         = true
    auto_delete  = true
    source_image = "${var.source_image}"
    disk_size_gb = "${var.root_volume_disk_size_gb}"
    disk_type    = "${var.root_volume_disk_type}"
  }

  network_interface {
    # Either network or subnetwork must both be blank, or exactly one must be provided.
    network            = "${var.subnetwork_name != "" ? "" : var.network_name}"
    subnetwork         = "${var.subnetwork_name != "" ? var.subnetwork_name : ""}"
    subnetwork_project = "${var.network_project_id != "" ? var.network_project_id : var.gcp_project_id}"

    access_config {
      # The presence of this property assigns a public IP address to each Compute Instance. We intentionally leave it
      # blank so that an external IP address is selected automatically.
      nat_ip = ""
    }
  }

  # For a full list of oAuth 2.0 Scopes, see https://developers.google.com/identity/protocols/googlescopes
  service_account {
    email = "${var.service_account_email}"

    scopes = ["${concat(
      list(
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/compute.readonly",
        "https://www.googleapis.com/auth/devstorage.read_write"
      ),
      var.service_account_scopes
    )}"]
  }

  # Per Terraform Docs (https://www.terraform.io/docs/providers/google/r/compute_instance_template.html#using-with-instance-group-manager),
  # we need to create a new instance template before we can destroy the old one. Note that any Terraform resource on
  # which this Terraform resource depends will also need this lifecycle statement.
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE FIREWALL RULES
# ---------------------------------------------------------------------------------------------------------------------

# Allow Vault-specific traffic within the cluster
# - This Firewall Rule may be redundant depending on the settings of your VPC Network, but if your Network is locked down,
#   this Rule will open up the appropriate ports.
resource "google_compute_firewall" "allow_intracluster_vault" {
  name    = "${var.cluster_name}-rule-cluster"
  network = "${var.network_name}"
  project = "${var.network_project_id != "" ? var.network_project_id : var.gcp_project_id}"

  allow {
    protocol = "tcp"

    ports = [
      "${var.cluster_port}",
    ]
  }

  source_tags = ["${var.cluster_tag_name}"]
  target_tags = ["${var.cluster_tag_name}"]
}

# Specify which traffic is allowed into the Vault cluster solely for API requests
# - This Firewall Rule may be redundant depending on the settings of your VPC Network, but if your Network is locked down,
#   this Rule will open up the appropriate ports.
# - Note that public access to your Vault cluster will only be permitted if var.assign_public_ip_addresses is true.
# - This Firewall Rule is only created if at least one source tag or source CIDR block is specified.
resource "google_compute_firewall" "allow_inbound_api" {
  count = "${length(var.allowed_inbound_cidr_blocks_api) + length(var.allowed_inbound_tags_api) > 0 ? 1 : 0}"

  name    = "${var.cluster_name}-rule-external-api-access"
  network = "${var.network_name}"
  project = "${var.network_project_id != "" ? var.network_project_id : var.gcp_project_id}"

  allow {
    protocol = "tcp"

    ports = [
      "${var.api_port}",
    ]
  }

  source_ranges = "${var.allowed_inbound_cidr_blocks_api}"
  source_tags   = ["${var.allowed_inbound_tags_api}"]
  target_tags   = ["${var.cluster_tag_name}"]
}

# If we require a Load Balancer in front of the Vault cluster, we must specify a Health Check so that the Load Balancer
# knows which nodes to route to. But GCP only permits HTTP Health Checks, not HTTPS Health Checks (https://github.com/terraform-providers/terraform-provider-google/issues/18)
# so we must run a separate Web Proxy that forwards HTTP requests to the HTTPS Vault health check endpoint. This Firewall
# Rule permits only the Google Cloud Health Checker to make such requests.
resource "google_compute_firewall" "allow_inbound_health_check" {
  count = "${var.enable_web_proxy}"

  name    = "${var.cluster_name}-rule-health-check"
  network = "${var.network_name}"

  project = "${var.network_project_id != "" ? var.network_project_id : var.gcp_project_id}"

  allow {
    protocol = "tcp"

    ports = [
      "${var.web_proxy_port}",
    ]
  }

  # Per https://goo.gl/xULu8U, all Google Cloud Health Check requests will be sent from 35.191.0.0/16
  source_ranges = ["35.191.0.0/16"]
  target_tags   = ["${var.cluster_tag_name}"]
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A GOOGLE STORAGE BUCKET TO USE AS A VAULT STORAGE BACKEND
# ---------------------------------------------------------------------------------------------------------------------

resource "google_storage_bucket" "vault_storage_backend" {
  name          = "${var.cluster_name}"
  location      = "${var.gcs_bucket_location}"
  storage_class = "${var.gcs_bucket_storage_class}"
  project       = "${var.gcp_project_id}"

  # In prod, the Storage Bucket should NEVER be emptied and deleted via Terraform unless you know exactly what you're doing.
  # However, for testing purposes, it's often convenient to destroy a non-empty Storage Bucket.
  force_destroy = "${var.gcs_bucket_force_destroy}"
}

# ACLs are now deprecated as a way to secure a GCS Bucket (https://goo.gl/PgDCYb0), however the Terraform Google Provider
# does not yet expose a way to attach an IAM Policy to a Google Bucket so we resort to using the Bucket ACL in case users
# of this module wish to limit Bucket permissions via Terraform.
resource "google_storage_bucket_acl" "vault_storage_backend" {
  bucket         = "${google_storage_bucket.vault_storage_backend.name}"
  predefined_acl = "${var.gcs_bucket_predefined_acl}"
}

# ---------------------------------------------------------------------------------------------------------------------
# CONVENIENCE VARIABLES
# Because we've got some conditional logic in this template, some values will depend on our properties. This section
# wraps such values in a nicer construct.
# ---------------------------------------------------------------------------------------------------------------------

# The Google Compute Instance Group needs the self_link of the Compute Instance Template that's actually created.
data "template_file" "compute_instance_template_self_link" {
  # This will return the self_link of the Compute Instance Template that is actually created. It works as follows:
  # - Make a list of 1 value or 0 values for each of google_compute_instance_template.consul_servers_public and
  #   google_compute_instance_template.consul_servers_private by adding the glob (*) notation. Terraform will complain
  #   if we directly reference a resource property that doesn't exist, but it will permit us to turn a single resource
  #   into a list of 1 resource and "no resource" into an empty list.
  # - Concat these lists. concat(list-of-1-value, empty-list) == list-of-1-value
  # - Take the first element of list-of-1-value
  template = "${element(concat(google_compute_instance_template.vault_public.*.self_link, google_compute_instance_template.vault_private.*.self_link), 0)}"
}

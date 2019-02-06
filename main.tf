# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A VAULT CLUSTER IN GOOGLE CLOUD
# This is an example of how to use the vault-cluster module to deploy a public Vault cluster in GCP. A public Vault
# cluster is NOT recommended for production usage, but it's the easiest way to try things out. For production usage,
# see the vault-cluster-private example, or if necessary, the vault-cluster-public example. Note that this Vault cluster
# uses Consul, running in a separate cluster, as its High Availability backend.
# ---------------------------------------------------------------------------------------------------------------------

provider "google" {
  region      = "${var.gcp_region}"
  credentials = "${var.gcp_credentials}"
  project     = "${var.gcp_project_id}"
}

terraform {
  required_version = ">= 0.10.3"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE VAULT SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "vault_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:hashicorp/terraform-google-vault.git//modules/vault-cluster?ref=v0.0.1"
  source = "modules/vault-cluster"

  gcp_project_id = "${var.gcp_project_id}"
  gcp_region     = "${var.gcp_region}"

  cluster_name     = "${var.vault_cluster_name}"
  cluster_size     = "${var.vault_cluster_size}"
  cluster_tag_name = "${var.vault_cluster_name}"
  machine_type     = "${var.vault_cluster_machine_type}"

  crypto_key       = "${var.crypto_key}"
  keyring_location = "${var.keyring_location}"
  key_ring         = "${var.key_ring}"

  source_image   = "${var.vault_source_image}"
  startup_script = "${data.template_file.startup_script_vault.rendered}"

  gcs_bucket_name          = "${var.vault_cluster_name}"
  gcs_bucket_location      = "${var.gcs_bucket_location}"
  gcs_bucket_storage_class = "${var.gcs_bucket_class}"
  gcs_bucket_force_destroy = "${var.gcs_bucket_force_destroy}"

  root_volume_disk_size_gb = "${var.root_volume_disk_size_gb}"
  root_volume_disk_type    = "${var.root_volume_disk_type}"

  # Even when the Vault cluster is pubicly accessible via a Load Balancer, we still make the Vault nodes themselves
  # private to improve the overall security posture. Note that the only way to reach private nodes via SSH is to first
  # SSH into another node that is not private.
  assign_public_ip_addresses = true

  # To enable external access to the Vault Cluster, enter the approved CIDR Blocks or tags below.
  # We enable health checks from the Consul Server cluster to Vault.
  allowed_inbound_cidr_blocks_api = ["0.0.0.0/0"]

  allowed_inbound_tags_api = ["${var.consul_server_cluster_name}"]
}

# Render the Startup Script that will run on each Vault Instance on boot. This script will configure and start Vault.
data "template_file" "startup_script_vault" {
  template = "${file("${path.module}/modules/vault-cluster/startup-script-vault.tpl")}"

  vars {
    consul_cluster_tag_name = "${var.consul_server_cluster_name}"
    vault_cluster_tag_name  = "${var.vault_cluster_name}"

    enable_vault_ui = "${var.enable_vault_ui ? "--enable-ui" : ""}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "consul_cluster" {
  #  source = "git::git@github.com:hashicorp/terraform-google-consul.git//modules/consul-cluster?ref=v0.3.0"
  source = "git::https://github.com/stoffee/terraform-google-consul.git//modules/consul-cluster"

  gcp_project_id = "${var.gcp_project_id}"
  gcp_region     = "${var.gcp_region}"

  cluster_name     = "${var.consul_server_cluster_name}"
  cluster_tag_name = "${var.consul_server_cluster_name}"
  cluster_size     = "${var.consul_server_cluster_size}"

  source_image = "${var.consul_server_source_image}"
  machine_type = "${var.consul_server_machine_type}"

  #startup_script = "${data.template_file.startup_script_consul.rendered}"

  # In a production setting, we strongly recommend only launching a Consul Server cluster as private nodes.
  # Note that the only way to reach private nodes via SSH is to first SSH into another node that is not private.
  assign_public_ip_addresses = true

  allowed_inbound_tags_dns      = ["${var.vault_cluster_name}"]
  allowed_inbound_tags_http_api = ["${var.vault_cluster_name}"]
}

# This Startup Script will run at boot configure and start Consul on the Consul Server cluster nodes
#data "template_file" "startup_script_consul" {
#  template = "${file("${path.module}/examples/root-example/startup-script-consul.sh")}"
#
#  vars {
#    cluster_tag_name = "${var.consul_server_cluster_name}"
#  }
#}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE NOMAD SERVER NODES
# ---------------------------------------------------------------------------------------------------------------------

module "nomad_servers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:hashicorp/terraform-google-nomad.git//modules/nomad-cluster?ref=v0.0.1"
  source = "modules/nomad-cluster"

  gcp_zone = "${var.gcp_zone}"

  cluster_name = "${var.nomad_server_cluster_name}"
  cluster_size = "${var.nomad_server_cluster_size}"
  cluster_tag_name = "${var.nomad_server_cluster_name}"
  machine_type = "${var.nomad_server_cluster_machine_type}"

  source_image = "${var.nomad_server_source_image}"
  startup_script = "${data.template_file.startup_script_nomad_server.rendered}"

  # WARNING!
  # In a production setting, we strongly recommend only launching a Nomad Server cluster as private nodes.
  # Note that the only way to reach private nodes via SSH is to first SSH into another node that is not private.
  assign_public_ip_addresses = true

  # To enable external access to the Nomad Cluster, enter the approved CIDR Blocks below.
  allowed_inbound_cidr_blocks_http = ["0.0.0.0/0"]

  # Enable the Consul Cluster to reach the Nomad Cluster
  allowed_inbound_tags_http = ["${var.consul_server_cluster_name}", "${var.nomad_client_cluster_name}"]
  allowed_inbound_tags_rpc = ["${var.consul_server_cluster_name}", "${var.nomad_client_cluster_name}"]
  allowed_inbound_tags_serf = ["${var.consul_server_cluster_name}", "${var.nomad_client_cluster_name}"]
}

# Render the Startup Script that will run on each Nomad Instance on boot. This script will configure and start Nomad.
data "template_file" "startup_script_nomad_server" {
  template = "${file("${path.module}/modules/nomad-cluster/startup-script-nomad-server.sh")}"

  vars {
    num_servers                      = "${var.nomad_server_cluster_size}"
    consul_server_cluster_tag_name   = "${var.consul_server_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE NOMAD CLIENT NODES
# ---------------------------------------------------------------------------------------------------------------------

module "nomad_clients" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:stoffee/terraform-google-nomad.git//modules/nomad-cluster?ref=v0.0.1"
  source = "modules/nomad-cluster"

  gcp_zone = "${var.gcp_zone}"

  cluster_name = "${var.nomad_client_cluster_name}"
  cluster_size = "${var.nomad_client_cluster_size}"
  cluster_tag_name = "${var.nomad_client_cluster_name}"
  machine_type = "${var.nomad_client_machine_type}"

  source_image = "${var.nomad_client_source_image}"
  startup_script = "${data.template_file.startup_script_nomad_client.rendered}"

  # We strongly recommend setting this to "false" in a production setting. Your Nomad cluster has no reason to be
  # publicly accessible! However, for testing and demo purposes, it is more convenient to launch a publicly accessible
  # Nomad cluster.
  assign_public_ip_addresses = true

  # These inbound clients need only receive requests from Nomad Server and Consul
  allowed_inbound_cidr_blocks_http = ["0.0.0.0/0"]
  allowed_inbound_tags_http = ["${var.consul_server_cluster_name}", "${var.nomad_client_cluster_name}"]
  allowed_inbound_tags_rpc = ["${var.consul_server_cluster_name}", "${var.nomad_client_cluster_name}"]
  allowed_inbound_tags_serf = ["${var.consul_server_cluster_name}", "${var.nomad_client_cluster_name}"]
}

# Render the Startup Script that will configure and run both Consul and Nomad in client mode.
data "template_file" "startup_script_nomad_client" {
  template = "${file("${path.module}/modules/nomad-cluster/startup-script-nomad-client.sh")}"

  vars {
    consul_server_cluster_tag_name   = "${var.consul_server_cluster_name}"
  }
}
# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE Kitteh Image SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "image_service" {
  source = "modules/image-service"

  gcp_project_id = "${var.gcp_project_id}"
  gcp_region     = "${var.gcp_region}"

  cluster_name     = "${var.image_service_name}"
  cluster_tag_name = "${var.image_service_name}"
  cluster_size     = "${var.image_service_size}"

  source_image = "${var.image_service_source_image}"
  machine_type = "${var.image_service_machine_type}"

  startup_script = "${data.template_file.startup_script_image_service.rendered}"

  # In a production setting, we strongly recommend only launching a Consul Server cluster as private nodes.
  # Note that the only way to reach private nodes via SSH is to first SSH into another node that is not private.
  assign_public_ip_addresses = true

  allowed_inbound_tags_dns      = ["${var.image_service_name}"]
  allowed_inbound_tags_http_api = ["${var.image_service_name}"]
}

# This Startup Script will run at boot configure and start the iamge service
data "template_file" "startup_script_image_service" {
  template = "${file("${path.module}/modules/install-image-service/onboot/startup-script-image-service.sh")}"

  vars {
    cluster_tag_name = "${var.image_service_name}"
  }
}

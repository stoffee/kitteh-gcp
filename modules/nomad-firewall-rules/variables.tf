# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# You must provide a value for each of these parameters.
# ---------------------------------------------------------------------------------------------------------------------

variable "gcp_zone" {
  description = "All GCP resources will be launched in this Zone."
}

variable "cluster_name" {
  description = "The name of the Nomad cluster (e.g. nomad-stage). This variable is used to namespace all resources created by this module."
}

variable "cluster_tag_name" {
  description = "The tag name the Compute Instances will look for to automatically discover each other and form a cluster. TIP: If running more than one Nomad cluster, each cluster should have its own unique tag name."
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

variable "network_name" {
  description = "The name of the VPC Network where all resources should be created."
  default = "default"
}

# Firewall Ports

variable "http_port" {
  description = "The port used by Nomad to handle incoming HTPT (API) requests."
  default = 4646
}

variable "rpc_port" {
  description = "The port used by Nomad to handle incoming RPC requests."
  default = 4647
}

variable "serf_port" {
  description = "The port used by Nomad to handle incoming serf requests."
  default = 4648
}

variable "allowed_inbound_cidr_blocks_http" {
  description = "A list of CIDR-formatted IP address ranges from which the Compute Instances will allow connections to Nomad on the port specified by var.http_port."
  type = "list"
  default = ["0.0.0.0/0"]
}

variable "allowed_inbound_tags_http" {
  description = "A list of tags from which the Compute Instances will allow connections to Nomad on the port specified by var.http_port."
  type = "list"
  default = []
}

variable "allowed_inbound_cidr_blocks_rpc" {
  description = "A list of CIDR-formatted IP address ranges from which the Compute Instances will allow connections to Nomad on the port specified by var.rpc_port."
  type = "list"
  default = []
}

variable "allowed_inbound_tags_rpc" {
  description = "A list of tags from which the Compute Instances will allow connections to Nomad on the port specified by var.rpc_port."
  type = "list"
  default = []
}

variable "allowed_inbound_cidr_blocks_serf" {
  description = "A list of CIDR-formatted IP address ranges from which the Compute Instances will allow connections to Nomad on the port specified by var.serf_port."
  type = "list"
  default = []
}

variable "allowed_inbound_tags_serf" {
  description = "A list of tags from which the Compute Instances will allow connections to Nomad on the port specified by var.serf_port."
  type = "list"
  default = []
}
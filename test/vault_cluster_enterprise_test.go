package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/gcp"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/gruntwork-io/terratest/modules/test-structure"
)

const (
	TFVAR_NAME_AUTOUNSEAL_KEY_PROJECT     = "vault_auto_unseal_key_project_id"
	TFVAR_NAME_AUTOUNSEAL_KEY_REGION      = "vault_auto_unseal_key_region"
	TFVAR_NAME_AUTOUNSEAL_KEY_RING_NAME   = "vault_auto_unseal_key_ring"
	TFVAR_NAME_AUTOUNSEAL_CRYPTO_KEY_NAME = "vault_auto_unseal_crypto_key_name"

	AUTOUNSEAL_KEY_REGION      = "global"
	AUTOUNSEAL_KEY_RING_NAME   = "vault-cluster-automated-tests"
	AUTOUNSEAL_CRYPTO_KEY_NAME = "circle-ci"
)

// const (
// 	VaultClusterExampleVarVaultSourceImage         = "vault_source_image"
// 	VaultClusterExampleVarConsulSourceImage        = "consul_server_source_image"
// 	VaultClusterExampleVarVaultClusterMachineType  = "vault_cluster_machine_type"
// 	VaultClusterExampleVarConsulClusterMachineType = "consul_server_machine_type"
// 	VaultClusterAllowedInboundCidrBlockHttpApi     = "allowed_inbound_cidr_blocks_api"
// 	VaultClusterExampleCreateKmsCryptoKey          = "create_kms_crypto_key"
// 	VaultClusterExampleKmsCryptoKeyName            = "kms_crypto_key_name"
// 	VaultClusterExampleKmsCryptoKeyRingName        = "kms_crypto_key_ring_name"
// 	VaultClusterExampleVarVaultClusterName         = "vault_cluster_name"
// 	VaultClusterExampleVarConsulClusterName        = "consul_server_cluster_name"
// 	VaultClusterExampleVarAutoUnsealProject        = "vault_auto_unseal_project_id"
// 	VaultClusterExampleVarAutoUnsealRegion         = "vault_auto_unseal_region"
// 	VaultClusterExampleVarAutoUnsealKeyRingName    = "vault_auto_unseal_key_ring"
// 	VaultClusterExampleVarAutoUnsealCryptoKey      = "vault_auto_unseal_crypto_key"
// 	VaultClusterExampleVarSecret                   = "example_secret"
// )

// To test this on CircleCI you need two URLs set as environment variables (VAULT_PACKER_TEMPLATE_VAR_CONSUL_DOWNLOAD_URL
// & VAULT_PACKER_TEMPLATE_VAR_VAULT_DOWNLOAD_URL) so the Vault & Consul Enterprise versions can be downloaded. You would
// also need to set these two variables locally to run the tests. The reason behind this is to prevent the actual url
// from being visible in the code and logs.
//
// To test this on CircleCI you need a url set as an environment variable, VAULT_AMI_TEMPLATE_VAR_DOWNLOAD_URL
// which you would also have to set locally if you want to run this test locally.
// The reason is to prevent the actual url from being visible on code and logs
//
// Test the Vault enterprise cluster example by:
//
// 1. Copy the code in this repo to a temp folder so tests on the Terraform code can run in parallel without the
//    state files overwriting each other.
// 2. Build the Cloud Image in the vault-consul-image example with the given build name and the enterprise packages
// 3. Deploy that Image using the example Terraform code
// 4. TODO - SSH into a Vault node and initialize the Vault cluster
// 5. TODO - SSH to each Vault node and unseal it
// 6. TODO - SSH to a Vault node and make sure you can communicate with the nodes via Consul-managed DNS
// 7. TODO - SSH to a Vault node and check if Vault enterprise is installed properly
func runVaultEnterpriseClusterTest(t *testing.T) {
	exampleDir := test_structure.CopyTerraformFolderToTemp(t, "../", "examples/vault-cluster-enterprise")

	defer test_structure.RunTestStage(t, "teardown", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, exampleDir)
		terraform.Destroy(t, terraformOptions)
	})

	defer test_structure.RunTestStage(t, "log", func() {
		//ToDo: Modify log retrieval to go through bastion host
		//      Requires adding feature to terratest
		//writeVaultLogs(t, "vaultPublicCluster", exampleDir)
	})

	test_structure.RunTestStage(t, "deploy", func() {
		// GCP only supports lowercase names for some resources
		// uniqueID := strings.ToLower(random.UniqueId())
		// imageID := test_structure.LoadArtifactID(t, exampleDir)
		// projectID := test_structure.LoadString(t, exampleDir, GCPProjectIdVarName)
		// gcpRegion := test_structure.LoadString(t, exampleDir, GCPRegionVarName)
		// gcpZone := test_structure.LoadString(t, exampleDir, GCPZoneVarName)

		projectId := test_structure.LoadString(t, WORK_DIR, SAVED_GCP_PROJECT_ID)
		region := test_structure.LoadString(t, WORK_DIR, SAVED_GCP_REGION_NAME)
		imageID := test_structure.LoadString(t, WORK_DIR, SAVED_OPEN_SOURCE_VAULT_IMAGE)

		// GCP only supports lowercase names for some resources
		uniqueID := strings.ToLower(random.UniqueId())

		consulClusterName := fmt.Sprintf("consul-test-%s", uniqueID)
		vaultClusterName := fmt.Sprintf("vault-test-%s", uniqueID)

		//keyPair := aws.CreateAndImportEC2KeyPair(t, awsRegion, uniqueId)
		//test_structure.SaveEc2KeyPair(t, examplesDir, keyPair)

		terraformOptions := &terraform.Options{
			TerraformDir: exampleDir,
			Vars: map[string]interface{}{
				TFVAR_NAME_GCP_PROJECT_ID:                     projectId,
				TFVAR_NAME_GCP_REGION:                         region,
				TFVAR_NAME_CONSUL_SERVER_CLUSTER_NAME:         consulClusterName,
				TFVAR_NAME_CONSUL_SOURCE_IMAGE:                imageID,
				TFVAR_NAME_CONSUL_SERVER_CLUSTER_MACHINE_TYPE: "g1-small",
				TFVAR_NAME_VAULT_CLUSTER_NAME:                 vaultClusterName,
				TFVAR_NAME_VAULT_SOURCE_IMAGE:                 imageID,
				TFVAR_NAME_VAULT_CLUSTER_MACHINE_TYPE:         "g1-small",
				TFVAR_NAME_BASTION_SERVER_NAME:                fmt.Sprintf("bastion-test-%s", uniqueID),
				TFVAR_NAME_AUTOUNSEAL_KEY_PROJECT:             projectId,
				TFVAR_NAME_AUTOUNSEAL_KEY_REGION:              AUTOUNSEAL_KEY_REGION,
				TFVAR_NAME_AUTOUNSEAL_KEY_RING_NAME:           AUTOUNSEAL_KEY_RING_NAME,
				TFVAR_NAME_AUTOUNSEAL_CRYPTO_KEY_NAME:         AUTOUNSEAL_CRYPTO_KEY_NAME,

				//	VAR_CONSUL_CLUSTER_TAG_KEY: fmt.Sprintf("consul-test-%s", uniqueId),
				//	VAR_SSH_KEY_NAME:           keyPair.Name,
				// VAULTCLUSTEREXAMPLEVARPROJECT:                  projectID,
				// VAULTCLUSTEREXAMPLEVARREGION:                   gcpRegion,
				// VAULTCLUSTEREXAMPLEVARZONE:                     gcpZone,
				// VAULTCLUSTEREXAMPLEVARVAULTCLUSTERNAME:         fmt.Sprintf("vault-test-%s", uniqueID),
				// VAULTCLUSTEREXAMPLEVARCONSULCLUSTERNAME:        fmt.Sprintf("consul-test-%s", uniqueID),
				// VAULTCLUSTEREXAMPLEVARVAULTCLUSTERMACHINETYPE:  "n1-standard-1",
				// VAULTCLUSTEREXAMPLEVARCONSULCLUSTERMACHINETYPE: "n1-standard-1",
				// VAULTCLUSTEREXAMPLEVARCONSULSOURCEIMAGE:        imageID,
				// VAULTCLUSTEREXAMPLEVARVAULTSOURCEIMAGE:         imageID,
				// VAULTCLUSTERALLOWEDINBOUNDCIDRBLOCKHTTPAPI:     []string{"0.0.0.0/0"},
				// VAULTCLUSTEREXAMPLECREATEKMSCRYPTOKEY:          false,
				// VAULTCLUSTEREXAMPLEKMSCRYPTOKEYNAME:            "vault-test",
				// VAULTCLUSTEREXAMPLEKMSCRYPTOKEYRINGNAME:        "global/gruntwork-test",
				// VAULTCLUSTEREXAMPLEVARAUTOUNSEALPROJECT:        projectID,
				// VAULTCLUSTEREXAMPLEVARAUTOUNSEALREGION:         gcpRegion,
				// VAULTCLUSTEREXAMPLEVARAUTOUNSEALKEYRINGNAME:    "global/gruntwork-test",
				// VAULTCLUSTEREXAMPLEVARAUTOUNSEALCRYPTOKEY:      "vault-test",
				// VAULTCLUSTEREXAMPLEVARSECRET:                   fmt.Sprintf("example-secret-%s", uniqueID),
			},
		}
		test_structure.SaveTerraformOptions(t, exampleDir, terraformOptions)

		terraform.InitAndApply(t, terraformOptions)
	})

	// TODO copied from private test
	test_structure.RunTestStage(t, "validate", func() {
		terraformOptions := test_structure.LoadTerraformOptions(t, exampleDir)
		projectId := test_structure.LoadString(t, WORK_DIR, SAVED_GCP_PROJECT_ID)
		region := test_structure.LoadString(t, WORK_DIR, SAVED_GCP_REGION_NAME)
		instanceGroupId := terraform.OutputRequired(t, terraformOptions, TFOUT_INSTANCE_GROUP_ID)

		sshUserName := "terratest"
		keyPair := ssh.GenerateRSAKeyPair(t, 2048)
		saveKeyPair(t, exampleDir, keyPair)
		addKeyPairToInstancesInGroup(t, projectId, region, instanceGroupId, keyPair, sshUserName)

		bastionName := terraform.OutputRequired(t, terraformOptions, TFVAR_NAME_BASTION_SERVER_NAME)
		bastionInstance := gcp.FetchInstance(t, projectId, bastionName)
		bastionInstance.AddSshKey(t, sshUserName, keyPair.PublicKey)
		bastionHost := ssh.Host{
			Hostname:    bastionInstance.GetPublicIp(t),
			SshUserName: sshUserName,
			SshKeyPair:  keyPair,
		}

		cluster := testVaultInitializeAutoUnseal(t, projectId, region, instanceGroupId, sshUserName, keyPair, &bastionHost)
		//cluster := initializeAndUnsealVaultCluster(t, projectId, region, instanceGroupId, sshUserName, keyPair, &bastionHost)
		testVaultUsesConsulForDns(t, cluster, &bastionHost)
	})
}

func testVaultInitializeAutoUnseal(t *testing.T, projectId string, region string, instanceGroupId string, sshUserName string, sshKeyPair *ssh.KeyPair, bastionHost *ssh.Host) *VaultCluster {
	cluster := findVaultClusterNodes(t, projectId, region, instanceGroupId, sshUserName, sshKeyPair, bastionHost)

	verifyCanSsh(t, cluster, bastionHost)
	assertAllNodesBooted(t, cluster, bastionHost)
	initializeVault(t, cluster, bastionHost)

	//assertNodeStatus(t, cluster.Leader, bastionHost, Sealed)
	//unsealNode(t, cluster.Leader, bastionHost, cluster.UnsealKeys)
	assertNodeStatus(t, cluster.Leader, bastionHost, Leader)

	//assertNodeStatus(t, cluster.Standby1, bastionHost, Sealed)
	//unsealNode(t, cluster.Standby1, bastionHost, cluster.UnsealKeys)
	//assertNodeStatus(t, cluster.Standby1, bastionHost, Standby)

	//assertNodeStatus(t, cluster.Standby2, bastionHost, Sealed)
	//unsealNode(t, cluster.Standby2, bastionHost, cluster.UnsealKeys)
	//assertNodeStatus(t, cluster.Standby2, bastionHost, Standby)

	return cluster
}

// Scenario 9: Key Vault (RBAC model) reachable only from one subnet (service endpoint)
// plus your own /32, and a VM identity that can read exactly one secret.
// Written from the live, portal/CLI-built lab and checked with what-if (no deploy needed).
// Not included on purpose: the VM (built with the CLI) and the secret VALUE - secret values
// don't belong in templates or deployment history.

targetScope = 'resourceGroup'

@description('Key Vault name (globally unique).')
param vaultName string

@description('Region for all resources.')
param location string = resourceGroup().location

@description('Object ID of the VM system-assigned managed identity that reads the secret.')
param readerPrincipalId string

@description('Your public IP for data-plane access during the lab, e.g. 203.0.113.10/32. Pass at deploy time; never commit it.')
param allowedClientIp string

@description('Existing secret the identity may read. Created out-of-band, not by this template.')
param secretName string = 'app-db-password'

@description('Role assignment name. Defaults to a deterministic guid; pass the existing name to adopt a CLI-created assignment.')
param readerAssignmentName string = guid(resourceGroup().id, vaultName, secretName, readerPrincipalId, 'Key Vault Secrets User')

var tags = {
  project: 'scenario-9'
  purpose: 'keyvault-mi-lab'
  owner: 'lab'
}

// Key Vault Secrets User: read secret values only (built-in role ID, same in every tenant)
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-s9'
  location: location
  tags: { project: 'scenario-9' }
  properties: {
    addressSpace: {
      addressPrefixes: [ '10.90.0.0/16' ]
    }
    // Declared so what-if stays clean: the platform sets this default, and leaving it
    // undeclared shows up as drift on every run (same finding as P3 RCA-002)
    privateEndpointVNetPolicies: 'Disabled'
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.90.1.0/24'
          defaultOutboundAccess: false // private subnet: no implicit internet egress
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true // Azure RBAC data roles, not access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // enablePurgeProtection omitted on purpose: once true it can't be turned off,
    // and the vault name stays reserved for the retention period.
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [
        {
          value: allowedClientIp
        }
      ]
      virtualNetworkRules: [
        {
          id: vnet.properties.subnets[0].id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  parent: vault
  name: secretName
}

// Least privilege: the role is scoped to ONE secret, not the vault
resource secretReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: readerAssignmentName
  scope: secret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: readerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output vaultUri string = vault.properties.vaultUri
output subnetId string = vnet.properties.subnets[0].id

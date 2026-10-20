@description('Region for the workload')
param location string

@description('Tags applied to the workload resources')
param tags object

resource vnet 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: 'vnet-access-lab'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.50.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.50.1.0/24'
        }
      }
    ]
  }
}

// ─── Storage for Scenario 5 (data-plane access) ─────────────
resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: 'stacclab${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: storage
  name: 'default'
}

resource reportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: 'reports'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storage.name

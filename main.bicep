targetScope = 'subscription'

@description('Region for all lab resources')
param location string = 'eastus'

@description('Tags applied to every resource group and resource')
param tags object = {
  project: 'access-troubleshooting-lab'
  environment: 'lab'
  owner: 'jeff'
  costCenter: 'CC-1001'
}

// ─── Resource groups ────────────────────────────────────────
resource rgApp 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-access-lab-app'
  location: location
  tags: tags
}

resource rgOther 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-access-lab-other'
  location: location
  tags: tags
}

// ─── Workload in the app resource group ─────────────────────
module workload 'modules/workload.bicep' = {
  name: 'deploy-workload'
  scope: rgApp
  params: {
    location: location
    tags: tags
  }
}


output storageAccountName string = workload.outputs.storageAccountName

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

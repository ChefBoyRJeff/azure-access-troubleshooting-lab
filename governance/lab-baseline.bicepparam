using './lab-baseline.bicep'

// Deploy with: az deployment mg what-if / create --management-group-id mg-lab --location eastus ...
param initiativeName = '9ffe7bb83c325a0ab4f354fa' // portal-generated name of the existing definition
param identityLocation = 'eastus'
param allowedLocations = [
  'eastus'
]
param tagName = 'costCenter'
param enforcementMode = 'Default'

// VM-based service template: .NET service on a Linux VM, logs shipped by Azure Monitor Agent (AMA).
// Per service, per environment, at resource-group scope.
targetScope = 'resourceGroup'

@description('Short service name, e.g. "orders". Lower-case letters, digits, hyphens.')
@minLength(3)
@maxLength(12)
param workload string

@allowed(['dev', 'test', 'prod'])
param environment string

param location string = resourceGroup().location

@description('VM size. B2s is fine for dev; use D-series for prod.')
param vmSize string = 'Standard_B2s'

@description('Admin username. There is no inbound SSH rule; access is via Azure Bastion / serial console if ever needed.')
param adminUsername string = 'azureadmin'

@description('SSH public key for the admin user (password auth is disabled).')
param adminSshPublicKey string

@description('Team alert mailbox / DL.')
param alertEmail string

@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('TCP port the service listens on (localhost only, unless you add a load balancer).')
param appPort int = 8080

param vnetAddressPrefix string = '10.20.0.0/24'
param subnetPrefix string = '10.20.0.0/26'

param tags object = {}

var uniq = take(uniqueString(resourceGroup().id), 5)
var baseName = '${workload}-${environment}'
var keyVaultName = 'kv${take(toLower(replace(workload, '-', '')), 8)}${environment}${take(uniqueString(subscription().id, resourceGroup().id), 8)}'
var allTags = union({
  workload: workload
  environment: environment
  managedBy: 'platform-vm-template'
}, tags)

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    baseName: baseName
    location: location
    retentionDays: logRetentionDays
    alertEmail: alertEmail
    tags: allTags
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    baseName: baseName
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    subnetPrefix: subnetPrefix
    appPort: appPort
    tags: allTags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: 'st${take(replace(workload, '-', ''), 10)}${take(environment, 4)}${uniq}'
    location: location
    tags: allTags
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: allTags
  }
}

module vm 'modules/vm.bicep' = {
  name: 'vm'
  params: {
    name: 'vm-${baseName}'
    location: location
    vmSize: vmSize
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
    subnetId: network.outputs.subnetId
    appPort: appPort
    storageAccountName: storage.outputs.name
    keyVaultName: keyVault.outputs.name
    dataCollectionRuleId: monitoring.outputs.dataCollectionRuleId
    tags: allTags
  }
}

output vmName string = vm.outputs.name
output storageAccountName string = storage.outputs.name
output artifactContainer string = storage.outputs.containerName
output workspaceName string = monitoring.outputs.workspaceName
output vmPrincipalId string = vm.outputs.principalId
output keyVaultName string = keyVault.outputs.name

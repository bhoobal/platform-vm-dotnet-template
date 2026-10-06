param baseName string
param location string
param vnetAddressPrefix string
param subnetPrefix string
param appPort int
param tags object

// No public IP on the VM and no inbound rules from the internet. Default outbound access is
// retired for new subnets, so outbound (AMA, package feeds, storage) goes through a NAT gateway.

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${baseName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-app-from-vnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: string(appPort)
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource natIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-nat-${baseName}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'ng-${baseName}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [{ id: natIp.id }]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${baseName}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [vnetAddressPrefix] }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: subnetPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: { id: nsg.id }
          natGateway: { id: nat.id }
        }
      }
    ]
  }
}

output subnetId string = vnet.properties.subnets[0].id

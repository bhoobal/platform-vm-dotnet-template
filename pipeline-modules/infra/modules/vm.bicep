param name string
param location string
param vmSize string
param adminUsername string
param adminSshPublicKey string
param subnetId string
param appPort int
param storageAccountName string
param keyVaultName string
param dataCollectionRuleId string
param tags object

// Built-in role: Storage Blob Data Reader (read release artifacts only)
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// cloud-init: create an unprivileged service user, release dirs and the systemd unit.
// The unit logs to syslog facility local0 so AMA collects it via rsyslog.
var cloudInit = '''
#cloud-config
users:
  - name: svc
    system: true
    shell: /usr/sbin/nologin
    no_create_home: true
write_files:
  - path: /etc/systemd/system/app.service
    permissions: '0644'
    content: |
      [Unit]
      Description=Sample .NET service
      After=network-online.target
      Wants=network-online.target

      [Service]
      User=svc
      WorkingDirectory=/opt/app/current
      ExecStart=/opt/app/current/SampleService
      Restart=always
      RestartSec=5
      Environment=ASPNETCORE_URLS=http://0.0.0.0:__PORT__
      Environment=DOTNET_ENVIRONMENT=Production
      EnvironmentFile=-/etc/app/app.env
      SyslogIdentifier=sampleservice
      SyslogFacility=local0
      StandardOutput=journal
      StandardError=journal
      # Hardening: the service needs no privileges
      NoNewPrivileges=true
      ProtectSystem=strict
      ProtectHome=true
      PrivateTmp=true

      [Install]
      WantedBy=multi-user.target
runcmd:
  - mkdir -p /opt/app/releases /etc/app
  - chown -R svc:svc /opt/app
  - systemctl daemon-reload
  - systemctl enable app.service
'''

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnetId }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' } // AMA authenticates with this identity; also used to pull releases
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: take(name, 15)
      adminUsername: adminUsername
      customData: base64(replace(cloudInit, '__PORT__', string(appPort)))
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: { bypassPlatformSafetyChecksOnUserSchedule: false }
        }
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }]
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

// Azure Monitor Agent
resource ama 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      authentication: {
        managedIdentity: {
          'identifier-name': 'mi_res_id'
          'identifier-value': vm.id
        }
      }
    }
  }
}

// Bind the DCR to the VM (this is what tells AMA what to collect).
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'dcra-${name}'
  scope: vm
  properties: {
    dataCollectionRuleId: dataCollectionRuleId
    description: 'Collect app + OS syslog and perf counters.'
  }
  dependsOn: [ama]
}

// Least privilege: the VM can read blobs in the one artifact storage account, nothing else.
resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource blobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, vm.id, storageBlobDataReaderRoleId)
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, vm.id, keyVaultSecretsUserRoleId)
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
  }
}

output name string = vm.name
output principalId string = vm.identity.principalId

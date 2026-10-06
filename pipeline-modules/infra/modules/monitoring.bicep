param baseName string
param location string
param retentionDays int
param alertEmail string
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'log-${baseName}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: retentionDays
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

// Data Collection Rule: what AMA collects and where it sends it.
// App logs: the service writes to stdout; systemd forwards to syslog facility local0,
// which AMA picks up through rsyslog. OS auth/daemon logs and perf counters are included.
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-${baseName}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'app-and-os-syslog'
          streams: ['Microsoft-Syslog']
          facilityNames: ['local0', 'auth', 'authpriv', 'daemon']
          // Info and above for the app facility keeps request/lifecycle logs; tighten to 'Warning' to cut cost.
          logLevels: ['Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency']
        }
      ]
      performanceCounters: [
        {
          name: 'basic-perf'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            'Processor(*)\\% Processor Time'
            'Memory(*)\\% Used Memory'
            'Logical Disk(*)\\% Used Space'
            'Network(*)\\Total Bytes'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'law'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Syslog', 'Microsoft-Perf']
        destinations: ['law']
      }
    ]
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${baseName}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: take('ag${replace(baseName, '-', '')}', 12)
    enabled: true
    emailReceivers: [
      {
        name: 'service-team'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Alert 1: the agent stopped sending heartbeats (VM down, agent broken, or network cut).
resource heartbeatAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-${baseName}-heartbeat'
  location: location
  tags: tags
  properties: {
    displayName: '${baseName}: no AMA heartbeat'
    description: 'No Heartbeat received from the VM in the last 10 minutes.'
    severity: 1
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          query: 'Heartbeat | where Category == "Azure Monitor Agent" | summarize LastBeat = max(TimeGenerated) | where LastBeat < ago(10m)'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    actions: { actionGroups: [actionGroup.id] }
  }
}

// Alert 2: the app logged errors (syslog severity err or worse on local0).
resource errorAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'alert-${baseName}-app-errors'
  location: location
  tags: tags
  properties: {
    displayName: '${baseName}: application errors'
    description: 'More than 5 error-level app log lines in 5 minutes.'
    severity: 2
    enabled: true
    scopes: [workspace.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'Syslog | where Facility == "local0" and SeverityLevel in ("err","crit","alert","emerg")'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    actions: { actionGroups: [actionGroup.id] }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output dataCollectionRuleId string = dcr.id

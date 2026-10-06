using '../main.bicep'

param workload = 'saas-svc'
param environment = 'dev'
param vmSize = 'Standard_B2s'
param adminSshPublicKey = 'ssh-ed25519 AAAAREPLACE_WITH_YOUR_PUBLIC_KEY'
param alertEmail = 'saas-svc-team@example.com'
param logRetentionDays = 30

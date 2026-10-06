using '../main.bicep'

param workload = 'saas-svc'
param environment = 'prod'
param vmSize = 'Standard_D2s_v5'
param adminSshPublicKey = 'ssh-ed25519 AAAAREPLACE_WITH_YOUR_PUBLIC_KEY'
param alertEmail = 'saas-svc-team@example.com'
param logRetentionDays = 90

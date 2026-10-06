# Build a Self-Service Platform Capability

## Scenario
### Overview
Your company runs a single-tenant SaaS platform on Azure. You are asked to design and
implement a minimal platform capability that enables an engineering team to deploy a
service to Azure in a safe, consistent, and repeatable way.
This exercise reflects real platform engineering work. We are less interested in perfection
and more interested in your thinking, structure, and trade-offs.

### Objective
Create a reusable solution that allows a team to:
 Deploy a service to Azure
    [] Deploy .net service to a linux VM
 Use Infrastructure as Code
    [] Organize Bicep templates into reusable modules that can be consumed from a separate repository, pinned to a version tag or tracking its main branch
 Deploy via a CI/CD pipeline
 [] azure-pipeline.yaml
    Build, Checkout bicep and deployment module, run unit test, publish , deploy to dev and production based on condition
 Have basic security and observability built in
    [] Deploy VM in private subnet 
    [] Data collection - CPU, memory, disk usage collection metrics

### Requirements
Your solution should include:
1. Infrastructure (IaC)
Use Bicep (preferred), Terraform or similar to provision:
 A compute resource (e.g. App Service, Function, or container-based service)
 Supporting resources (e.g. resource group, monitoring)
 Identity (managed identity preferred)
2. CI/CD Pipeline
Provide a pipeline definition (Azure DevOps):
 Build step
 Deploy step
 At least one validation or safety check

3. Security (Baseline)
 Use a secure approach (e.g. Key Vault or managed identity)
 Apply least privilege principles where possible
4. Observability

Confidential
(External)

 Enable logging and/or monitoring
 Ensure basic visibility into application health

5. Documentation (Important)
Provide a short README that explains:
 What your solution does
 How a team would use it
 Any assumptions or trade-offs

Time Expectation
 Expected effort: 2–4 hours
 Please do not over-engineer, focus on clarity and intent

Submission
Provide:
 A Git repository (preferred), or
 A zip file containing your solution
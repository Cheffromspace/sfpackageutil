# Salesforce Managed Package Utility

A PowerShell module for managing Salesforce managed package installations across orgs. This utility helps automate the process of installing and updating managed packages, with built-in retry mechanisms and dependency management.

## Features

- Install and update managed packages from a configuration file
- Automatic retry mechanism for failed installations (up to 3 attempts)
- Packages installed in configuration file order
- Support for installation keys and security types
- Configuration synchronization between orgs
- Clear status messages and progress tracking

## Prerequisites

- PowerShell 5.1 or later
- Salesforce CLI (sf) installed and configured
- Active Salesforce org with appropriate permissions

## Pipeline use instructions

1. In Salesforce Sandbox - Retrieve Consumer key

- Option 1: UI Method

  - Navigate to Setup > App Manager > SFDX_CI > View
  - Click Manage Consumer Details
  - Complete verification (email/authenticator)
  - Copy Consumer Key

- Option 2: CLI Method
  - sf project retrieve start --target-org [username] --metadata ConnectedApp:SFDX_CI
  - Extract and copy key from XML file

2. In Bitbucket - Run Pipeline

- Navigate to: Salesforce Repository > Pipelines
  - Set pipeline parameters:
  - Branch:
    - Branch you want to sync with. `master` for Production, `develop` for Test sandbox, etc.
  - Pipeline: install-managed-packages-manually
    - Variables:
      - CONSUMER_KEY: (paste from previous step)
      - SFDC_USERNAME: deployment.user@zlamas.com.[sandbox name]

3. Click Run

4. Verification

- Confirm pipeline completed without errors
- Check managed packages installed in sandbox

## Local Installation

Use the Absolute Path when importing the module, e.g.,
`C:\Users\e12345\Documents\salesforce\build\SfManagedPackageUtility\SfManagedPackageUtility.psd1`

- Import the module:

```powershell
Import-Module {Absolute Path}
```

- Confirm Installation:

`Get-Command -Module SfManagedPackageUtility`

## Usage

### Configuration File

Create a JSON configuration file (`PackageConfig.json`) with your package details:

```json
{
  "packages": [
    {
      "namespace": "MyPackage",
      "packageId": "04t...",
      "version": "1.2.0",
      "password": "optional-install-key",
      "securityType": "AdminsOnly"
    }
  ]
}
```

## Available Functions

### Install-SalesforcePackages

Installs or updates packages in a target org based on the configuration file.

Parameters:

- `TargetOrg` (Required): Username or alias of the target org
- `ConfigPath` (Optional): Path to configuration file (defaults to ./PackageConfig.json)

### Update-ConfigFileFromOrg

Updates the package configuration file with versions and IDs from a source org.

Parameters:

- `SourceOrg` (Required): Username or alias of the source org
- `ConfigPath` (Optional): Path to configuration file (defaults to ./PackageConfig.json)

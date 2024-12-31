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

## Installation

1. Clone this repository or download the module files
2. Place the module files in your PowerShell modules directory
3. Import the module:
```powershell
Import-Module SfManagedPackageUtility
```

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
      "securityType": "AdminsOnly",
    }
  ]
}
```

### Update Configuration from Source Org

Sync your configuration file with package versions from a source org:

```powershell
Update-ConfigFileFromOrg -SourceOrg myorg@example.com
```

### Install Packages in Target Org

Install or update packages in a target org based on the configuration:

```powershell
Install-SalesforcePackages -TargetOrg targetorg@example.com
```

## Retry Mechanism

The module includes an automatic retry system for handling failed package installations:

- Failed installations are automatically retried up to 3 times
- Successfully installed packages are removed from the retry queue
- 5-second delay between retry attempts
- Clear status messages show which packages succeeded or failed
- Final summary lists any packages that failed after all retry attempts

## Available Functions

### Update-ConfigFileFromOrg

Updates the package configuration file with versions and IDs from a source org.

Parameters:
- `SourceOrg` (Required): Username or alias of the source org
- `ConfigPath` (Optional): Path to configuration file (defaults to ./PackageConfig.json)

### Install-SalesforcePackages

Installs or updates packages in a target org based on the configuration file.

Parameters:
- `TargetOrg` (Required): Username or alias of the target org
- `ConfigPath` (Optional): Path to configuration file (defaults to ./PackageConfig.json)

## Error Handling

- Comprehensive error messages for installation failures
- Validation of configuration file format and required fields
- Automatic retry for failed installations
- Detailed logging of installation progress and results

## Best Practices

1. Always test package installations in a sandbox environment first
2. Keep your configuration file under version control
3. Use descriptive org aliases for better clarity
4. Review the installation preview before proceeding
5. Monitor the installation logs for any warnings or errors
6. Order packages in the configuration file based on their installation requirements

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

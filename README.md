# Exchange Online to Swyx Phonebook Sync

Automatic synchronization of Exchange Online mail contacts into the global Swyx phonebook.

This project is intended as a practical helper tool for administrators who want a lightweight PowerShell-based sync between Microsoft 365 and Swyx without introducing CSV exports, additional middleware, or a separate database.

It is designed as an automation aid, not as a full product or officially supported integration layer.

## Features

- Automatic add, update, and remove sync
- App-only authentication against Exchange Online using a certificate
- Reads centralized Exchange mail contacts
- Normalizes phone numbers into E.164 format
- Daily rotating log files
- Ready for Windows Task Scheduler
- Deduplication of desired entries before sync

## Architecture

```text
Exchange Online (MailContacts)
            |
            v
PowerShell Script (App Authentication)
            |
            v
  Swyx PowerShell (IpPbx)
            |
            v
   Global Swyx Phonebook
```

## Requirements

### Microsoft 365

- Exchange Online
- Entra ID access
- Administrative rights to create and consent an app registration

### Swyx Environment

- SwyxWare installed
- Swyx PowerShell / `IpPbx` cmdlets available
- Windows authentication working for the service account

## Service Account

The scheduled task should run under a dedicated Windows user.

Recommended characteristics:

- Windows user exists
- Swyx user exists
- no active Swyx license required
- Swyx administrative permissions assigned
- Windows logon works for Swyx management

That account must be able to run the following successfully in an interactive session:

```powershell
Connect-IpPbx
```

## Microsoft 365 Setup

### 1. Create an App Registration

Create a new app registration in Entra ID, for example:

- Name: `EXO-Swyx-Sync`
- Supported account types: `Single tenant`

### 2. Create a Certificate

Example:

```powershell
$cert = New-SelfSignedCertificate `
  -Subject "CN=EXO-Swyx-Sync" `
  -CertStoreLocation "Cert:\LocalMachine\My"
```

### 3. Export the Public Certificate

```powershell
Export-Certificate -Cert $cert -FilePath "C:\Temp\cert.cer"
```

### 4. Upload the Certificate

Upload the exported `.cer` file to the app registration under:

`Certificates & secrets -> Certificates`

### 5. Grant API Permissions

Required Exchange Online application permission:

- `Exchange.ManageAsApp`

After assigning it, grant tenant-wide admin consent.

### 6. Assign an Exchange Role

The service principal must have sufficient Exchange permissions to read the required contact objects.

Document the required role model in a generic way and avoid hardcoding tenant-specific assignments in public documentation.

## Test the Exchange Connection

Example app-only login:

```powershell
Connect-ExchangeOnline `
  -AppId "<APP_ID>" `
  -CertificateThumbprint "<THUMBPRINT>" `
  -Organization "<tenant>.onmicrosoft.com"
```

After connecting, test:

```powershell
Get-MailContact
Get-Contact
```

## Test the Swyx Connection

```powershell
Connect-IpPbx
Get-IpPbxPhonebookEntry -GlobalPhoneBook
```

## Project Files

- `Sync-ExchangeToSwyx.ps1` - main synchronization script
- `Exchange-Swyx-Phonebook-Sync.sample.xml` - example Windows Task Scheduler definition
- `LICENSE` - MIT license

## Installation

Example script path:

```text
C:\Scripts\Sync-ExchangeToSwyx.ps1
```

## Configuration

Adjust the configuration block at the top of `Sync-ExchangeToSwyx.ps1`:

```powershell
$Marker = "[EXO-SYNC]"
$LogBasePath = "C:\System\Swyxware\Scripts\Logs\SwyxSync.log"
$LogRetentionDays = 2
$AddDefaultCountryCodeToLocalNumbers = $false
$DefaultCountryCode = "39"
```

### Configuration Options

- `$Marker` identifies entries managed by this script
- `$LogBasePath` defines the base path for dated daily log files
- `$LogRetentionDays` controls how many days logs are retained
- `$AddDefaultCountryCodeToLocalNumbers` converts local numbers starting with `0`
- `$DefaultCountryCode` defines the country code used for local-number conversion

## Phone Number Format

The script is intended to store numbers in E.164-style format, for example:

```text
+390000000001
+490000000001
```

## Usage

Run the sync manually:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1
```

Run a dry-run without changing Swyx:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1 -WhatIf
```

## Task Scheduler

The repository includes an anonymized sample definition in `Exchange-Swyx-Phonebook-Sync.sample.xml`.

Suggested task settings:

- Run whether user is logged on or not
- Run with highest privileges

Typical trigger:

- Daily at `06:00`
- Optional repeat every `4 hours`

Typical action:

- Program: `powershell.exe`
- Arguments:

```powershell
-ExecutionPolicy Bypass -NoProfile -File "C:\Scripts\Sync-ExchangeToSwyx.ps1"
```

## Logging

Example configuration:

```powershell
$LogBasePath = "C:\Logs\SwyxSync.log"
```

Example generated file:

```text
C:\Logs\SwyxSync_2026-03-19.log
```

Example retention:

```powershell
$LogRetentionDays = 30
```

## Sync Logic

| Action | Description |
| --- | --- |
| ADD | new contact |
| UPDATE | changed number or description |
| REMOVE | contact no longer exists in Exchange |

## Data Mapping

| Exchange | Swyx |
| --- | --- |
| DisplayName | Name |
| Company | Description |
| Email | Description |
| Phone | Number |
| MobilePhone | Number |

## Matching Behavior

- Existing Swyx entries are currently matched by `Name`
- Mobile numbers are created as separate entries with the suffix `(Mobil)`
- Only entries containing the configured marker are managed by the script

Because matching is name-based, ambiguous or duplicate display names may require a custom strategy in larger environments.

## Troubleshooting

### Unauthorized

Admin consent or Exchange role assignment may be missing.

### Certificate Not Found

Check available certificates:

```powershell
Get-ChildItem Cert:\LocalMachine\My
```

### Scheduled Task Does Not Run

Verify that the configured service account is correct and can access both Exchange and Swyx requirements.

### No Contacts Returned

Test Exchange access directly:

```powershell
Get-MailContact
Get-Contact
```

## Security Notes

- no password stored in the script
- certificate-based Exchange authentication
- scope can be limited to the minimum required permissions

## Possible Future Enhancements

- mail alerts on failures
- monitoring integration
- GUID-based matching instead of name-based matching
- performance optimization for large contact sets

## License

This project is licensed under the MIT License. See `LICENSE` for details.

## Author

Manuel J. Mahr

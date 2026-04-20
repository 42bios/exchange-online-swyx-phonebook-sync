# Exchange Online to Swyx Phonebook Sync

Exchange Online to Swyx Phonebook Sync is a small PowerShell helper that synchronizes Exchange Online mail contacts into the global Swyx phonebook.

It is designed as a practical automation aid for administrators, not as a full product or officially supported integration layer.

## What it does

- reads Exchange Online mail contacts
- normalizes phone numbers into a consistent E.164-style format
- creates new entries in the global Swyx phonebook
- updates existing managed entries when numbers or descriptions change
- removes managed Swyx entries that no longer exist in Exchange
- supports dry-run execution with `-WhatIf`
- writes daily rotating log files

## How it works

```text
Exchange Online (MailContacts)
            |
            v
PowerShell Script
            |
            v
  Swyx PowerShell (IpPbx)
            |
            v
   Global Swyx Phonebook
```

Only Swyx entries containing the configured marker are managed by the script. That keeps manually maintained entries outside the sync scope.

## Requirements

- Windows PowerShell
- Exchange Online access
- Entra ID app registration with certificate-based authentication
- Exchange application permission `Exchange.ManageAsApp`
- SwyxWare with available `IpPbx` cmdlets
- a dedicated Windows user that can run `Connect-IpPbx`

## Getting started

1. Create an Entra app registration for Exchange Online app-only authentication.
2. Upload a certificate to the app registration.
3. Grant `Exchange.ManageAsApp` and admin consent.
4. Ensure the app has the required Exchange permissions in your environment.
5. Ensure the service account can connect to Swyx interactively.
6. Adjust the configuration block in `Sync-ExchangeToSwyx.ps1`.
7. Run the script manually before scheduling it.

## Configuration

The main settings are:

- `$Marker`
- `$LogBasePath`
- `$LogRetentionDays`
- `$AddDefaultCountryCodeToLocalNumbers`
- `$DefaultCountryCode`

Example:

```powershell
$Marker = "[EXO-SYNC]"
$LogBasePath = "C:\System\Swyxware\Scripts\Logs\SwyxSync.log"
$LogRetentionDays = 2
$AddDefaultCountryCodeToLocalNumbers = $false
$DefaultCountryCode = "39"
```

## Usage

Run the sync manually:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1
```

Run a dry-run:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1 -WhatIf
```

## Task Scheduler

The repository includes an anonymized sample definition in `Exchange-Swyx-Phonebook-Sync.sample.xml`.

Typical setup:

- run whether user is logged on or not
- run with highest privileges
- trigger daily at `06:00`
- optionally repeat every `4 hours`

Action:

```powershell
-ExecutionPolicy Bypass -NoProfile -File "C:\Scripts\Sync-ExchangeToSwyx.ps1"
```

## Authentication notes

Example Exchange Online app-only login:

```powershell
Connect-ExchangeOnline `
  -AppId "<APP_ID>" `
  -CertificateThumbprint "<THUMBPRINT>" `
  -Organization "<tenant>.onmicrosoft.com"
```

Example Swyx test:

```powershell
Connect-IpPbx
Get-IpPbxPhonebookEntry -GlobalPhoneBook
```

## Matching behavior

- matching is currently based on `Name`
- mobile numbers are created as separate entries with the suffix `(Mobil)`
- only entries containing the configured marker are modified or removed

For larger environments with ambiguous display names, GUID-based matching may be a useful future improvement.

## Example number format

```text
+390000000001
+490000000001
```

## Repository contents

- `Sync-ExchangeToSwyx.ps1`
- `Exchange-Swyx-Phonebook-Sync.sample.xml`
- `LICENSE`

## Security notes

- no password stored in the script
- certificate-based Exchange authentication
- intended to run with the minimum required permissions

## License

This project is released under the MIT License. See `LICENSE`.

## Author

Manuel J. Mahr

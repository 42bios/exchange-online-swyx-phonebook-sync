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

## Usage

Run the sync manually:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1
```

Run a dry-run:

```powershell
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .\Sync-ExchangeToSwyx.ps1 -WhatIf
```

## Setup guide

The full setup and scheduling notes are in [`docs/SETUP.md`](docs/SETUP.md).

## Repository contents

- `Sync-ExchangeToSwyx.ps1`
- `Exchange-Swyx-Phonebook-Sync.sample.xml`
- `docs/SETUP.md`
- `LICENSE`

## Security notes

- no password stored in the script
- certificate-based Exchange authentication
- intended to run with the minimum required permissions

## License

This project is released under the MIT License. See `LICENSE`.

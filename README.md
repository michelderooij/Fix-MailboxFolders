# Fix-MailboxFolders

This script fixes mailbox folder names, for example after importing PST files from a different
regional setting. In such cases, you can end up having the the well-known folders in different 
language settings and possibly with number suffixes (e.g. Inbox1).	

### Prerequisites

* Exchange Server 2007 or later
* Exchange Managed API 1.2 or later

### Usage

Fix mailbox folders for a single user:
```
Fix-MailboxFolders.ps1 -Mailbox francis -Language en-US -FromLanguage nl-NL -Server l14ex1 -ScanNumericals -Impersonation
```

Fix mailbox folders for users using Mailbox and FromLanguage information contained in CSV file:
```
Import-Csv .\users.csv | .\Fix-MailboxFolders.ps1 -Language en-US -ScanNumericals -Impersonation -Verbose
```

### About

For more information on this script, as well as usage and examples, see
the related blog article on [EighTwOne](https://eightwone.com/2013/01/19/fixing-well-known-folders-troubles/).

## License

This project is licensed under the MIT License - see the LICENSE.md for details.

 
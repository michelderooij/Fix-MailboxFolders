<#
    .SYNOPSIS
    Fix-MailboxFolders
   
    Michel de Rooij
    michel@eightwone.com
	
    THIS CODE IS MADE AVAILABLE AS IS, WITHOUT WARRANTY OF ANY KIND. THE ENTIRE 
    RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.
	
    Version 1.6, August 16th, 2022
        
    .DESCRIPTION
    This script fixes mailbox folder names, for example after importing PST files from a different
    regional setting. In such cases, you can end up having the the well-known folders in different 
    language settings and possibly with number suffixes (e.g. Inbox1).
	
    .LINK
    http://eightwone.com
    
    .NOTES
    Microsoft Exchange Web Services (EWS) Managed API 1.2 or up is required.
    The current version of the EWS Managed API is available at http://go.microsoft.com/fwlink/?LinkId=255472

    Limitation: RSS Feeds folder not processed

    .CREDITS
    Thanks for Maarten Piederiet.

    Revision History
    --------------------------------------------------------------------------------
    1.1     Initial public release
    1.2     Fixed loop (resulting in call depth overflow) when Top of Information Store AKA 
            IPM_SUBTREE has been localized after using a non-English client, e.g. 
            "Bovenste map van gegevensarchief" (NL) or "Höchste Hierarchiestufe des IS" (DE).
    1.3     Adjustments for Exchange 2013 (Maarten Piederiet).
            Removed misleading warning message on matching source and target folder.
            Added code to handle PoSH differences in System.Collections.Generic.List creation.
            Lowered Exchange version requirements (Exchange 2007 SP1 and up).
            Enhanced detection / loading of EWS Managed API DLL (install or same folder).
            Added Swedish (Daniel Viklund).
    1.4     Added Norwegian (Magnus Jakobsen).
    1.41    Fixed DLL loading bug (Maarten Piederiet).
    1.42    Improved DLL loading routine.
    1.43    Added es-ES.
    1.44    Added nl-NL2 to accomodate for Dutch calendar variation (Agenda vs. Kalender)
            Fixed script aborting when RegionalConfiguration not set on mailbox
    1.45    Altered routines for EWS loading and E-mail address retrieval
            Changed cmdlet for EMS check, EMS is required for Regional Configuration
            Added Credentials parameter
            Office 365 compatible. Run script after connecting to remote EMS session.
            Added fr-CA, fr-FR
    1.46    Added ru-RU
    1.47    Added cs-CZ
    1.48    Added de-DE
    1.50    Renamed Mailbox parameter to Identity
            Added placeholders for alternative folder names
            Added da-dk, ja-jp, it-it, pt-pt, pt-br, no-no
            Added X-AnchorMailbox for Impersonation
            Removed unused connect function
    1.51    Fixed AutoDiscover lookup
    1.52    Fixed parameter descriptions and examples
    1.60    Added Modern Authentication support (for EWS)
            Added TrustAll switch
    
    .PARAMETER Identity
    Name of the Mailbox to fix

    .PARAMETER Language
    Language to configure. Default value is en-US. 
    
    .PARAMETER FromLanguage
    Scan for folders in this language, e.g. nl-NL. When omitted, will use currently configured mailbox language.
    
    .PARAMETER Server
    Exchange Client Access Server to use for Exchange Web Services. When ommited, script will attempt to use Autodiscover.
       
    .PARAMETER ScanNumericals
    When scanning for folders, also check for folders used due to conflicts, e.g. Inbox1 or Contacts1.

    .PARAMETER Credentials
    Specify credentials to use. When not specified, current credentials are used.
    Credentials can be set using $Credentials= Get-Credential
           
    .PARAMETER Impersonation
    When specified, uses impersonation for mailbox access, otherwise current logged on user is used.
    For details on how to configure impersonation access using RBAC, see knowledgebase article
    http://msdn.microsoft.com/en-us/library/exchange/bb204095(v=exchg.140).aspx
        
    .EXAMPLE
    Fix mailbox folders for a single user:
    Fix-MailboxFolders.ps1 -Identity francis -Language en-US -FromLanguage nl-NL -Server l14ex1 -ScanNumericals -Impersonation

    .EXAMPLE
    Fix mailbox folders for users using Mailbox and FromLanguage information contained in CSV file:
    Import-Csv .\users.csv | .\Fix-MailboxFolders.ps1 -Language en-US -ScanNumericals -Impersonation -Verbose
#>

#Requires -Version 3
[cmdletbinding(
    DefaultParameterSetName = 'DefaultAuth',
    SupportsShouldProcess= $true,
    ConfirmImpact= 'High'
)]
param(
    [parameter( Position= 0, Mandatory= $true, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'DefaultAuth')] 
    [parameter( Position= 0, Mandatory= $true, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Position= 0, Mandatory= $true, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Position= 0, Mandatory= $true, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Position= 0, Mandatory= $true, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'BasicAuth')] 
    [string[]]$Identity,
    [parameter( Position= 1, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'DefaultAuth')] 
    [parameter( Position= 1, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Position= 1, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Position= 1, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Position= 1, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'BasicAuth')] 
    [string]$Language= 'en-US',
    [parameter( Position= 2, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'DefaultAuth')] 
    [parameter( Position= 2, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Position= 2, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Position= 2, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Position= 2, Mandatory= $false, ValueFromPipelineByPropertyName= $true, ParameterSetName= 'BasicAuth')] 
    [string]$FromLanguage,
    [parameter( Mandatory= $false, ParameterSetName= 'DefaultAuth')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Mandatory= $false, ParameterSetName= 'BasicAuth')] 
    [string]$Server,
    [parameter( Mandatory= $false, ParameterSetName= 'DefaultAuth')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Mandatory= $false, ParameterSetName= 'BasicAuth')] 
    [switch]$Impersonation,
    [parameter( Mandatory= $false, ParameterSetName= 'DefaultAuth')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Mandatory= $false, ParameterSetName= 'BasicAuth')] 
    [switch]$ScanNumericals,
    [parameter( Mandatory= $true, ParameterSetName= 'DefaultAuth')] 
    [parameter( Mandatory= $true, ParameterSetName= 'DefaultAuthMailboxOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'DefaultAuthArchiveOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'DefaultAuthPublicFolders')] 
    [Switch]$UseDefaultCredentials,
    [parameter( Mandatory= $true, ParameterSetName= 'BasicAuth')] 
    [parameter( Mandatory= $true, ParameterSetName= 'BasicAuthMailboxOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'BasicAuthArchiveOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'BasicAuthPublicFolders')] 
    [System.Management.Automation.PsCredential]$Credentials,
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertSecretMailboxOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertSecretArchiveOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertSecretPublicFolders')] 
    [System.Security.SecureString]$Secret,
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertThumbMailboxOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertThumbArchiveOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertThumbPublicFolders')] 
    [String]$CertificateThumbprint,
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertFileMailboxOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertFileArchiveOnly')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertFilePublicFolders')] 
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf})]
    [String]$CertificateFile,
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFileMailboxOnly')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFileArchiveOnly')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFilePublicFolders')] 
    [System.Security.SecureString]$CertificatePassword,
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertSecret')] 
    [string]$TenantId,
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $true, ParameterSetName= 'OAuthCertSecret')] 
    [string]$ClientId,
    [parameter( Mandatory= $false, ParameterSetName= 'DefaultAuth')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertThumb')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertFile')] 
    [parameter( Mandatory= $false, ParameterSetName= 'OAuthCertSecret')] 
    [parameter( Mandatory= $false, ParameterSetName= 'BasicAuth')] 
    [switch]$TrustAll
)

begin {

    # Well known folders
    # http://msdn.microsoft.com/en-us/library/microsoft.exchange.webservices.data.wellknownfoldername(v=EXCHG.80).aspx
    $WellKnownFolders= @("Calendar", "Contacts", "DeletedItems", "Drafts", "Inbox", "Notes", "Outbox", "SentItems", "Tasks", "JunkEmail", "Journal")

    # For each possible regional setting, specify the folder for each WellKnownFolder, e.g. "SentItems"="Sent Items" means
    # that WellKnownFolder "SentItems" corresponds with a folder named "Sent Items" for a specific regional setting. Special
    # settings are DateFormat and TimeFormat for Date and Time formatting respectively.
    $LanguageInfo= @{
        "en-US"= @{
            "Inbox"="Inbox"; 
            "SentItems"="Sent Items"; 
            "Notes"="Notes"; 
            "Drafts"="Drafts"; 
            "DeletedItems"="Deleted Items"; 
            "Outbox"="Outbox"; 
            "Contacts"="Contacts"; 
            "Calendar"="Calendar"; 
            "Tasks"="Tasks"; 
            "JunkEmail"="Junk E-mail";
            "JunkEmail2013"="Junk Email";
            "Journal"="Journal";
            "DateFormat"="M/d/yyyy";
            "TimeFormat"="h:mm tt"
        };
        "nl-NL"= @{
            "Inbox"="Postvak IN"; 
            "SentItems"="Verzonden items"; 
            "Notes"="Notities"; 
            "Drafts"="Concepten"; 
            "DeletedItems"="Verwijderde items"; 
            "Outbox"="Postvak UIT"; 
            "Contacts"="Contactpersonen"; 
            "Calendar"="Agenda"; 
            "Tasks"="Taken"; 
            "JunkEmail"="Ongewenste e-mail";
            "Journal"="Journaal";
            "DateFormat"="dd-MM-yy";
            "TimeFormat"="HH:mm";
        };
        "sv-SE"= @{
            "Inbox"="Inkorgen"; 
            "SentItems"="Skickat"; 
            "Notes"="Anteckningar"; 
            "Drafts"="Utkast"; 
            "DeletedItems"="Borttaget"; 
            "Outbox"="Utkorgen"; 
            "Contacts"="Kontakter"; 
            "Calendar"="Kalender"; 
            "Tasks"="Uppgifter"; 
            "JunkEmail"="Skräppost";
            "Journal"="Journal";
            "DateFormat"="yyyy-MM-dd";
            "TimeFormat"="HH:mm";
        };
        "es-ES"= @{
            "Inbox"="Bandeja de entrada"; 
            "SentItems"="Elementos enviados"; 
            "Notes"="Notas"; 
            "Drafts"="Borradores"; 
            "DeletedItems"="Elementos eliminados"; 
            "Outbox"="Bandeja de salida"; 
            "Contacts"="Contactos"; 
            "Calendar"="Calendario"; 
            "Tasks"="Tareas"; 
            "JunkEmail"="Correo no deseado";
            "Journal"="Diario";
            "DateFormat"="dd/MM/yyyy";
            "TimeFormat"="H:mm";
        };
        "nl-NL2"= @{
            "Inbox"="Postvak IN"; 
            "SentItems"="Verzonden items"; 
            "Notes"="Notities"; 
            "Drafts"="Concepten"; 
            "DeletedItems"="Verwijderde items"; 
            "Outbox"="Postvak UIT"; 
            "Contacts"="Contactpersonen"; 
            "Calendar"="Kalender"; 
            "Tasks"="Taken"; 
            "JunkEmail"="Ongewenste e-mail";
            "Journal"="Journaal";
            "DateFormat"="dd-MM-yy";
            "TimeFormat"="HH:mm";
        };
        "fr-CA"= @{
            "Inbox"="Boîte de réception"; 
            "SentItems"="Éléments envoyés"; 
            "Notes"="Notes"; 
            "Drafts"="Brouillons"; 
            "DeletedItems"="Éléments supprimés"; 
            "Outbox"="Boîte d'envoi"; 
            "Contacts"="Contacts"; 
            "Calendar"="Calendrier"; 
            "Tasks"="Tâches"; 
            "JunkEmail"="Courrier indésirable";
            "Journal"="Journal";
            "DateFormat"="yyyy-MM-dd";
            "TimeFormat"="HH:mm";
        };
        "fr-FR"= @{
            "Inbox"="Boîte de réception"; 
            "SentItems"="Éléments envoyés"; 
            "Notes"="Notes"; 
            "Drafts"="Brouillons"; 
            "DeletedItems"="Éléments supprimés"; 
            "Outbox"="Boîte d'envoi"; 
            "Contacts"="Contacts"; 
            "Calendar"="Calendrier"; 
            "Tasks"="Tâches"; 
            "JunkEmail"="Courrier indésirable";
            "Journal"="Journal";
            "DateFormat"="dd/MM/yyyy";
            "TimeFormat"="HH:mm";
        };
        "ru-RU"= @{
            "Inbox"="Входящие";
            "SentItems"="Отправленные";
            "Notes"="Заметки";
            "Drafts"="Черновики";
            "DeletedItems"="Удаленные";
            "Outbox"="Исходящие";
            "Contacts"="Контакты";
            "Calendar"="Календарь";
            "Tasks"="Задачи";
            "JunkEmail"="Нежелательная почта";
            "Journal"="Дневник";
            "DateFormat"="dd.MM.yyyy";
            "TimeFormat"="H:mm";
        };
        "cs-CZ"= @{ 
            "Inbox"="Doručená pošta"; 
            "SentItems"="Odeslaná pošta"; 
            "Notes"="Poznámky"; 
            "Drafts"="Koncepty"; 
            "DeletedItems"="Odstraněná pošta"; 
            "Outbox"="Odchozí pošta"; 
            "Contacts"="Kontakty"; 
            "Calendar"="Kalendář"; 
            "Tasks"="Úlohy"; 
            "JunkEmail"="Nevyžádaná pošta"; 
            "Journal"="Deník"; 
            "DateFormat"="d. M. yyyy"; 
            "TimeFormat"="H:mm" ;         
        };
        "de-DE"= @{
            "Inbox"="Posteingang"; 
            "SentItems"="Gesendete Elemente"; 
            "SentItems2007"="Gesendete Objekte"; 
            "Notes"="Notizen"; 
            "Drafts"="Entwürfe"; 
            "DeletedItems"="Gelöschte Elemente"; 
            "DeletedItems2007"="Gelöschte Objekte"; 
            "Outbox"="Postausgang"; 
            "Contacts"="Kontakte"; 
            "Calendar"="Kalender"; 
            "Tasks"="Aufgaben"; 
            "JunkEmail"="Junk-E-mail";
            "Journal"="Journal";
            "DateFormat"="dd.MM.yyyy";
            "TimeFormat"="HH:mm"
        };
        "da-dk"= @{
            "Inbox"="Indbakke"; 
            "SentItems"="Sendt post"; 
            "Notes"="Noter"; 
            "Drafts"="Kladder"; 
            "DeletedItems"="Slettet post"; 
            "Outbox"="Udbakke"; 
            "Contacts"="Kontakter"; 
            "Calendar"="Kalender"; 
            "Tasks"="Opgaver"; 
            "JunkEmail"="Junk-E-mail";
            "Journal"="Journal";
            "DateFormat"="dd.MM.yyyy";
            "TimeFormat"="HH:mm"
        };
        "ja-jp"= @{
            "Inbox"="受信トレイ"; 
            "SentItems"="送信済みアイテム"; 
            "Notes"="メモ"; 
            "Drafts"="下書き"; 
            "DeletedItems"="削除済みアイテム"; 
            "Outbox"="送信トレイ"; 
            "Contacts"="連絡先"; 
            "Calendar"="カレンダー"; 
            "Tasks"="タスク"; 
            "JunkEmail"="迷惑メール";
            "Journal"="履歴";
            "DateFormat"="yyyy/MM/dd";
            "TimeFormat"="HH:mm"
        };
        "it-it"= @{
            "Inbox"="Posta in arrivo"; 
            "SentItems"="Posta inviata"; 
            "Notes"="Note"; 
            "Drafts"="Bozze"; 
            "DeletedItems"="Posta eliminata"; 
            "Outbox"="Posta in uscita"; 
            "Contacts"="Contatti"; 
            "Calendar"="Calendario"; 
            "Tasks"="Attività"; 
            "JunkEmail"="Posta indesiderata";
            "Journal"="Diario";
            "DateFormat"="dd/MM/yyyy";
            "TimeFormat"="HH:mm"
        };
        "pt-br"= @{
            "Inbox"="A receber"; 
            "SentItems"="Itens enviados"; 
            "Notes"="Notas"; 
            "Drafts"="Rascunhos"; 
            "DeletedItems"="Itens eliminados"; 
            "Outbox"="A enviar"; 
            "Contacts"="Contactos"; 
            "Calendar"="Calendário"; 
            "Tasks"="Tarefas"; 
            "JunkEmail"="Lixo eletrônico";
            "Journal"="Diário";
            "DateFormat"="dd/MM/yyyy";
            "TimeFormat"="HH:mm"
        };
        "pt-pt"= @{
            "Inbox"="Caixa de entrada"; 
            "SentItems"="Itens enviados"; 
            "Notes"="Anotações"; 
            "Drafts"="Rascunhos"; 
            "DeletedItems"="Itens excluídos"; 
            "Outbox"="Caixa de saída"; 
            "Contacts"="Contactos"; 
            "Calendar"="Calendário"; 
            "Tasks"="Tarefas"; 
            "JunkEmail"="Lixo eletrônico";
            "Journal"="Diário";
            "DateFormat"="dd/MM/yyyy";
            "TimeFormat"="HH:mm"
        };
        "no-no"= @{
            "Inbox"="Innboks"; 
            "SentItems"="Sendte elementer"; 
            "Notes"="Notater"; 
            "Drafts"="Kladd"; 
            "DeletedItems"="Slettede elementer"; 
            "Outbox"="Utboks"; 
            "Contacts"="Kontakter"; 
            "Calendar"="Kalender"; 
            "Tasks"="Oppgaver"; 
            "JunkEmail"="Søppelpost";
            "Journal"="Logg";
            "DateFormat"="dd.MM.yyyy";
            "TimeFormat"="HH:mm"
        };
    }
    
    # Process items in these batch sizes
    $MaxBatchSize= 1000

    # Max. number of folders to return after search at each folder level
    $MaxNumFolders= 99999
    
    # Maximum no. of conflict folders to check, e.g. Inbox1..Inbox99
    $NumericalMax= 1

    # Errors
    $ERR_EXCHANGESNAPINMISSING               = 1
    $ERR_MAILBOXNOTFOUND                     = 3
    $ERR_AUTODISCOVERFAILED                  = 4
    $ERR_CANTDETERMINESOURCELANGUAGESETTINGS = 5
    $ERR_LANGUAGECONFIGURATIONISSUE          = 7
    $ERR_CANTACCESSMAILBOXSTORE              = 8
    $ERR_CANTACCESSFOLDER                    = 9
    $ERR_DLLNOTFOUND                         = 1000
    $ERR_DLLLOADING                          = 1001
    $ERR_MAILBOXNOTFOUND                     = 1002
    $ERR_AUTODISCOVERFAILED                  = 1003
    $ERR_CANTACCESSMAILBOXSTORE              = 1004
    $ERR_INVALIDCREDENTIALS                  = 1007
    $ERR_PROBLEMIMPORTINGCERT                = 1008
    $ERR_CERTNOTFOUND                        = 1009

    Function Get-EmailAddress {
        param(
            [string]$Identity
        )
        $address= [regex]::Match([string]$Identity, ".*@.*\..*", "IgnoreCase")
        if ( $address.Success ) {
            return $address.value.ToString()
        }
        Else {
            # Use local AD to look up e-mail address using $Identity as SamAccountName
            $ADSearch= New-Object DirectoryServices.DirectorySearcher( [ADSI]"")
            $ADSearch.Filter= "(|(cn=$Identity)(samAccountName=$Identity)(mail=$Identity))"
            $Result= $ADSearch.FindOne()
            If ( $Result) {
                $objUser= $Result.getDirectoryEntry()
                return $objUser.mail.toString()
            }
            else {
                return $null
            }
        }
    }
    
    Function get-LanguageConfiguration( $Language) {
        $LanguageConfiguration= $null
        ForEach( $Set in $LanguageInfo.GetEnumerator()) {
            If($Set.Name -eq $Language) {
                $LanguageConfiguration= $LanguageInfo[ $Language]
            }
        }
        return $LanguageConfiguration
    }

    Function Import-ModuleDLL {
        param(
            [string]$Name,
            [string]$FileName,
            [string]$Package
        )

        $AbsoluteFileName= Join-Path -Path $PSScriptRoot -ChildPath $FileName
        If ( Test-Path $AbsoluteFileName) {
            # OK
        }
        Else {
            If( $Package) {
                If( Get-Command -Name Get-Package -ErrorAction SilentlyContinue) {
                    If( Get-Package -Name $Package -ErrorAction SilentlyContinue) {
                        $AbsoluteFileName= (Get-ChildItem -ErrorAction SilentlyContinue -Path (Split-Path -Parent (get-Package -Name $Package | Sort-Object -Property Version -Descending | Select-Object -First 1).Source) -Filter $FileName -Recurse).FullName
                    }
                }
            }
        }

        If( $absoluteFileName) {
            $ModLoaded= Get-Module -Name $Name -ErrorAction SilentlyContinue
            If( $ModLoaded) {
                Write-Verbose ('Module {0} v{1} already loaded' -f $ModLoaded.Name, $ModLoaded.Version)
            }
            Else {
                Write-Verbose ('Loading module {0}' -f $absoluteFileName)
                try {
                    Import-Module -Name $absoluteFileName -Global -Force
                    Start-Sleep 1
                }
                catch {
                    Write-Error ('Problem loading module {0}: {1}' -f $Name, $error[0])
                    Exit $ERR_DLLLOADING
                }
                $ModLoaded= Get-Module -Name $Name -ErrorAction SilentlyContinue
                If( $ModLoaded) {
                    Write-Verbose ('Module {0} v{1} loaded' -f $ModLoaded.Name, $ModLoaded.Version)
                }
                If(!( Get-Module -Name $Name -ErrorAction SilentlyContinue)) {
                    Write-Error ('Problem loading module {0}: {1}' -f $Name, $_.Exception.Message)
                    Exit $ERR_DLLLOADING
                }
            }
        }
        Else {
            Write-Verbose ('Required module {0} could not be located' -f $FileName)
            Exit $ERR_DLLNOTFOUND
        }
    }

    Function Set-SSLVerification {
        param(
            [switch]$Enable,
            [switch]$Disable
        )

        Add-Type -TypeDefinition  @"
            using System.Net.Security;
            using System.Security.Cryptography.X509Certificates;
            public static class TrustEverything
            {
                private static bool ValidationCallback(object sender, X509Certificate certificate, X509Chain chain,
                    SslPolicyErrors sslPolicyErrors) { return true; }
                public static void SetCallback() { System.Net.ServicePointManager.ServerCertificateValidationCallback= ValidationCallback; }
                public static void UnsetCallback() { System.Net.ServicePointManager.ServerCertificateValidationCallback= null; }
        }
"@
        If($Enable) {
            Write-Verbose ('Enabling SSL certificate verification')
            [TrustEverything]::UnsetCallback()
        }
        Else {
            Write-Verbose ('Disabling SSL certificate verification')
            [TrustEverything]::SetCallback()
        }
    }
    
    Function getFolderPath( $Folder) {
        If( $Folder.ParentFolderId) {
            $ParentFolder= [Microsoft.Exchange.WebServices.Data.Folder]::Bind( $EwsService, $Folder.ParentFolderId)
            # Top of Information Store reached?
            If( $ParentFolder.Id.UniqueId -ne $ParentFolder.ParentFolderId.UniqueId) {
                $FolderPath= (getFolderPath $ParentFolder)+ "\"+ [String]$Folder.DisplayName
            }
            Else {
                $FolderPath= [String]$Folder.DisplayName
            }
        }
        Else {
            $FolderPath= ""
        }
        return $FolderPath
    }

    Function folderExists( $FolderName, $Folder) {
        Write-Verbose ("Checking if folder [$FolderName] exists in "+ (getFolderPath $Folder))
        $FolderView= New-Object Microsoft.Exchange.WebServices.Data.FolderView( 1)
        $SearchFilter= New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+isEqualTo( [Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName, "$FolderName")
        $SearchResults= $EwsService.FindFolders( $Folder.Id, $SearchFilter, $FolderView)
        Return ($SearchResults.TotalCount -gt 0)
    }
    
    Function getFolderFromName( $FolderName, $SearchFolder) {
        Write-Verbose "Accessing folder [$FolderName] in $($SearchFolder.DisplayName)"
        $SourceFolderView= New-Object Microsoft.Exchange.WebServices.Data.FolderView( 1)
        $SearchFilter= New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+isEqualTo( [Microsoft.Exchange.WebServices.Data.FolderSchema]::DisplayName, $FolderName)
        $SearchResults= $EwsService.FindFolders( $SearchFolder.Id, $SearchFilter, $SourceFolderView)
        If( $SearchResults.TotalCount -gt 0) {
            # Note that if multiple folders are found, only the last one will be returned
            ForEach( $Result in $SearchResults.Folders) {
                $Folder= $Result
            }
        }
        Else {
            $Folder= $null
        }
        return $Folder
    }
    
    Function Process-Folder( $SourceFolder, $TargetFolder, $RootFolder, $Depth) {
    
        $Result= $true
        If( $SourceFolder) {
            $SourcePath= getFolderPath $SourceFolder
            $TargetPath= getFolderPath $TargetFolder
            # Do we manually need to remove the current SourceFolder after processing
            # will be skipped when errors are encountered processing (sub)folder(s) or items.
            $Delete= $true

            Write-Verbose "Processing folder $SourcePath (Depth:$Depth)"
            If( $SourceFolder.Id -ne $TargetFolder.Id) {
            
                # Process folders
                $SearchResults= $SourceFolder.FindFolders( $MaxNumFolders)
                Write-Verbose "Found $($SearchResults.TotalCount) subfolders"
                ForEach( $Folder in $SearchResults) {

                    Write-Verbose "Processing subfolder $($Folder.DisplayName) in $SourcePath"

                    If( folderExists ($Folder.DisplayName) $TargetFolder) {
            
                        # Process subfolders
                        $matchingTargetFolder= getFolderFromName ($Folder.DisplayName) $TargetFolder
                        If( !( Process-Folder $Folder $matchingTargetFolder $SourceFolder ($Depth+1))){
                            $Delete= $false
                        }
                    }
                    Else {

                        # Target folder doesn't exist, so we can use Move method; no need to
                        # manually remove folder (and if move fails we'd like to keep original folder)
                        $Delete= $false

                        try{
                            Write-Verbose "Moving folder [$($Folder.DisplayName)] in [$SourcePath] to $TargetPath"
                            $null= $Folder.Move( $TargetFolder.Id)
                        }
                        catch{
                            Write-Warning "Problem moving folder: $($error[0])"
                        }
                    }
                }
                # Process Items
                If( ! (Process-Items $SourceFolder $TargetFolder)){
                    $Delete= $false
                    $Result= $false
                }
            
                If( $Delete){
                    try{
                        Write-Verbose "Removing folder $SourcePath"
                        $SourceFolder.Delete( [Microsoft.Exchange.WebServices.Data.DeleteMode]::SoftDelete)
                    }
                    catch{
                        Write-Error "Problem removing folder or already removed: $($error[0])"
                        $Result= $false
                    }
                }
                Else {
                    Write-Warning "Not removing folders since problems were encountered"
                }
            }
            Else {
                # Skip when source matches target folder
            }
        }
        return $Result
    }
    
    Function Process-Items( $SourceFolder, $TargetFolder) {

        Write-Verbose "Processing items in folder $($SourceFolder.DisplayName)"
        $ItemView= New-Object Microsoft.Exchange.WebServices.Data.ItemView( $MaxBatchSize)
        $SearchResults= $null
        $Result= $true

        Do {
            $type=("System.Collections.Generic.List"+'`'+"1")-as"Type"
            $type = $type.MakeGenericType(“Microsoft.Exchange.WebServices.Data.ItemId” -as “Type”)
            $ItemIds = [Activator]::CreateInstance($type)

            $SearchResults= $EwsService.FindItems( $SourceFolder.Id, "", $ItemView)
            Write-Verbose ("Found $($SearchResults.TotalCount) items in ["+ (getFolderPath $SourceFolder)+ "]")

            If( $SearchResults.TotalCount -gt 0) {

                Write-Verbose ("Moving items to destination folder ["+ (getFolderPath $TargetFolder)+ "]")

                # We'll use the MoveItems method (faster/more efficient) which will take 
                # a set of item ID's which we need to collect first 
                ForEach( $Item in $SearchResults.Items) {
                    $ItemIds.Add( $Item.Id)
                }
                try {
                    [void]$EwsService.MoveItems( $ItemIds, $TargetFolder.Id)
                }
                catch{ 
                    Write-Error "Problem moving items: $($error[0])"
                    $Result= $false
                }
                $ItemView.Offset+= $SearchResults.Items.Count
            }
        } While( $SearchResults.MoreAvailable)

        return $Result
    }

    Import-ModuleDLL -Name 'Microsoft.Exchange.WebServices' -FileName 'Microsoft.Exchange.WebServices.dll' -Package 'Exchange.WebServices.Managed.Api'
    Import-ModuleDLL -Name 'Microsoft.Identity.Client' -FileName 'Microsoft.Identity.Client.dll' -Package 'Microsoft.Identity.Client'

    If ( ! ( Get-Command Get-MailboxRegionalConfiguration -ErrorAction SilentlyContinue )) {
        Write-Error "Exchange Management Shell not loaded"
        Exit $ERR_EXCHANGESNAPINMISSING
    }

    $ExchangeVersion= [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010_SP1
    $EwsService= New-Object Microsoft.Exchange.WebServices.Data.ExchangeService( $ExchangeVersion)

    If( $Credentials -or $UseDefaultCredentials) {
        If( $Credentials) {
            try {
                Write-Verbose ('Using credentials {0}' -f $Credentials.UserName)
                $EwsService.Credentials= [System.Net.NetworkCredential]::new( $Credentials.UserName, [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR( $Credentials.Password )))
            }
            catch {
                Write-Error ('Invalid credentials provided: {0}' -f $_.Exception.Message)
                Exit $ERR_INVALIDCREDENTIALS
            }
        }
        Else {
            Write-Verbose ('Using Default Credentials')
            $EwsService.UseDefaultCredentials = $true
        }
    }
    Else {

        # Use OAuth (and impersonation/X-AnchorMailbox always set)
        $Impersonation= $true

        If( $CertificateThumbprint -or $CertificateFile) {
            If( $CertificateFile) {
                
                # Use certificate from file using absolute path to authenticate
                $CertificateFile= (Resolve-Path -Path $CertificateFile).Path
                
                Try {
                    If( $CertificatePassword) {
                        $X509Certificate2= [System.Security.Cryptography.X509Certificates.X509Certificate2]::new( $CertificateFile, [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR( $CertificatePassword)))
                    }
                    Else {
                        $X509Certificate2= [System.Security.Cryptography.X509Certificates.X509Certificate2]::new( $CertificateFile)
                    }
                }
                Catch {
                    Write-Error ('Problem importing PFX: {0}' -f $_.Exception.Message)
                    Exit $ERR_PROBLEMIMPORTINGCERT
                }
            }
            Else {
                # Use provided certificateThumbprint to retrieve certificate from My store, and authenticate with that
                $CertStore= [System.Security.Cryptography.X509Certificates.X509Store]::new( [Security.Cryptography.X509Certificates.StoreName]::My, [Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
                $CertStore.Open( [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly )
                $X509Certificate2= $CertStore.Certificates.Find( [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $CertificateThumbprint, $False) | Select-Object -First 1
                If(!( $X509Certificate2)) {
                    Write-Error ('Problem locating certificate in My store: {0}' -f $error[0])
                    Exit $ERR_CERTNOTFOUND
                }
            }
            Write-Verbose ('Will use certificate {0}, issued by {1} and expiring {2}' -f $X509Certificate2.Thumbprint, $X509Certificate2.Issuer, $X509Certificate2.NotAfter)
            $App= [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::Create( $ClientId).WithCertificate( $X509Certificate2).withTenantId( $TenantId).Build()
               
        }
        Else {
            # Use provided secret to authenticate
            Write-Verbose ('Will use provided secret to authenticate')
            $PlainSecret= [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR( $Secret))
            $App= [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::Create( $ClientId).WithClientSecret( $PlainSecret).withTenantId( $TenantId).Build()
        }
        $Scopes= New-Object System.Collections.Generic.List[string]
        $Scopes.Add( 'https://outlook.office365.com/.default')
        Try {
            $Response=$App.AcquireTokenForClient( $Scopes).executeAsync()
            $Token= $Response.Result
            $EwsService.Credentials= [Microsoft.Exchange.WebServices.Data.OAuthCredentials]$Token.AccessToken
            Write-Verbose ('Authentication token acquired')
        }
        Catch {
            Write-Error ('Problem acquiring token: {0}' -f $error[0])
            Exit $ERR_INVALIDCREDENTIALS
        }
    }

    If( $TrustAll) {
        Set-SSLVerification -Disable
    }
}

process {

    ForEach( $CurrentIdentity in $Identity) {
 
        Write-Host "Processing mailbox $CurrentIdentity"

        $EmailAddress= get-EmailAddress -Identity $CurrentIdentity
        If ( !$EmailAddress) {
            Write-Error ('Specified mailbox {0} not found' -f $EmailAddress)
            Exit $ERR_MAILBOXNOTFOUND
        }

        If( $Impersonation) {
            Write-Verbose "Using $EmailAddress for impersonation"
            $EwsService.ImpersonatedUserId= [Microsoft.Exchange.WebServices.Data.ImpersonatedUserId]::new( [Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress, $EmailAddress)
            $EwsService.HttpHeaders.Clear()
            $EwsService.HttpHeaders.Add( 'X-AnchorMailbox', $EmailAddress)
        }
    
        If ($Server) {
            $EwsUrl= 'https://{0}/EWS/Exchange.asmx' -f $Server
            Write-Verbose ('Using Exchange Web Services URL {0}' -f $EwsUrl)
            $EwsService.Url= "$EwsUrl"
        }
        Else {
            Write-Verbose "Looking up EWS URL using Autodiscover for $EmailAddress"
            try {
                # Set script to terminate on all errors (autodiscover failure isn't) to make try/catch work
                $ErrorActionPreference= 'Stop'
                #$EwsService.TraceEnabled = $true
                $EwsService.autodiscoverUrl( $EmailAddress, {$true})
            }
            catch {
                Write-Error ('Autodiscover failed: {0}' -f $error[0])
                Exit $ERR_AUTODISCOVERFAILED
            }
            $ErrorActionPreference= 'Continue'
            Write-Verbose ('Using EWS on CAS {0}' -f $EwsService.Url)
        } 
            
        If ($FromLanguage) {
            Write-Verbose "From language selected is $FromLanguage"
        }
        Else {
            If(( Get-MailboxRegionalConfiguration -Identity $CurrentIdentity).Language) {
                $FromLanguage= (Get-MailboxRegionalConfiguration -Identity $CurrentIdentity).Language.Name.ToString()
            }
            Else {
                $FromLanguage= 'en-US'
            }
            Write-Verbose ('From language not specified, using currently configured language {0}' -f $FromLanguage)
        }

        If( $LanguageInfo.ContainsKey($FromLanguage) ) {
            $LanguageConfiguration= get-LanguageConfiguration $FromLanguage
        } 
        Else {
            Write-Error "Can't determine source language settings"
            Exit $ERR_CANTDETERMINESOURCELANGUAGESETTINGS
        }

        If( $LanguageInfo.ContainsKey($Language) ) {
            $TargetLanguageConfiguration= get-LanguageConfiguration $Language
        } 
        Else {
            Write-Warning "Can't determine destination language settings, using en-US"
            $FromLanguage= 'en-US'
        }

        If( $FromLanguage -ne $Language) {
            $DateFormat= $TargetLanguageConfiguration.Get_Item( "DateFormat")
            $TimeFormat= $TargetLanguageConfiguration.Get_Item( "TimeFormat")
            Write-Verbose "Setting mailbox language to $Language, DateFormat=$DateFormat, TimeFormat=$TimeFormat"
            $ErrorActionPreference= "Stop"
            try{

                Set-MailboxRegionalConfiguration -Identity $CurrentIdentity -Language $Language -LocalizeDefaultFolderName:$true -DateFormat $DateFormat -TimeFormat $TimeFormat
            }
            catch{
                Write-Error "Bad language configuration information $($error[0])"
                Exit $ERR_LANGUAGECONFIGURATIONISSUE
            }
            $ErrorActionPreference= "Continue"
        }
        Else {
            Write-Verbose "Mailbox language already set to $Language"
        }

        try {
            $RootFolderId= New-Object Microsoft.Exchange.WebServices.Data.FolderId( [Microsoft.Exchange.WebServices.Data.WellknownFolderName]::MsgFolderRoot, $EmailAddress)
            $RootFolder= [Microsoft.Exchange.WebServices.Data.Folder]::Bind( $EwsService, $RootFolderId)
        }
        catch {
            Write-Error "Can't access mailbox information store ($($error[0]))"
            Exit $ERR_CANTACCESSMAILBOXSTORE
        }

        ForEach( $Folder in $WellKnownFolders) {
            Write-Verbose ("Target folder is ["+ $TargetLanguageConfiguration.Get_Item( $Folder )+ "]")
            try {
                $TargetFolderId= New-Object Microsoft.Exchange.WebServices.Data.FolderId( [Microsoft.Exchange.WebServices.Data.WellknownFolderName]::($Folder), $EmailAddress)
                $TargetFolder= [Microsoft.Exchange.WebServices.Data.Folder]::Bind( $EwsService, $TargetFolderId)
            }
            catch {
                Write-Error "Unable to access folder ($($error[0]))"
                Exit $ERR_CANTACCESSFOLDER
            }
            If( $TargetFolder) {            
                $SourceFolderName= $LanguageConfiguration.Get_Item($Folder)
                # First entry is the bare folder name, e.g. Inbox
                $SourceFolderList= @( $SourceFolderName)
                # When specified, add any numericals, e.g. Inbox1
                If ($ScanNumericals) {
                    1.. $NumericalMax | ForEach-Object { $SourceFolderList+= "$SourceFolderName$_" }
                }
            
                ForEach( $Folder in $SourceFolderList) {
                    $SourceFolder= getFolderFromName $Folder $RootFolder
                    If( $SourceFolder) {
                        If (Process-Folder $SourceFolder $TargetFolder $RootFolder 1){
                            Write-Host "Successfully processed $Folder"
                        }
                        Else {
                            Write-Warning "Problem processing $Folder"
                        }
                    }
                    Else {
                        Write-Verbose "Folder [$Folder] not found"
                    }
                }           
          }
        }
    }   
}   
End {
    If( $TrustAll) {
        Set-SSLVerification -Enable
    }
}
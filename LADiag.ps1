# Function to perform Test-Connection
function Test-ConnectionResult {
    param (
        [string]$Endpoint
    )
    $result = "<span class='alert2 warning-alert'>tcpping $Endpoint</span><hr>"
   # cmd /c openssl s_client -connect $Endpoint | Tee-Object -Variable $result
    return $result
}

function Get-CertificateSubject {
    param (
        [string]$Endpoint
    )
    
    try {
        # Remove protocol if it exists
        $Endpoint = $Endpoint -replace "^https?://", ""
        # Remove path and keep only host
        $Endpoint = ($Endpoint -split "/")[0]
         # Remove port number if any
        $Endpoint = ($Endpoint -split ":")[0]
         $Endpoint
        # Create connection to get the certificate
        $tcpClient = New-Object System.Net.Sockets.TcpClient($Endpoint, 443)
        $tcpStream = $tcpClient.GetStream()
        
        # Create SSL stream
        $sslStream = New-Object System.Net.Security.SslStream($tcpStream, $false)
        $sslStream.AuthenticateAsClient($Endpoint)
        
        # Get certificate details
        $cert = $sslStream.RemoteCertificate
        $subject = $cert.Subject
        
        # Clean up resources
        $sslStream.Close()
        $tcpStream.Close()
        $tcpClient.Close()
        
        return $subject
    }
    catch {
        return "Error getting certificate: $($_.Exception.Message)"
    }
}

function NameresolverResult {
    param (
        [string]$Endpoint
    )

    try {
        $nslookup = Nameresolver $Endpoint 2>$null
        $output = $nslookup -replace "  ", "<br>" -replace "`t", "<br>&nbsp;&nbsp;&nbsp;&nbsp;"
    }
    catch {
        $output = "Failed"
    }

    return [PSCustomObject]@{
        Endpoint = $Endpoint
        Output   = $output
    }
}
function listShare {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$StorageAccountName,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$StorageAccountKey
    )
    
    $Date = (Get-Date).ToUniversalTime()
    $Datestr = $Date.ToString("R")
    $Url = "https://$StorageAccountName.file.core.windows.net/?comp=list"
    $Version = "2017-04-17"

    $StrToSign = "GET`n`n`n`n`n`n`n`n`n`n`n`nx-ms-date:$Datestr"
    $StrToSign = $StrToSign + "`nx-ms-version:$Version"
    $StrToSign = $StrToSign + "`n/${StorageAccountName}/${ShareName}"
    $StrToSign = $StrToSign + "`ncomp:list"
 
    [byte[]]$DataBytes = ([System.Text.Encoding]::UTF8).GetBytes($StrToSign)
    $Hmacsha256 = New-Object System.Security.Cryptography.HMACSHA256
    $Hmacsha256.Key = [Convert]::FromBase64String($StorageAccountKey)
    $Sig = [Convert]::ToBase64String($Hmacsha256.ComputeHash($DataBytes))
    $AuthHdr = "SharedKey ${StorageAccountName}:$Sig"
  
    $RequestHeader = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $RequestHeader.Add("Authorization", $AuthHdr)
    $RequestHeader.Add("x-ms-date", $Datestr)
    $RequestHeader.Add("x-ms-version", $Version)
    
    try {
        $Response = (Invoke-RestMethod -Uri $Url -Method get -Headers $RequestHeader)
    }
    catch {
        $resultStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($resultStream)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $Response = $reader.ReadToEnd()
    }

    return $Response
}

function Get-EndpointsHtmlTable {
    param (
        [Parameter(Mandatory = $true)]
        [Array]$Endpoints
    )

    $htmlTable = @"
<h2>Endpoint Certificate Verification</h2>
<table>
    <tr>
        <th>Endpoint Type</th>
      
        <th>Certificate and DNS </th>
        <th>Certificate Match</th>
    </tr>
"@

    foreach ($endpoint in $Endpoints) {
        $verified = if ($endpoint.Certificate -match $endpoint.Type) {
            "Y"
        } else {
            "N"
        }
        
        $htmlTable += @"
    <tr>
        <td>$($endpoint.Type)</td>
      
        <td><pre>$($endpoint.Certificate)</pre><pre>$($endpoint.DNS.Output)</pre></td>
        <td>$verified</td>
    </tr>
"@
    }

    $htmlTable += "</table>"
    return $htmlTable
}

$WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = [Environment]::GetEnvironmentVariable('XWEBSITE_CONTENTAZUREFILECONNECTIONSTRING')
$WEBSITE_CONTENTSHARE = [Environment]::GetEnvironmentVariable('XWEBSITE_CONTENTSHARE')

if (-not $WEBSITE_CONTENTAZUREFILECONNECTIONSTRING) {
    $WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = [Environment]::GetEnvironmentVariable('WEBSITE_CONTENTAZUREFILECONNECTIONSTRING')
}

if (-not $WEBSITE_CONTENTSHARE) {
    $WEBSITE_CONTENTSHARE = [Environment]::GetEnvironmentVariable('WEBSITE_CONTENTSHARE')
}
$StorageAccountName = $WEBSITE_CONTENTAZUREFILECONNECTIONSTRING -replace ".*AccountName=([^;]+).*", '$1'
$StorageAccountKey = $WEBSITE_CONTENTAZUREFILECONNECTIONSTRING -replace ".*AccountKey=([^;]+).*", '$1'
$EndpointSuffix = '.core.windows.net'

$endpoints = @(
    @{ Address = "$StorageAccountName.blob$EndpointSuffix"; Type = "Blob"; Certificate = ""; DNS = "" },
    @{ Address = "$StorageAccountName.table$EndpointSuffix"; Type = "Table"; Certificate = ""; DNS = "" },
    @{ Address = "$StorageAccountName.file$EndpointSuffix"; Type = "File"; Certificate = ""; DNS = "" },
    @{ Address = "$StorageAccountName.queue$EndpointSuffix"; Type = "Queue"; Certificate = ""; DNS = "" }
)

# Initialize arrays to store the results
# Remove unused variables
$reportDate = Get-Date
"Report is generating now $reportDate , Please wait!"
"You can see the report by downloading the file ConnectionAndDnsResults.html"

# Loop through each endpoint and gather results
foreach ($endpoint in $endpoints) {
    $endpoint.Certificate = (Get-CertificateSubject -Endpoint "$($endpoint.Address):443")
    $endpoint.DNS = NameresolverResult -Endpoint $endpoint.Address
}

$filePort445Result = cmd /c tcpping "$StorageAccountName.file.core.windows.net:445" 2`>`&1
$ListResult = listShare -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

$pattern = "<Name>$WEBSITE_CONTENTSHARE<\/Name>"
$namemMatches = [regex]::Matches($ListResult, $pattern)
$shareNames = ""
foreach ($match in $namemMatches) {
    $shareNames += "Found the Share on the Storage account  $match"
}
$ListResult = $ListResult -replace "><", ">`n<"

# Convert the results to HTML tables
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Connection and DNS Lookup Results</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: rgb(96, 94, 92);
            color: #e0e0e0;
            margin: 50px;
        }
        h2 {
            color: #ffffff;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            border-radius: 10px;
            overflow: hidden;
        }
        table, th, td {
            border: 1px solid #333333;
        }
        th, td {
            padding: 12px;
            text-align: left;
        }
        th {
            background-color: #333333;
        }
        tr:nth-child(even) {
            background-color: #1e1e1e;
        }
        tr:nth-child(odd) {
            background-color: #2b2b2b;
        }
        pre {
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        textarea {
            display: inline-block;
            margin: 0;
            padding: .2em;
            width: auto;
            min-width: 30em;
            max-width: 100%;
            height: auto;
            min-height: 10em;
            background-color: #eee;
            overflow: auto;
            resize: both;
        }
               .alert {
            width: 50%;
            padding: 30px;
            position: relative;
            border-radius: 5px;
            box-shadow: 0 0 2px 0px #ccc;
            background-color: #6a6a6a;
        }
        .alert2 {
            width: 50%;
            position: relative;
            border-radius: 5px;
            box-shadow: 0 0 2px 0px #ccc;
            background-color: #071c6d;
            color: #d0ff00;
            font-size: x-large;
        }
    </style>
</head>
<body>
<h1>Storage Connection Test & DNS Results</h1>
<p><strong>Report Date:</strong><span style='font-family: Arial, sans-serif;color: burlywood;font-size: larger;'> $reportDate</span></p>
$(Get-EndpointsHtmlTable -Endpoints $endpoints)
"@


$html += @"
</table>
<h2>Available File Shares using Rest API over port 443</h2>
<p class='alert warning-alert'>You should see the share Name that match the <code>WEBSITE_CONTENTSHARE = <span class='alert2'>$WEBSITE_CONTENTSHARE</span></code></p>

$(if ([string]::IsNullOrEmpty($shareNames)) {
    "<p class='alert2 warning-alert'>WARNING: No file shares found in the storage account! The share '$WEBSITE_CONTENTSHARE' does not exist.</p>"
} else {
    "<p class='alert2' >$shareNames</p>"
})
<p>Full shares list </p>
<textarea>$ListResult</textarea>
<br>
<br>
<br>

<h2>Testing port 445 for <code>$StorageAccountName.file.core.windows.net</code></h2>
<h3>The command result </h3>
<hr>
<pre class='alert warning-alert'>$filePort445Result</pre>
<p class='alert warning-alert'> 
if you see the text  <span style="text-decoration: underline;">
<strong>"An attempt was made to access a socket in a way forbidden by its access permissions"</strong></span> means that the connection is not blocked 
</p>




</body>
</html>
"@

# Output the HTML to a file
$outputFile = "ConnectionAndDnsResults.html"
$html | Out-File -FilePath $outputFile


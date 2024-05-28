


# Function to perform Test-Connection


function Test-ConnectionResult {
    param (
        [string]$Endpoint
    )
    

    $result = cmd /c tcpping  $Endpoint 2`>`&1
    if ($result) {
        return @{
            Endpoint     = $Endpoint
            Status       = "Success"
            ResponseTime = $result
        }
    }
    else {
        return [PSCustomObject]@{
            Endpoint     = $Endpoint
            Status       = "Failed"
            ResponseTime = "N/A"
        }
    }
}

# Function to perform nslookup
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
    param ( [Parameter(Mandatory = $true, Position = 0)]
        [string]$StorageAccountName,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$StorageAccountKey
    )
    
    $Date = (Get-Date).ToUniversalTime()
    $Datestr = $Date.ToString("R");
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
        $Response = $reader.ReadToEnd();
    }

    Return $Response
}

# Define the list of endpoints
$WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = [Environment]::GetEnvironmentVariable('WEBSITE_CONTENTAZUREFILECONNECTIONSTRING')
$StorageAccountName = $WEBSITE_CONTENTAZUREFILECONNECTIONSTRING -replace ".*AccountName=([^;]+).*", '$1'
$StorageAccountKey = $WEBSITE_CONTENTAZUREFILECONNECTIONSTRING -replace ".*AccountKey=([^;]+).*", '$1'
$EndpointSufix = '.core.windows.net'



$endpoints = @( "$StorageAccountName.blob$EndpointSufix" , "$StorageAccountName.table$EndpointSufix", "$StorageAccountName.file$EndpointSufix", "$StorageAccountName.queue$EndpointSufix" )

# Initialize arrays to store the results
$testConnectionResults = @()
$nslookupResults = @()

"Report is generating now, please wait. You can see the report by downloading the file ConnectionAndDnsResults.html"

# Loop through each endpoint and gather results
foreach ($endpoint in $endpoints) {
    $testConnectionResults += Test-ConnectionResult -Endpoint $endpoint
    $nslookupResults += NameresolverResult -Endpoint $endpoint
}

$filePort445Result = cmd /c tcpping  "$StorageAccountName.file.core.windows.net:445" 2`>`&1
$ListResult = listShare -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

$pattern = '<Name>(.*?)<\/Name>'
 
$namemMatches = [regex]::Matches($ListResult, $pattern)
$shareNames = ""
foreach ($match in $namemMatches) {
    $shareNames += "<li>$match</li>"
}
$ListResult = $ListResult -replace "><", ">`n<"
# Get the current date and time
$reportDate = Get-Date

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
            /* The max-width "100%" value fixes a weird issue where width is too wide by default and extends beyond 100% of the parent in some agents. */
            max-width: 100%;
            /* Height "auto" will allow the text area to expand vertically in size with a horizontal scrollbar if pre-existing content is added to the box before rendering. Remove this if you want a pre-set height. Use "em" to match the font size set in the website. */
            height: auto;
            /* Use "em" to define the height based on the text size set in your website and the text rows in the box, not a static pixel value. */
            min-height: 10em;
            /* Do not use "border" in textareas unless you want to remove the 3D box most browsers assign and flatten the box design. */
            /*border: 1px solid black;*/
            cursor: text;
            /* Some textareas have a light gray background by default anyway. */
            background-color: #eee;
            /* Overflow "auto" allows the box to start with no scrollbars but add them as content fills the box. */
            overflow: auto;
            /* Resize creates a tab in the lower right corner of textarea for most modern browsers and allows users to resize the box manually. Note: Resize isn't supported by most older agents and IE. */
            resize: both;
        }
        .alert{
            width: 50%;
            /* margin: 20px auto; */
            padding: 30px;
            position: relative;
            border-radius: 5px;
            box-shadow: 0 0 15px 5px #ccc;
            background-color: darkgoldenrod;
          }
         
    </style>
</head>
<body>
<h1>Storage Connection Test & DNS Results</h1>
<p><strong>Report Date:</strong><span style='font-family: Arial, sans-serif;color: burlywood;font-size: larger;'> $reportDate</span></p>
    <h2>TCPPing Results</h2>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>Status</th>
            <th>Response Time (ms)</th>
        </tr>
"@

foreach ($result in $testConnectionResults) {
    $html += @"
        <tr>
            <td>$($result.Endpoint)</td>
            <td>$($result.Status)</td>
            <td>$($result.ResponseTime)</td>
        </tr>
"@
}

$html += @"
    </table>
    <h2>NameResolver Results</h2>
    <table>
        <tr>
            <th>Endpoint</th>
            <th>Output</th>
        </tr>
"@

foreach ($result in $nslookupResults) {
    $html += @"
        <tr>
            <td>$($result.Endpoint)</td>
            <td><pre>$($result.Output)</pre></td>
        </tr>
"@
}

$html += @"
    </table>
    <H2>Available File Shares using port 443</h2>
    <p class='alert warning-alert'>You should see the share Name that match the <code>WEBSITE_CONTENTSHARE</code> </p>
    <ul>
    $shareNames
    </ul>
    <textarea>$ListResult</textarea>
   
    <h2>Testing port 445 for <code>$StorageAccountName.file.core.windows.net</code> </h2>
    <p class='alert warning-alert'>"An attempt was made to access a socket in a way forbidden by its access permissions" mean that the connection is open  </p>
     <pre>$filePort445Result</pre>
</body>
</html>
"@

# Output the HTML to a file
$outputFile = "ConnectionAndDnsResults.html"
$html | Out-File -FilePath $outputFile



[CmdletBinding()]
param()

# For more information on the VSTS Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {
    $arm=Get-VstsInput -Name ConnectedServiceNameARM
    $Endpoint = Get-VstsEndpoint -Name $arm -Require
    $la = get-VstsInput -Name la
    $parts = $la.Split('_')
    $name = $parts[0]
    $customerId = $parts[1]
    Write-Host "name is $($name) and customer is $($customerId)"
    $rg = get-VstsInput -Name rg
    $msg = get-VstsInput -Name msg
    $lt=get-VstsInput -Name lt
    try
    {
        $msg|ConvertFrom-Json
    }
    catch
    {
        Write-Error "The message to be written to the logs must be in JSON format"
    }
    $client=$Endpoint.Auth.Parameters.ServicePrincipalId
	$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
	$tenant=$Endpoint.Auth.Parameters.TenantId		
	$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
     "&client_id=$($client)"+
     "&grant_type=client_credentials"+
        "&client_secret=$($secret)"
	try
	{
			#getting ARM token
		$resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($tenant)/oauth2/token" -Method POST -Body $body| ConvertFrom-Json    		
	}
	catch [System.Net.WebException] 
	{
		$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
		Write-Error $er.error.details		
	}
		
	$sharedKeyHeaders = @{
		Authorization = "Bearer $($resp.access_token)"        
	}   
    
    $b64key=(Invoke-WebRequest -UseBasicParsing -Uri "$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.OperationalInsights/workspaces/$($name)/sharedKeys?api-version=2015-03-20" -Method POST -Headers $sharedKeyHeaders|ConvertFrom-Json).secondarySharedKey
    $key=[System.Convert]::FromBase64String($b64key)
    $headers = @{}
    $date=[System.DateTime]::UtcNow.ToString("r")
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $message = "POST`n$($jsonBytes.Length)`napplication/json`nx-ms-date:$($date)`n/api/logs";
    $hmacsha = New-Object System.Security.Cryptography.HMACSHA256
    $hmacsha.key = $key 
    $signature = "SharedKey $($customerId):"+[System.Convert]::ToBase64String($hmacsha.ComputeHash([Text.Encoding]::ASCII.GetBytes($message)))
    $headers.Add("Log-Type",$($lt));
    $headers.Add("x-ms-date",$date);
    $headers.Add("time-generated-field","");
    $headers.Add("Authorization",$signature)
    Invoke-WebRequest -UseBasicParsing -Uri "https://$($customerId).ods.opinsights.azure.com/api/logs?api-version=2016-04-01" -Method Post -Body $msg -Headers $headers -ContentType "application/json"
    Write-Host "Log written to Log Analytics $($name)"

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}

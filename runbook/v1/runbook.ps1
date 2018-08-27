[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {      
	Write-Host "Gathering parameters"  
	Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
    Initialize-Azure
	$rg=Get-VstsInput -Name rg
	$AutomationAccount=Get-VstsInput -Name AutomationAccountName
	$rb=get-VstsInput -Name runbook	
    $uri=Get-VstsInput -Name runbookuri
	$body=Get-VstsInput -Name webhookdata
	$wait=Get-VstsInput -Name wait
	$newwh=Get-VstsInput -Name NewWebHook
	$timeout=Get-VstsInput -Name timeout
	$timeout *= 60
	$wh=$null
	
	if($newwh -eq $true)
	{
		Write-Host "Creating webhook"
		#creating a onetime webhook only used by the current release
		$wh=New-AzureRmAutomationWebhook -Name ([System.Guid]::NewGuid()).Guid -ResourceGroupName $rg -Force -RunbookName $rb -IsEnabled $True -AutomationAccountName $AutomationAccount -ExpiryTime ([System.DateTimeOffset]::Now.AddDays(1)).UtcDateTime
		$uri=$wh.WebhookURI
	}
	Write-Host "Calling webhook"
    $response = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/json"
	$JobCompleted = $false
	$waitingfor=0
	while($JobCompleted -eq $false -and $wait -eq $true)
	{
		Start-Sleep -s 1
		if($waitingfor -ge $timeout)
		{
			throw "Timeout expired"
		}
		$waitingfor++
		$job=Get-AzureRmAutomationJob -Id $response.JobIds[0] -ResourceGroupName $rg -AutomationAccountName $AutomationAccount
		Write-Host "status is $($job.Status)"
		$JobCompleted = (($job.Status -match "Completed") -or ($job.Status -match "Failed") -or ($job.Status -match "Suspended") -or ($job.Status -match "Stopped")) 
	}    
} finally {
	if($wh -ne $null)
	{
		Remove-AzureRmAutomationWebhook $wh.Name -ResourceGroupName $rg -AutomationAccountName $AutomationAccount
	}
    Trace-VstsLeavingInvocation $MyInvocation
}
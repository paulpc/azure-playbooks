<#
.SYNOPSIS 
    This sample Automation runbook integrates with Azure event grid subscriptions to get notified when a 
    write command is performed against an Azure VM.
    The runbook adds a cost tag to the VM if it doesn't exist. It also sends an optional notification 
    to a Microsoft Teams channel indicating that a new VM has been created and that it is set up for 
    automatic shutdown / start up tags.
    
.DESCRIPTION
    This sample Automation runbook integrates with Azure event grid subscriptions to get notified when a 
    write command is performed against an Azure VM.
    The runbook adds a cost tag to the VM if it doesn't exist. It also sends an optional notification 
    to a Microsoft Teams channel indicating that a new VM has been created and that it is set up for 
    automatic shutdown / start up tags.
    A RunAs account in the Automation account is required for this runbook.

.PARAMETER WebhookData
    Optional. The information about the write event that is sent to this runbook from Azure Event grid.
  
.PARAMETER ChannelURL
    Optional. The Microsoft Teams Channel webhook URL that information will get sent.

.NOTES
    AUTHOR: Paul PC
    LASTEDIT: March of 2018 
#>
 
Param(
    [parameter (Mandatory=$false)]
    [object] $WebhookData,

    [parameter (Mandatory=$false)]
    $ChannelURL
)

$RequestBody = $WebhookData.RequestBody | ConvertFrom-Json
$Data = $RequestBody.data

if($Data.operationName -match "MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/WRITE")
{
    # Authenticate to Azure
    $ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint | Write-Verbose
    
    # selecting the apropriate subscription
    $subby = ($Data.resourceID -split "/")[2]                                                                                                                                                                  
    Select-AzureRmSubscription $subby
    
    $rg = ($Data.resourceID -split "/")[4]                                                                                                                                                                     
    $nsg_name = ($Data.resourceID -split "/")[8] 
    # Set subscription to work against
    Set-AzureRmContext -SubscriptionID $ServicePrincipalConnection.SubscriptionId | Write-Verbose

    $nsg = Get-AzureRmNetworkSecurityGroup  -ResourceGroupName $rg -Name $nsg_name
    foreach ($networkwatcher in Get-AzurermNetworkWatcher  -ResourceGroupName NetworkWatcherRg) {
        if ($nsg.Location -eq $networkwatcher.Location) {
            $fl_status = Get-AzureRmNetworkWatcherFlowLogStatus -NetworkWatcher $NW -TargetResourceId $nsg.Id
            if ( ! ($fl_status.Enabled)) {
                if (!([string]::IsNullOrEmpty($ChannelURL)))
                    {
                        $TargetURL = "https://portal.azure.com/#resource" + $Data.resourceUri + "/overview"   
                        
                        $Body = ConvertTo-Json -Depth 4 @{
                        title = 'NSG Creation notification' 
                        text = 'NSG was created, but is not getting logged.'
                        sections = @(
                            @{
                            activityTitle = 'Azure NSG'
                            activitySubtitle = 'NSG ' + $nsg.Name + ' has been created'
                            activityText = 'NSG ' + $subby + ' and resource group ' + $nsg.ResourceGroupName
                            activityImage = 'https://azure.microsoft.com/svghandler/automation/'
                            }
                        )
                        potentialAction = @(@{
                            '@context' = 'http://schema.org'
                            '@type' = 'ViewAction'
                            name = 'Click here to manage the NSG'
                            target = @($TargetURL)
                            })
                        }
                        
                        # call Teams webhook
                        Invoke-RestMethod -Method "Post" -Uri $ChannelURL -Body $Body | Write-Verbose
                    }
                }
            }
        }
    }


 
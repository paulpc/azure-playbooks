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

if($Data.operationName -match "MICROSOFT.NETWORK/NETWORKSECURITYGROUPS/WRITE" -And $Data.status -match "Succeeded")
{
    # Authenticate to Azure
    $ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint | Write-Verbose
    
    # selecting the apropriate subscription
    write-host $Data.resourceUri
    $subby = ($Data.resourceUri -split "/")[2]                                                                                                                                                                  
    Select-AzureRmSubscription $subby
    $rg = ($Data.resourceUri -split "/")[4]                                                                                                                                                                     
    $nsg_name = ($Data.resourceUri -split "/")[8] 
    # Set subscription to work against
    Set-AzureRmContext -SubscriptionID $ServicePrincipalConnection.SubscriptionId | Write-Verbose

    $nsg = Get-AzureRmNetworkSecurityGroup  -ResourceGroupName $rg -Name $nsg_name
    foreach ($networkwatcher in Get-AzurermNetworkWatcher  -ResourceGroupName NetworkWatcherRg) {
        if ($nsg.Location -eq $networkwatcher.Location) {
            $fl_status = Get-AzureRmNetworkWatcherFlowLogStatus -NetworkWatcher $NW -TargetResourceId $nsg.Id
            if ( ! ($fl_status.Enabled)) {

                # this is where we enable the logging
                $logging = "not logging"
                #first of all getting the blob account
                $found=$false
                $blob_name_start=($subby -split "-")[0]

                foreach ($store in Get-AzureRmStorageAccount -ResourceGroupName NetworkWatcherRG) {
                    # looking for blobs in the NetworkWatcherRG group and making sure they are the right odd-named-ones
                    if ($store.Location -eq $nsg.Location -And $store.name.StartsWtih($blob_name_start)) {
                        # that match the location of the NSG
                        $found=$store
                    }
                }

                # if we found one, we can set it
                if ($found) {
                    Set-AzureRmNetworkWatcherConfigFlowLog -NetworkWatcher $networkwatcher -TargetResourceId $nsg.Id -EnableFlowLog $true -StorageAccountId $found.Id
                    $logging = "logging to $($found.Id)"
                }

                if (!([string]::IsNullOrEmpty($ChannelURL)))
                    {
                        $TargetURL = "https://portal.azure.com/#resource" + $Data.resourceUri + "/overview"   
                        
                        $Body = ConvertTo-Json -Depth 4 @{
                        title = 'NSG Creation notification' 
                        text = "NSG was created, $($logging)"
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


 
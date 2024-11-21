# Filename: Connect-RDPOverSSH.ps1

# Prompt for inputs
$azureTenant = Read-Host "Enter the Azure tenant ID"
$subscriptionId = Read-Host "Enter the subscription ID"
$resourceGroup = Read-Host "Enter the resource group name"
$jumpboxVM = Read-Host "Enter the jumpbox VM name"
$targetVM = Read-Host "Enter the target VM name"

# Check if already logged in
try {
    $account = az account show --query "{name:name}" -o json | ConvertFrom-Json
    if (-not $account) {
        throw "Not logged in"
    }
    Write-Host "Already logged into Azure as $($account.name)."
} catch {
    Write-Host "Logging into Azure..."
    az login --tenant $azureTenant
}

# Set the subscription
Write-Host "Setting the subscription..."
az account set --subscription $subscriptionId

# Generate SSH config for the jumpbox VM
$sshConfigFile = ".\sshconfig"

Write-Host "Generating SSH configuration for the jumpbox VM..."
az ssh config --file $sshConfigFile --resource-group $resourceGroup --name $jumpboxVM

# Retrieve the private IP address of the target VM
Write-Host "Retrieving the private IP address of the target VM..."
$targetIP = az vm show --show-details --resource-group $resourceGroup --name $targetVM --query "privateIps" -o tsv

Write-Host "Target VM IP address: $targetIP"

# Establish the SSH tunnel
Write-Host "Establishing SSH tunnel to the target VM through the jumpbox..."
$sshArguments = "-F `"$sshConfigFile`" `$jumpboxVM -L 4001:`"$targetIP`":3389 -N"
$sshProcess = Start-Process ssh.exe -ArgumentList $sshArguments -NoNewWindow -PassThru

# Wait a few seconds to ensure the SSH tunnel is established
Start-Sleep -Seconds 5

# Launch RDP client
Write-Host "Launching RDP client..."
Start-Process mstsc.exe -ArgumentList "/v:localhost:4001"

# Wait for the SSH process to exit (i.e., when the user closes the SSH tunnel)
$sshProcess.WaitForExit()

# Clean up
Write-Host "SSH tunnel closed. Cleaning up..."

# Remove SSH config file if desired
Remove-Item $sshConfigFile -Force

Write-Host "Done."

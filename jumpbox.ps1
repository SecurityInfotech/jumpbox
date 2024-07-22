#!/bin/bash

# Variables
RESOURCE_GROUP="myResourceGroup"  # Replace with your resource group
LOCATION="eastus"  # Replace with your desired location
VM_NAME="myJumpBoxVM"
VM_SIZE="Standard_D2_v2"
ACR_IMAGE=""  # This will be input by the user
NSG_NAME=""  # This will be input by the user
SUBNET_NAME=""  # This will be input by the user
EXTENSION_NAME=""  # This will be input by the user
ADMIN_USERNAME="azureuser"  # Replace with your desired admin username
ADMIN_PASSWORD=""  # This will be input by the user

# Prompt user for inputs
read -p "Enter the ACR image link: " ACR_IMAGE
read -p "Enter the NSG name: " NSG_NAME
read -p "Enter the subnet name: " SUBNET_NAME
read -p "Enter the extension name (leave blank if none): " EXTENSION_NAME
read -s -p "Enter the admin password: " ADMIN_PASSWORD
echo

# Get the subnet ID
SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name myVnet --name $SUBNET_NAME --query id --output tsv)

# Create a network interface with the specified NSG
NIC_ID=$(az network nic create --resource-group $RESOURCE_GROUP --name ${VM_NAME}NIC --vnet-name myVnet --subnet $SUBNET_NAME --network-security-group $NSG_NAME --query id --output tsv)

# Create the VM with the specified parameters
az vm create \
--resource-group $RESOURCE_GROUP \
--name $VM_NAME \
--size $VM_SIZE \
--admin-username $ADMIN_USERNAME \
--admin-password $ADMIN_PASSWORD \
--nics $NIC_ID \
--image $ACR_IMAGE \
--assign-identity \
--custom-data cloud-init.txt

# Check if an extension needs to be added
if [ -n "$EXTENSION_NAME" ]; then
az vm extension set \
--resource-group $RESOURCE_GROUP \
--vm-name $VM_NAME \
--name $EXTENSION_NAME \
--publisher Microsoft.Azure.Extensions \
--version 2.0
fi

# Output the VM details
az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --show-details --output table

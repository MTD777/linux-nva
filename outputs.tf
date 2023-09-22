################################
# Output values
################################


output "NVA_Mgmt_IP" {
  value = azurerm_public_ip.nva_mgmt_pip.ip_address
}

output "NVA_Untrust_IP" {
  value = azurerm_public_ip.nva_untrust_pip.ip_address
}

output "Windows_PIP" {
  value = azurerm_windows_virtual_machine.windows_vm.public_ip_address
}
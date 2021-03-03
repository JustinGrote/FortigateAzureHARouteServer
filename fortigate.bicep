// Mandatory Parameters
@description('Username for the Fortigate virtual appliances.')
param VmName string 

@description('Username for the Fortigate virtual appliances.')
param AdminUsername string

@description('Password for the Fortigate virtual appliances.')
@secure()
param AdminPassword string

@description('Resource ID for the admin access Network Security Group')
param AdminNsgId string

@description('Subnet for the external (port1) interface')
param ExternalSubnet object

@description('Subnet for the internal (port2) interface')
param InternalSubnet object

@description('Load balancer information object from the fortigate loadbalancer module')
param LoadBalancerInfo object

// Optional Parameters
@description('Which Azure Location (Region) to deploy to. Defaults to the same region as the resource group')
param Location string = resourceGroup().location

@description('Fully Qualified DNS Name of the Fortimanager appliance. The fortigates will auto-register with this fortigate upon startup. WARNING: As of 6.2.4 you will need to set the default "admin" password to blank temporarily to be able to click Authorize in Fortimanager and have it complete the tunnel successfully')
param FortimanagerFqdn string = ''

@description('SSH Public Key for the virtual machine. Format: https://www.ssh.com/ssh/key/')
param AdminPublicKey string = ''

@description('Identifies whether to to use PAYG (on demand licensing) or BYOL license model (where license is purchased separately)')
@allowed([
  'fortinet_fg-vm'
  'fortinet_fg-vm_payg_20190624'
])
param FortigateImageSKU string = 'fortinet_fg-vm'

@description('Select image version.')
param FortigateImageVersion string = 'latest'

@description('FortiGate CLI configuration items to add to the basic configuration. You should use the \\n character to delimit newlines, though a multiline string should generally be OK as well')
param FortiGateAdditionalConfig string = ''

@description('Virtual Machine size selection')
param VmSize string = 'Standard_DS3_v2'

param FortinetTags object = {
  provider: '6EB3B02F-50E5-4A3E-8CB8-2E129258317D'
}
@description('Size of the log disk for the virtual appliances. Defaults to 30GB')
param VmLogDiskSizeGB int = 30

@description('IP Address for the external (port1) interface in 1.2.3.4 format.')
param ExternalSubnetIP string = ''

@description('IP Address for the internal (port2) interface in 1.2.3.4 format.')
param InternalSubnetIP string = ''

@description('Availability Set that the fortigate should belong to')
param AvailabilitySetId string = ''

var vmDiagnosticStorageName = toLower(VmName)
var vmPublicKeyConfiguration = {
  ssh: {
    publicKeys: [
      {
        path: '/home/${AdminUsername}/.ssh/authorized_keys'
        keyData: AdminPublicKey
      }
    ]
  }
}

resource nic1 'Microsoft.Network/networkInterfaces@2020-05-01' = {
  name: '${VmName}-port1'
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  properties: {
    ipConfigurations: [
      {
        name: ExternalSubnet.name
        properties: {
          privateIPAllocationMethod: empty(ExternalSubnetIP) ? 'Dynamic' : 'Static' 
          privateIPAddress: empty(ExternalSubnetIP) ? json('null') : ExternalSubnetIP
          subnet: {
            id: ExternalSubnet.id
          }
          loadBalancerBackendAddressPools: [
            {
              id: LoadBalancerInfo.externalBackendId
            }
          ]
          loadBalancerInboundNatRules: [
            {
              id: LoadBalancerInfo.natrules[0].id
            }
            {
              id: LoadBalancerInfo.natrules[1].id
            }
          ]
        }
      }
    ]
    enableIPForwarding: true
    enableAcceleratedNetworking: true
    networkSecurityGroup: {
      id: AdminNsgId
    }
  }
}

resource nic2 'Microsoft.Network/networkInterfaces@2020-05-01' = {
  name: '${VmName}-port2'
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  properties: {
    ipConfigurations: [
      {
        name: InternalSubnet.Name
        properties: {
          privateIPAllocationMethod: empty(InternalSubnetIP) ? 'Dynamic' : 'Static' 
          privateIPAddress: empty(InternalSubnetIP) ? json('null') : InternalSubnetIP
          subnet: {
            id: InternalSubnet.Id
          }
          loadBalancerBackendAddressPools: [
            {
              id: LoadBalancerInfo.internalBackendId
            }
          ]
        }
      }
    ]
    enableIPForwarding: true
    enableAcceleratedNetworking: true
  }
}

resource diagStorage 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: vmDiagnosticStorageName
  location: Location
  kind: 'Storage'
  sku: {
    name: 'Standard_LRS'
  }
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
}

// Unnecessary due to DHCP. Maybe add option for vNet route?
// module externalGateway './getSubnetGateway.bicep' = {
//   name: '${deployment().name}-getSubnet-externalGateway'
//   params: {
//     subnetAddress: externalSubnet.properties.addressPrefix
//   }
// }

// module internalGateway './getSubnetGateway.bicep' = {
//   name: '${deployment().name}-getSubnet-internalGateway'
//   params: {
//     subnetAddress: internalSubnet.properties.addressPrefix
//   }
// }

var fortigateBaseConfigTemplate = '''
config system probe-response
 set mode http-probe
end
config system interface
 edit port1
  set description {0}
  append allowaccess probe-response
 next
 edit port2
  set description {1}
  set allowaccess ping probe-response
 next
end
{2}
'''
var fortigateBaseConfig = format(fortigateBaseConfigTemplate, ExternalSubnet.name, InternalSubnet.name, FortiGateAdditionalConfig)
var fortigateFMConfig = empty(FortimanagerFqdn) ? '' : '\nconfig system central-management\n set type fortimanager\n set fmg ${FortimanagerFqdn}\n end' 
var fortigateConfig = base64('${fortigateBaseConfig}${fortigateFMConfig}')

var availabilitySet = {
  id: AvailabilitySetId
}
resource vmFortigate 'Microsoft.Compute/virtualMachines@2019-07-01' = {
  name: VmName
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  plan: {
    name: FortigateImageSKU
    publisher: 'fortinet'
    product: 'fortinet_fortigate-vm_v5'
  }
  properties: {
    hardwareProfile: {
      vmSize: VmSize
    }
    //Spot instance settings
    priority: empty(AvailabilitySetId) ? 'Spot' : 'Regular' 
    evictionPolicy: empty(AvailabilitySetId) ? 'Deallocate' : json('null')
    billingProfile: {
      maxPrice: empty(AvailabilitySetId) ? -1 : json('null')
    }
    availabilitySet: empty(AvailabilitySetId) ? json('null') : availabilitySet
    osProfile: {
      computerName: VmName
      adminUsername: AdminUsername
      adminPassword: AdminPassword
      linuxConfiguration: empty(AdminPublicKey) ? json('null') : vmPublicKeyConfiguration
      customData: fortigateConfig
    }
    storageProfile: {
      imageReference: {
        publisher: 'fortinet'
        offer: 'fortinet_fortigate-vm_v5'
        sku: FortigateImageSKU
        version: FortigateImageVersion
      }
      osDisk: {
        name: VmName
        createOption: 'FromImage'
      }
      dataDisks: [
        {
          name: '${VmName}-data'
          diskSizeGB: VmLogDiskSizeGB
          lun: 0
          createOption: 'Empty'
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: diagStorage.properties.primaryEndpoints.blob
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          properties: {
            primary: true
          }
          id: nic1.id
        }
        {
          properties: {
            primary: false
          }
          id: nic2.id
        }
      ]
    }
  }
}

output fgName string = VmName
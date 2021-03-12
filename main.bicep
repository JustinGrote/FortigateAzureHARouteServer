targetScope = 'resourceGroup'
// Mandatory Parameters
@secure()
@description('Password for the user defined by AdminUsername')
param AdminPassword string

// Optional Parameters
@description('Name for FortiGate virtual appliances (A & B will be appended to the end of each respectively). Defaults to the same name as the resource group.')
param FgNamePrefix string = resourceGroup().name

@description('Which Azure Location (Region) to deploy to. Defaults to the same location as the resource group')
param Location string = resourceGroup().location

@description('Resource ID of the Public IP to use for the outbound traffic and inbound management. A standard static SKU Public IP is required. Default is to generate a new one')
param PublicIPID string = ''

@description('Fully Qualified DNS Name of the Fortimanager appliance. The fortigates will auto-register with this fortimanager upon startup')
param FortimanagerFqdn string = ''

@secure()
@description('Password to use for Fortimanager connectivity, similar to a pre-shared key. Once the appliance registers with the fortimanager you will need to run "exec dev replace pw <Hostname> <ThisPassword>" at the fortimanager command line for each fortigate before clicking "Authorize". This will default to a random string that will show in the outputs upon deployment')
param FortimanagerPassword string = ''

@description('Username for the Fortigate virtual appliances. Defaults to fgadmin. NOTE: This must be something other than "admin" or the process will fail because admin is used exclusively for fortimanager communication')
param AdminUsername string = 'fgadmin'

@description('Id of an SSH public key resource stored in Azure to be used for SSH login to the user defined by AdminUsername. The public key is not sensitive information.')
param AdminSshPublicKeyId string = ''

@description('Specify true for a Bring Your Own License (BYOL) deployment, otherwise the fortigate license will be included in the VM subscription cost')
param BringYourOwnLicense bool = false

@description('Use spot instances to save cost at the expense of potential reduced availability. Availability set will be disabled with this option')
param UseSpotInstances bool = false

@description('Specify the version to use e.g. 6.4.2. Defaults to latest version')
param FgVersion string = 'latest'

@description('Specify an alternate VM size. The VM size must allow for at least two NICs, and four are recommended')
param VmSize string = 'Standard_DS3_v2'

@description('The port to use for accessing the http management interface of the first Fortigate')
param FgaManagementHttpPort int = 50443

@description('The port to use for accessing the http management interface of the second Fortigate')
param FgbManagementHttpPort int = 51443

@description('The port to use for accessing the ssh management interface of the first Fortigate')
param FgaManagementSshPort int = 50022

@description('The port to use for accessing the ssh management interface of the first Fortigate')
param FgbManagementSshPort int = 51022

@description('IP Address for the external (port1) interface in 1.2.3.4 format. This should normally not be set as only the LB addresses matters')
param FgaExternalSubnetIP string = ''

@description('IP Address for the external (port1) interface in 1.2.3.4 format. This should normally not be set as only the LB addresses matters')
param FgaInternalSubnetIP string = ''

@description('IP Address for the external (port1) interface in 1.2.3.4 format. This should normally not be set as only the LB addresses matters')
param FgbExternalSubnetIP string = ''

@description('IP Address for the external (port1) interface in 1.2.3.4 format. This should normally not be set as only the LB addresses matters')
param FgbInternalSubnetIP string = ''

@description('Specify the ID of an existing vnet to use. You must specify the internalSubnetName and externalSubnetName options if you specify this option')
param ExternalSubnetName string = 'External'

@description('Specify the name of the internal subnet. The port1 interface will be given this name')
param InternalSubnetName string = 'Transit'

param FortinetTags object = {
  provider: '6EB3B02F-50E5-4A3E-8CB8-2E129258317D'
}

@description('Add a random suffix to names that must be regionally unique, such as DNS names or storage accounts')
param RegionUniqueNames bool = false

// New vNet Scenario parameters
@description('vNet Address Prefixes to allocate to the vNet')
param VnetAddressPrefixes array = [
  '10.0.0.0/16'
]

@description('Subnet range for the external network.')
param ExternalSubnetPrefix string = '10.0.1.0/24'

@description('Subnet range for the internal (transit) network. There typically will be no other devices in this subnet besides the internal load balancer, it is just used as a UDR target')
param InternalSubnetPrefix string = '10.0.2.0/24'

// Existing vNet Scenario parameters
@description('Specify the name of an existing vnet within the subscription to use. You must specify the internalSubnetName and externalSubnetName options if you specify this option, as well as vnetResourceGroupName if the vnet is not in the same resource group as this deployment')
param ExistingVNetId string = ''

//Route Server Scenario
@description('Deploy an Azure Route Server for internal BGP communication to the vnet')
param UseRouteServer bool = false

@description('IP Range to use for the RouteServerSubnet. If it exists in the vnet the existing will be used')
param RouteServerSubnetPrefix string = '10.0.0.64/27'

@description('BGP ASN to use for the fortigate firewalls. Defaults to 65515')
param FortigateBgpAsn int = 65511

var deploymentName = deployment().name

resource fgAdminNsg 'Microsoft.Network/networkSecurityGroups@2020-05-01' = {
  name: FgNamePrefix
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  properties: {
    securityRules: [
      {
        name: 'AllowAllInbound'
        properties: {
          description: 'Allow all in'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllOutbound'
        properties: {
          description: 'Allow all out'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 105
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource fgSet 'Microsoft.Compute/availabilitySets@2019-07-01' = if (!UseSpotInstances) {
  name: FgNamePrefix
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 2
  }
}

module network 'network.bicep' = if (empty(ExistingVNetId)) {
  name: '${deploymentName}-network'
  params: {
    VnetName: FgNamePrefix
    VnetAddressPrefixes: VnetAddressPrefixes
    InternalSubnetPrefix: InternalSubnetPrefix
    ExternalSubnetPrefix: ExternalSubnetPrefix
    InternalSubnetName: InternalSubnetName
    ExternalSubnetName: ExternalSubnetName
    RouteServerSubnetPrefix: RouteServerSubnetPrefix
  }
}

//This is a module because we need to retrieve the peering IPs and ASN for the fortigate config
module routeserver 'routeserver.bicep' = {
  name: '${deploymentName}-routeserver'
  params: {
    RouteServerName: FgNamePrefix
    Location: Location
    // TODO: Specify alternate vnet via external resource
    RouteServerSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', FgNamePrefix, 'RouteServerSubnet')
  }
}

var internalSubnetInfo = {
  id: empty(ExistingVNetId) ? network.outputs.internalSubnet.id : '${ExistingVNetId}/subnets/${InternalSubnetName}'
  name: !empty(network.outputs.internalSubnet.name) ? network.outputs.internalSubnet.name : InternalSubnetName
}
var externalSubnetInfo = {
  id: empty(ExistingVNetId) ? network.outputs.externalSubnet.id : '${ExistingVNetId}/subnets/${ExternalSubnetName}'
  name: !empty(network.outputs.externalSubnet.name) ? network.outputs.externalSubnet.name : ExternalSubnetName
}

var externalSubnetId = empty(ExistingVNetId) ? network.outputs.externalSubnet.id : '${ExistingVNetId}/subnets/${ExternalSubnetName}'

var LbName = FgNamePrefix
var LbDnsName = RegionUniqueNames ? toLower('${LbName}-${substring(uniqueString(LbName), 0, 4)}') : toLower('${LbName}')
resource pip 'Microsoft.Network/publicIPAddresses@2020-05-01' = if (empty(PublicIPID)) {
  name: LbName
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: LbDnsName
    }
  }
}

resource externalLB 'Microsoft.Network/loadBalancers@2020-05-01' = {
  name: FgNamePrefix
  location: Location
  tags: {
    provider: toUpper(FortinetTags.provider)
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: empty(PublicIPID) ? pip.id : PublicIPID
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'default'
      }
    ]
    loadBalancingRules: []
    outboundRules: [
      {
        name: 'default'
        properties: {
          allocatedOutboundPorts: 0
          protocol: 'All'
          enableTcpReset: true
          idleTimeoutInMinutes: 4
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', LbName, 'default')
          }
          frontendIPConfigurations: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', LbName, 'default')
            }
          ]
        }
      }
    ]
    inboundNatRules: [
      {
        name: 'default'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', LbName, 'default')
          }
          protocol: 'Tcp'
          frontendPort: FgaManagementSshPort
          backendPort: 22
          enableFloatingIP: false
        }
      }
      {
        name: '${LbName}A-Management-HTTPS'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', LbName, 'default')
          }
          protocol: 'Tcp'
          frontendPort: FgaManagementHttpPort
          backendPort: 443
          enableFloatingIP: false
        }
      }
      {
        name: '${LbName}B-Management-SSH'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', LbName, 'default')
          }
          protocol: 'Tcp'
          frontendPort: FgbManagementSshPort
          backendPort: 22
          enableFloatingIP: false
        }
      }
      {
        name: '${LbName}B-Management-HTTPS'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', LbName, 'default')
          }
          protocol: 'Tcp'
          frontendPort: FgbManagementHttpPort
          backendPort: 443
          enableFloatingIP: false
        }
      }
    ]
    probes: [
      {
        properties: {
          protocol: 'Tcp'
          port: 8008
          intervalInSeconds: 5
          numberOfProbes: 2
        }
        name: 'lbprobe'
      }
    ]
  }
}

var fgImageSku = BringYourOwnLicense ? 'fortinet_fg-vm' : 'fortinet_fg-vm_payg_20190624'

var fortigateALoadBalancerInfo = {
  externalBackendId: externalLB.properties.backendAddressPools[0].id
  natrules: [
    {
      id: externalLB.properties.inboundNatRules[0].id
    }
    {
      id: externalLB.properties.inboundNatRules[1].id
    }
  ]
}

var fortigateBLoadBalancerInfo = {
  externalBackendId: externalLB.properties.backendAddressPools[0].id
  natrules: [
    {
      id: externalLB.properties.inboundNatRules[2].id
    }
    {
      id: externalLB.properties.inboundNatRules[3].id
    }
  ]
}

var fortigateBgpConfigTemplate = '''
config router bgp
  set as {0}
  set keepalive-timer 1
  set holdtime-timer 3
  set ebgp-multipath enable
  set graceful-restart enable
  config neighbor
      edit "{2}"
          set ebgp-enforce-multihop enable
          set soft-reconfiguration enable
          set interface "port2"
          set remote-as {1}
          {4}
      next
      edit "{3}"
          set ebgp-enforce-multihop enable
          set soft-reconfiguration enable
          set interface "port2"
          set remote-as {1}
          {4}
      next
  end
end
'''

var fortigateABgpConfig = format(fortigateBgpConfigTemplate, FortigateBgpAsn, routeserver.outputs.asn, routeserver.outputs.routerA, routeserver.outputs.routerB, null)

var secondaryConfigTemplate = '''
config router route-map
  edit "SecondaryPath"
    config rule
      edit 1
        set set-aspath "{0} {0} {0}"                        
      next
    end
  next
end

config router bgp
  config neighbor
    edit "{1}"
      set route-map-out "SecondaryPath"
    next
    edit "{2}"
      set route-map-out "SecondaryPath"
    next
  end
end
'''
var secondaryConfig = format(secondaryConfigTemplate,FortigateBgpAsn,routeserver.outputs.routerA,routeserver.outputs.routerB)
var fortigateBBgpConfig = format(fortigateBgpConfigTemplate, FortigateBgpAsn, routeserver.outputs.asn, routeserver.outputs.routerA, routeserver.outputs.routerB, secondaryConfig)

module fortigateA 'fortigate.bicep' = {
  name: '${deploymentName}-fortigateA'
  params: {
    //Fortigate Instance-Specific Parameters
    VmName: '${FgNamePrefix}A'
    LoadBalancerInfo: fortigateALoadBalancerInfo
    ExternalSubnetIP: !empty(FgaExternalSubnetIP) ? FgaExternalSubnetIP : ''
    InternalSubnetIP: !empty(FgaInternalSubnetIP) ? FgaInternalSubnetIP : ''

    //Fortigate Common Parameters
    Location: Location
    VmSize: VmSize
    RegionUniqueNames: RegionUniqueNames
    AdminUsername: AdminUsername
    AdminPassword: AdminPassword
    AdminSshPublicKeyId: AdminSshPublicKeyId
    FortigateImageSKU: fgImageSku
    FortigateImageVersion: FgVersion
    FortimanagerFqdn: FortimanagerFqdn
    FortimanagerPassword: FortimanagerPassword
    FortiGateAdditionalConfig: fortigateABgpConfig
    AdminNsgId: fgAdminNsg.id
    AvailabilitySetId: empty(fgSet.id) ? fgSet.id : ''
    ExternalSubnet: externalSubnetInfo
    InternalSubnet: internalSubnetInfo
  }
}

module fortigateB 'fortigate.bicep' = {
  name: '${deploymentName}-fortigateB'
  params: {
    //Fortigate Instance-Specific Parameters
    VmName: '${FgNamePrefix}B'
    LoadBalancerInfo: fortigateBLoadBalancerInfo
    ExternalSubnetIP: !empty(FgbExternalSubnetIP) ? FgbExternalSubnetIP : ''
    InternalSubnetIP: !empty(FgbInternalSubnetIP) ? FgbInternalSubnetIP : ''

    //Fortigate Common Parameters
    Location: Location
    VmSize: VmSize
    RegionUniqueNames: RegionUniqueNames
    AdminUsername: AdminUsername
    AdminPassword: AdminPassword
    AdminSshPublicKeyId: AdminSshPublicKeyId
    FortigateImageSKU: fgImageSku
    FortigateImageVersion: FgVersion
    FortimanagerFqdn: FortimanagerFqdn
    FortimanagerPassword: FortimanagerPassword
    FortiGateAdditionalConfig: fortigateBBgpConfig
    AdminNsgId: fgAdminNsg.id
    AvailabilitySetId: empty(fgSet.id) ? fgSet.id : ''
    ExternalSubnet: externalSubnetInfo
    InternalSubnet: internalSubnetInfo
  }
}

// var fqdn = loadbalancer.outputs.publicIpFqdn
// var baseUri = 'https://${fqdn}'
// var baseSsh = 'ssh ${AdminUsername}@${fqdn}'
// output fgManagementUser string = AdminUsername
// output fgaManagementUri string = '${baseUri}:${FgaManagementHttpPort}'
// output fgbManagementUri string = '${baseUri}:${FgbManagementHttpPort}'
// output fgaManagementSshCommand string = '${baseSsh} -p ${FgaManagementSshPort}' 
// output fgbManagementSshCommand string = '${baseSsh} -p ${FgbManagementSshPort}'

// var fgManagementSSHConfigTemplate = '''

// Host {0}  
//   HostName {1}
//   Port {2}
//   User {3}
// '''
// output fgaManagementSSHConfig string = format(fgManagementSSHConfigTemplate, fortigateA.outputs.fgName, fqdn, FgaManagementSshPort, AdminUsername)
// output fgbManagementSSHConfig string = format(fgManagementSSHConfigTemplate, fortigateB.outputs.fgName, fqdn, FgbManagementSshPort, AdminUsername)

// output fgaFortimanagerSharedKeyCommand string = fortigateA.outputs.fortimanagerSharedKey
// output fgbFortimanagerSharedKeyCommand string = fortigateB.outputs.fortimanagerSharedKey
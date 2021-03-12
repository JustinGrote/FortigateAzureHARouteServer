//Generic Route Server config template
param RouteServerSubnetId string
param RouteServerName string
param Location string

resource routeserver 'Microsoft.Network/virtualHubs@2020-06-01' = {
  name: RouteServerName
  location: Location
  properties: {
    sku: 'Standard'
  }
}

resource routeserveripconfig 'Microsoft.Network/virtualHubs/ipConfigurations@2020-06-01' = {
  //This name is critical, it will not work with any other name
  name: '${routeserver.name}/ipconfig1'
  dependsOn: any(routeserver.id)
  properties: {
    subnet: {
      //TODO: Existing vnet?
      id: RouteServerSubnetId
    }
  }
}

output asn int = routeserver.properties.virtualRouterAsn
output routerA string = routeserver.properties.virtualRouterIps[0]
output routerB string = routeserver.properties.virtualRouterIps[1]
# Securely connect to an External Endpoint from Azure

# Introduction
Azure’s [Private Link](https://docs.microsoft.com/en-us/azure/private-link/private-link-overview) enables you to securely access Azure PaaS and Partner resources over a private endpoint (PE) in your own virtual network (VNET).  The private access is resource specific as opposed to service specific and protects against data exfiltration in that connectivity can be initiated in only a single direction.

# IaaS Connectivity
In addition to being able to connect to PaaS resources, you can also securely connect to Azure Virtual Machines (IaaS) that are fronted by a Standard Internal Load Balancer as shown in the figure below:
![Figure 1](images/Azure_IaaS_PLS.png)
The Private Link Service (PLS) as shown in the Provider Network performs [Destination NAT](https://en.wikipedia.org/wiki/Network_address_translation#DNAT) which prevents IP overlapping issues between the Consumer and Provider VNETs in Azure.  From the perspective of the Provider Network, the source IP is going to be the NAT-ted IP (192.168.0.5 from the figure above).  The Provider can determine the original source of the connection by looking at the TCP Proxy V2 header.  Details for this is outside the scope of this article but more information on how one can get the source IP can be found [here](https://docs.microsoft.com/en-us/azure/private-link/private-link-service-overview#getting-connection-information-using-tcp-proxy-v2).

# Connectivity from Managed/Secure VNET to a server in another VNET or On-Premises server
If you want to connect from a private/managed subnet to an on-premise server or a server in another VNET as shown in the figure below which shows connectivity from Azure Data Factory (ADF) Managed Virtual Network to an on-premise SQL Server
Steps to implement this solution:
```
az login 
az group create 

```




# Securely connect to an External Endpoint from Azure

# Introduction
Azure’s [Private Link](https://docs.microsoft.com/en-us/azure/private-link/private-link-overview) enables you to securely access Azure PaaS and Partner resources over a private endpoint (PE) in your own virtual network (VNET).  The private access is resource specific as opposed to service specific and protects against data exfiltration in that connectivity can be initiated in only a single direction.

# IaaS Connectivity
In addition to being able to connect to PaaS resources, you can also securely connect to Azure Virtual Machines (IaaS) that are fronted by a Standard Internal Load Balancer as shown in the figure below:
![Figure 1](images/Azure_IaaS_PLS.png)

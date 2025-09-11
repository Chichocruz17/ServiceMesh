Implementing a Service Mesh for a Core Banking Cell-Based Architecture with Consul
Overview: The Need for a Service Mesh in a Cell-Based Architecture
Modernizing a core banking platform often involves adopting a Cell-Based Architecture. This pattern segregates services into logical, domain-oriented "cells" (e.g., Retail, Corporate, Payments, and a Common cell for shared services) which can be deployed and scaled independently, often across multiple on-premise OpenShift clusters for high availability and disaster recovery.

This distributed architecture introduces significant networking and security challenges:

How do we intelligently route traffic to the correct cell based on complex business logic?

How do we enforce strict security boundaries, ensuring services in one cell cannot improperly access another?

How do we maintain a global, real-time registry of all services across all cells and datacenters?

How can we encrypt all communication between services automatically?

How do we ensure the entire system is resilient to failures within a cell or an entire datacenter?

This document outlines the architecture for solving these challenges by implementing HashiCorp Consul as a service mesh. Consul provides a consistent control plane for networking, security, and resiliency across the entire cell-based platform running on OpenShift.

The Role of the Service Mesh in Supporting Cells
A service mesh provides the critical infrastructure layer that enables a cell-based architecture to function securely and efficiently.

Service Registry & Discovery: In a multi-cell architecture spanning different OpenShift clusters, a globally aware service registry is essential. Consul provides a central catalog that tracks the real-time health and location of every service in every cell, accessible via both DNS and a rich HTTP API.

Load Balancing: Consul's Envoy sidecar proxies provide advanced Layer 7 load balancing. This ensures that traffic is intelligently distributed among service instances within a cell, improving performance and resilience.

Automatic mTLS Encryption: Consul Connect automatically secures all traffic between services, both within the same cell and across different cells. It manages the entire certificate lifecycle, providing a foundational layer of zero-trust security.

Access Control (Intentions): Consul Intentions are used to enforce strict communication boundaries. They operate on a "deny-by-default" principle, meaning you must explicitly define which cells and services are allowed to communicate. For example, an intention can ensure that a service in the Paylah cell cannot call a service in the Corporate cell unless explicitly permitted.

Observability: A service mesh is critical for understanding traffic flows in a complex cell-based architecture. The Envoy proxies export detailed metrics and tracing data, providing deep visibility into the performance and dependencies of inter- and intra-cell communication.

Resiliency Patterns: Consul enables critical resiliency patterns like retries, timeouts, and circuit breaking. These are configured centrally and enforced at the data plane, making the entire platform more resilient to transient failures or service degradation within any given cell.

Consul Architecture for a Cell-Based Deployment
To support a multi-datacenter, cell-based deployment on OpenShift, the Consul infrastructure is deployed in a highly available configuration within each cluster.

The Control Plane: The brain of the service mesh, consisting of a cluster of Consul servers, is deployed as an OpenShift StatefulSet. This provides the stable storage and network identity needed to maintain the mesh's state. Each datacenter (e.g., East and West) runs its own Consul control plane.

The Data Plane: A Consul client agent is deployed to every OpenShift worker node using a DaemonSet. For each application pod that joins the mesh, a lightweight Envoy sidecar proxy is automatically injected. This proxy intercepts all network traffic to and from the application, enforcing the policies defined by the control plane.

This architecture ensures that the service mesh infrastructure is as resilient as the cell-based applications it supports.

# ServiceMesh # ServiceMesh# ServiceMesh # ServiceMesh
```mermaid 
graph TD
    subgraph "On-Premise OpenShift Cluster"
        direction TB

        subgraph "Control Plane"
            subgraph "Consul Servers (StatefulSet)"
                S1["Consul Server 1"]
                S2["Consul Server 2"]
                S3["Consul Server 3"]
            end
            S1 <-.->|"Raft Consensus"| S2
            S2 <-.->|"Raft Consensus"| S3
            S3 <-.->|"Raft Consensus"| S1
        end

        subgraph "Data Plane (Worker Nodes)"
            direction LR
            subgraph "Worker Node 1"
                C1["Consul Client (DaemonSet Pod)"]
                subgraph "Application Pod A"
                    App1["App Container"] --> E1["Envoy Sidecar"]
                end
            end

            subgraph "Worker Node 2"
                C2["Consul Client (DaemonSet Pod)"]
                subgraph "Application Pod B"
                    App2["App Container"] --> E2["Envoy Sidecar"]
                end
            end
        end

        %% Define Interactions
        S2 -- "Distributes Config (gRPC)" --> C1
        S2 -- "Distributes Config (gRPC)" --> C2
        C1 -- "Manages Local Proxy" --> E1
        C2 -- "Manages Local Proxy" --> E2
        E1 -- "Service Traffic via mTLS" --> E2
    end

    %% Define Styles
    classDef controlPlane fill:#e0f2fe,stroke:#3b82f6,stroke-width:2px
    classDef dataPlane fill:#dcfce7,stroke:#22c55e,stroke-width:2px
    classDef appPod fill:#fefce8,stroke:#eab308,stroke-width:2px
    class S1,S2,S3 controlPlane
    class C1,C2,E1,E2 dataPlane
    class App1,App2 appPod

```

Resiliency and Disaster Recovery for the Cell-Based Platform
For a mission-critical banking platform, resilience is paramount. The architecture must tolerate failures ranging from a single pod to an entire datacenter.

Multi-Cluster Resiliency with Mesh Gateways
The Consul deployments in the East and West datacenters are federated, allowing them to form a single global service mesh. All traffic between the two sites is securely routed through Mesh Gateways. These gateways are dedicated Envoy proxies that act as the entry/exit points for all cross-datacenter traffic, ensuring it is encrypted, controlled, and observable.

Active-Passive Failover
The primary disaster recovery model is active-passive, with the East datacenter serving live traffic and the West datacenter on standby. This is managed declaratively using Consul's native OpenShift CRDs:

ServiceResolver: This CRD logically partitions services into subsets based on their location (e.g., an east subset and a west subset).

ServiceSplitter: This CRD controls the traffic flow. In normal operation, it is configured to route 100% of traffic to the east subset. During a DR event, an operator or automation simply updates this CRD to route 100% of traffic to the west, and Consul handles reconfiguring the entire data plane to redirect traffic.

```mermaid
graph TD
    subgraph "User Traffic"
        U(Users)
    end

    GLB[Global Load Balancer]

    subgraph "East Datacenter (Active)"
        OC_East["OpenShift Cluster (East)"]
        subgraph OC_East
          MGE[Mesh Gateway East]
          ServiceA_East["Service A"]
          ServiceB_East["Service B"]
        end
    end

    subgraph "West Datacenter (Passive)"
      OC_West["OpenShift Cluster (West)"]
      subgraph OC_West
        MGW[Mesh Gateway West]
        ServiceA_West["Service A"]
        ServiceB_West["Service B"]
      end
    end

    U --> GLB
    GLB -- "100% Traffic" --> MGE
    GLB -.->|"0% Traffic (Failover Path)"| MGW
    MGE --> ServiceA_East --> ServiceB_East
    MGW --> ServiceA_West --> ServiceB_West
    MGE <-.->|"Federated Control Plane Traffic"| MGW

    classDef active fill:#dcfce7,stroke:#22c55e
    classDef passive fill:#f1f5f9,stroke:#64748b
    class MGE,ServiceA_East,ServiceB_East active
    class MGW,ServiceA_West,ServiceB_West passive

```

E2E Security and Advanced Cell-Based Routing
The Global Load Balancer (GLB)
In front of the two datacenters sits a Global Load Balancer (GLB). This is a DNS-based routing service responsible for directing end-user traffic to the active datacenter. The GLB relies on health checks that continuously monitor application availability in both East and West. If the health checks for the East datacenter fail, the GLB automatically updates its DNS records to send all traffic to the West, automating the user-facing aspect of a failover. 

```mermaid

graph LR
    subgraph "East Datacenter"
        direction TB
        subgraph "Consul Servers (East)"
            S_E1["Server E1"]
            S_E2["Server E2"]
            S_E3["Server E3"]
        end
        S_E1 <-.->|"LAN Gossip"| S_E2
        S_E2 <-.->|"LAN Gossip"| S_E3
        MGE[Mesh Gateway East]
    end

    subgraph "West Datacenter"
        direction TB
        subgraph "Consul Servers (West)"
            S_W1["Server W1"]
            S_W2["Server W2"]
            S_W3["Server W3"]
        end
        S_W1 <-.->|"LAN Gossip"| S_W2
        S_W2 <-.->|"LAN Gossip"| S_W3
        MGW[Mesh Gateway West]
    end

    S_E1 <-->|"WAN Gossip"| S_W1
    S_E2 <-->|"WAN Gossip"| S_W2

    %% Define RPC Forwarding for cross-datacenter query
    style MGE fill:#dcfce7,stroke:#22c55e
    style MGW fill:#dcfce7,stroke:#22c55e

```

Advanced Routing with Envoy Lua Filters
The core challenge is routing an incoming request to the correct cell (Retail, Corporate, or Paylah) based on business logic. This is achieved by deploying a custom Lua script as an Envoy filter on the Consul Ingress Gateway.

This script acts as an intelligent, centralized router at the edge of the mesh. For each incoming request, it performs two stages of logic:

Fast Path Routing: It first inspects the request path and payload for well-known identifiers (e.g., specific product codes or account prefixes) that map directly to a destination cell. This handles high-volume, predictable traffic with maximum efficiency.

Dynamic Lookup: If the request doesn't match a fast path, the script makes an internal, asynchronous call to the Cell Localization Service (CLS) in the Common Cell. The CLS encapsulates the complex business logic to determine the correct destination. The Lua script uses the CLS response to route the original request to the appropriate cell.

This advanced routing logic is defined in an external script and declaratively applied to the Ingress Gateway using Consul's CRDs. This centralizes the routing intelligence and decouples clients from the internal service topology.

The Lua script that implements this logic can be found here: [Code: Cell Localization Lua Script - See assets/cell_router.lua]  


The script is deployed by applying it to the gateway via a Consul CRD: [Code: Ingress Gateway CRD Configuration - See assets/ingress_gateway.yaml]

```mermaid
graph TD
    %% Define the main actors and entry point
    Client([External Client]) -- "API Request" --> IngressGateway;

    %% Define the main cluster boundary
    subgraph "On-Premise OpenShift Cluster"
        %% Ingress Gateway is the edge component
        subgraph "Consul Ingress Gateway"
            IngressGateway("fa:fa-network-wired Ingress Gateway<br/><i>Lua Filter Enforced Here</i>");
        end

        %% Define the logical cells
        subgraph "Common Cell"
            CLS("Cell Localization Service (CLS)");
            GLS_DB[(GLS DB)];
            CLS -- "Queries" --> GLS_DB;
        end

        subgraph "Retail Cell"
            RetailServices("Retail Banking Services");
        end

        subgraph "Corporate Cell"
            CorporateServices("Corporate Banking Services");
        end

        subgraph "Paylah Cell (Wallet)"
            PaylahServices("Payment & Wallet Services");
        end

        %% Define the routing logic flows from the Gateway
        IngressGateway -- "<b>Rules 1-5: Fast Path Routing</b><br/>Directly routes based on Path/Payload<br/>(e.g., Product Code '010')" --> RetailServices;
        IngressGateway -- " " --> CorporateServices;
        IngressGateway -- " " --> PaylahServices;

        IngressGateway -- "<b>Rule 6: Dynamic Lookup</b><br/>Forwards request context to CLS" --> CLS;
        CLS -.->|"<b>Rule 7: Lookup & Respond</b><br/>Returns target cell name (e.g., 'retail-cell')"| IngressGateway;

        %% Final routing after dynamic lookup
        IngressGateway -.->|"<b>Routes based on CLS response</b>"| RetailServices;
        IngressGateway -.->|" "| CorporateServices;
        IngressGateway -.->|" "| PaylahServices;
    end

    %% Styling
    style Client fill:#f3e8ff,stroke:#8b5cf6
    style IngressGateway fill:#e0f2fe,stroke:#3b82f6,stroke-width:2px
    style CLS fill:#fefce8,stroke:#eab308,stroke-width:2px
    style GLS_DB fill:#fefce8,stroke:#eab308
    classDef cell fill:#dcfce7,stroke:#22c55e,stroke-width:1px,color:#15803d
    class RetailServices,CorporateServices,PaylahServices cell
```

```mermaid
graph TD
    subgraph "OpenShift Cluster 1 (Partition: p1)"
        direction TB
        subgraph "App-A Pod"
            AppA["App-A Container"] -- "1. curl app-b.p2..." --> SidecarA["Envoy Sidecar"]
        end
        SidecarA -- "2. Routes to local Mesh GW" --> MeshGW1["Mesh Gateway (p1)"]
    end

    subgraph "OpenShift Cluster 2 (Partition: p2)"
        direction TB
        MeshGW2["Mesh Gateway (p2)"] -- "4. Forwards to App-B sidecar" --> SidecarB["Envoy Sidecar"]
        subgraph "App-B Pod"
             SidecarB -- "Delivers request" --> AppB["App-B Container"]
        end
    end

    MeshGW1 -- "3. Encrypted mTLS Peering Traffic" --> MeshGW2

    classDef cluster1 fill:#e0f2fe,stroke:#3b82f6
    classDef cluster2 fill:#eef2ff,stroke:#6366f1
    class AppA,SidecarA,MeshGW1 cluster1
    class AppB,SidecarB,MeshGW2 cluster2
```
Service Identity & Secrets Management
The service mesh, integrated with HashiCorp Vault, provides a modern, identity-based approach to security that dramatically reduces the need for traditional secrets like Functional IDs, static certificates, and API tokens.

Service-to-Service Communication
In a traditional model, services might need API tokens or manually managed certificates to authenticate with each other. The service mesh eliminates this requirement.

The Service Mesh Answer: No, services do not need Functional IDs or developer-managed tokens to communicate. The mesh provides a strong, automated identity to every workload based on the SPIFFE standard. Communication is authenticated and encrypted using short-lived automatic mTLS certificates managed by the Consul control plane. Developers no longer manage this layer of security; it is an automatic feature of the platform.

```mermaid
graph TD
    subgraph "Consul Control Plane"
        ConsulServer["fa:fa-server Consul Server (CA)"]
    end

    subgraph "OpenShift Data Plane"
        subgraph "Pod A"
            AppA["App-A Container"]
            SidecarA["fa:fa-shield-alt Envoy Sidecar A"]
        end
        
        subgraph "Pod B"
            AppB["App-B Container"]
            SidecarB["fa:fa-shield-alt Envoy Sidecar B"]
        end
        
        ConsulServer -- "1. Distributes SPIFFE Certs" --> SidecarA & SidecarB
        AppA -- "2. Plaintext to Sidecar" --> SidecarA
        SidecarA -- "3. Automatic mTLS Encryption" --> SidecarB
        SidecarB -- "4. Decrypts & Forwards Plaintext" --> AppB
    end

    classDef control fill:#e0f2fe,stroke:#3b82f6;
    classDef data fill:#dcfce7,stroke:#22c55e;
    class ConsulServer control;
    class AppA,AppB,SidecarA,SidecarB data;
```
Communicating with External Databases
The traditional method for a service to connect to a database involves using a long-lived Functional ID and password, often stored in an OpenShift secret. This is a significant security risk.

The Service Mesh Answer: The best practice is to integrate with HashiCorp Vault's Database Secrets Engine. The application pod is injected with a Vault Agent sidecar, which authenticates to Vault using its OpenShift Service Account identity. The application can then request dynamic, on-demand database credentials from Vault. These credentials are unique, have a short time-to-live (TTL), and are automatically revoked. This completely eliminates the need for static Functional IDs for databases.

```mermaid
graph TD
    subgraph "External Systems"
        Database["fa:fa-database Legacy Database"]
    end

    subgraph "OpenShift Cluster"
        Vault["fa:fa-key HashiCorp Vault"]
        TerminatingGW["fa:fa-sign-out-alt Terminating Gateway"]
        
        subgraph "Application Pod"
            direction LR
            App["App Container"]
            VaultAgent["fa:fa-user-secret Vault Agent Sidecar"]
            SharedVolume{{"fa:fa-folder-open<br/>Shared Volume"}}
            
            App -- "6. Reads Secret" --> SharedVolume
            VaultAgent -- "5. Writes Secret" --> SharedVolume
        end
        
        VaultAgent -- "1. Auth (k8s SA)" --> Vault
        Vault -- "2. Issues Vault Token" --> VaultAgent
        VaultAgent -- "3. Requests DB Creds" --> Vault
        Vault -- "4. Issues Dynamic DB Creds" --> VaultAgent
        App -- "7. DB Connection Request" --> TerminatingGW
        TerminatingGW -- "8. Connects to DB w/ Creds" --> Database
    end
    
    classDef platform fill:#e0f2fe,stroke:#3b82f6,stroke-width:2px;
    classDef app fill:#dcfce7,stroke:#22c55e,stroke-width:2px;
    classDef external fill:#fee2e2,stroke:#ef4444,stroke-width:2px;
    
    class Vault,TerminatingGW platform;
    class App,VaultAgent,SharedVolume app;
    class Database external;


```


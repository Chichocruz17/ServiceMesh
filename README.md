# ServiceMesh

graph TD
    subgraph On-Premise OpenShift Cluster
        subgraph Control Plane
            direction TB
            subgraph "Consul Server StatefulSet"
                S1[Server 1]
                S2[Server 2]
                S3[Server 3]
            end
            S1 <--> S2
            S2 <--> S3
            S1 <--> S3
        end

        subgraph Data Plane
            direction LR
            subgraph "Worker Node 1 (DaemonSet)"
                C1[Consul Client]
                subgraph Pod A
                    App1[App Container] <--> E1[Envoy Sidecar]
                end
                C1 --> E1
            end

            subgraph "Worker Node 2 (DaemonSet)"
                C2[Consul Client]
                subgraph Pod B
                    App2[App Container] <--> E2[Envoy Sidecar]
                end
                C2 --> E2
            end
        end

        S1 -- "Distributes Config" --> C1
        S2 -- "Distributes Config" --> C2
        E1 -- "Traffic" --> E2
    end

    style Control Plane fill:#d3eaf7
    style Data Plane fill:#dae8d3 

    

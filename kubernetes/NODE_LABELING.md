# Node Labeling for Rack Awareness and Topology

This guide explains how to label GKE nodes for ClickHouse rack awareness and topology constraints.

## Overview

The ClickHouse deployment uses node labels to:
1. **Zone Awareness**: Automatically provided by GKE (`topology.kubernetes.io/zone`)
2. **Rack Awareness**: Custom label for physical rack distribution (`topology.clickhouse.com/rack`)
3. **Workload Placement**: Direct pods to appropriate nodes (`workload=clickhouse`)

## Quick Start

### 1. Label Nodes by Rack

If your nodes are distributed across physical racks, label them accordingly:

```bash
# Get all nodes
kubectl get nodes

# Label nodes by rack
kubectl label node <node-name> topology.clickhouse.com/rack=rack1
kubectl label node <node-name> topology.clickhouse.com/rack=rack2
kubectl label node <node-name> topology.clickhouse.com/rack=rack3
```

### 2. Label Nodes for ClickHouse Workload

Label nodes that should run ClickHouse pods:

```bash
kubectl label node <node-name> workload=clickhouse
```

### 3. Automated Labeling Script

Use this script to automatically label all nodes:

```bash
#!/bin/bash

# Get all nodes in the clickhouse node pool
NODES=$(kubectl get nodes -l cloud.google.com/gke-nodepool=clickhouse-clickhouse-pool -o name)

RACK_NUM=1
for NODE in $NODES; do
  NODE_NAME=$(echo $NODE | cut -d'/' -f2)
  ZONE=$(kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')

  # Assign rack based on zone and node index
  RACK="rack$RACK_NUM"

  echo "Labeling $NODE_NAME: zone=$ZONE, rack=$RACK"

  # Add rack label
  kubectl label node $NODE_NAME topology.clickhouse.com/rack=$RACK --overwrite

  # Add workload label
  kubectl label node $NODE_NAME workload=clickhouse --overwrite

  # Cycle through racks
  RACK_NUM=$((RACK_NUM % 3 + 1))
done
```

Save as `label-nodes.sh` and run:

```bash
chmod +x label-nodes.sh
./label-nodes.sh
```

## Rack Awareness Strategy

### For GKE with Multiple Zones

GKE zones typically represent different data centers. You can map racks within zones:

```bash
# Zone us-central1-a
kubectl label node gke-node-1 topology.clickhouse.com/rack=rack1
kubectl label node gke-node-2 topology.clickhouse.com/rack=rack2

# Zone us-central1-b
kubectl label node gke-node-3 topology.clickhouse.com/rack=rack3
kubectl label node gke-node-4 topology.clickhouse.com/rack=rack1

# Zone us-central1-c
kubectl label node gke-node-5 topology.clickhouse.com/rack=rack2
kubectl label node gke-node-6 topology.clickhouse.com/rack=rack3
```

### For On-Premises or Bare Metal

Label nodes based on actual physical rack location:

```bash
# Data Center 1, Rack A
kubectl label node node1 topology.clickhouse.com/rack=dc1-rack-a
kubectl label node node2 topology.clickhouse.com/rack=dc1-rack-a

# Data Center 1, Rack B
kubectl label node node3 topology.clickhouse.com/rack=dc1-rack-b
kubectl label node node4 topology.clickhouse.com/rack=dc1-rack-b

# Data Center 2, Rack A
kubectl label node node5 topology.clickhouse.com/rack=dc2-rack-a
kubectl label node node6 topology.clickhouse.com/rack=dc2-rack-a
```

## Verify Labels

Check that labels are applied correctly:

```bash
# View all node labels
kubectl get nodes --show-labels

# View specific topology labels
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
ZONE:.metadata.labels."topology\.kubernetes\.io/zone",\
RACK:.metadata.labels."topology\.clickhouse\.com/rack",\
WORKLOAD:.metadata.labels.workload

# Count nodes per rack
kubectl get nodes -l topology.clickhouse.com/rack=rack1 --no-headers | wc -l
kubectl get nodes -l topology.clickhouse.com/rack=rack2 --no-headers | wc -l
kubectl get nodes -l topology.clickhouse.com/rack=rack3 --no-headers | wc -l
```

## How Labels Affect Pod Scheduling

### Topology Spread Constraints

The ClickHouse Installation uses these constraints:

```yaml
topologySpreadConstraints:
  # Spread across zones (maxSkew: 1, DoNotSchedule)
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule

  # Spread across racks (maxSkew: 1, ScheduleAnyway)
  - maxSkew: 1
    topologyKey: topology.clickhouse.com/rack
    whenUnsatisfiable: ScheduleAnyway

  # Spread across nodes (maxSkew: 1, ScheduleAnyway)
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
```

**What this means:**
- **Zone**: Pods MUST be evenly distributed across zones (hard requirement)
- **Rack**: Pods SHOULD be evenly distributed across racks (soft preference)
- **Node**: Pods SHOULD be spread across different nodes (soft preference)

### Pod Anti-Affinity

```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname  # Never same node
  preferredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: topology.kubernetes.io/zone      # Prefer different zones
    - topologyKey: topology.clickhouse.com/rack    # Prefer different racks
```

**What this means:**
- Replicas of the same shard will NEVER be on the same node
- Replicas will PREFER to be in different zones
- Replicas will PREFER to be in different racks

## Example Deployment Scenarios

### Scenario 1: 2 Shards × 3 Replicas = 6 Pods

With 3 zones and 3 racks:

```
Zone A         Zone B         Zone C
------------------------------------
Shard 1 Rep 1  Shard 1 Rep 2  Shard 1 Rep 3
Rack 1         Rack 2         Rack 3

Shard 2 Rep 1  Shard 2 Rep 2  Shard 2 Rep 3
Rack 2         Rack 3         Rack 1
```

### Scenario 2: High Availability Distribution

For 3 zones with 6 nodes (2 per zone):

```
Zone A          Zone B          Zone C
-----------------------------------------
Node 1 (R1):    Node 3 (R1):    Node 5 (R1):
  - Shard1-Rep1   - Shard1-Rep2   - Shard1-Rep3

Node 2 (R2):    Node 4 (R2):    Node 6 (R2):
  - Shard2-Rep1   - Shard2-Rep2   - Shard2-Rep3
```

This ensures:
- Each shard has replicas in all 3 zones
- Replicas are spread across different racks
- No single point of failure

## Updating Labels

To change labels on existing nodes:

```bash
# Update rack label
kubectl label node <node-name> topology.clickhouse.com/rack=new-rack --overwrite

# Remove rack label
kubectl label node <node-name> topology.clickhouse.com/rack-
```

After updating labels, you may need to:
1. Delete and recreate ClickHouse pods for optimal redistribution
2. Or let the operator handle it during the next rolling update

## Terraform Integration

If using the Terraform GKE module, you can add node labels automatically:

Edit `terraform/modules/gke/main.tf`:

```hcl
resource "google_container_node_pool" "clickhouse_nodes" {
  # ... existing configuration ...

  node_config {
    # ... existing config ...

    labels = merge(
      var.labels,
      {
        "workload" = "clickhouse"
        "topology.clickhouse.com/rack" = "rack${count.index % 3 + 1}"
      }
    )
  }
}
```

However, GKE doesn't support custom topology keys in labels, so you'll need to apply `topology.clickhouse.com/rack` labels manually or via a DaemonSet.

## Automated Labeling with DaemonSet

Create a DaemonSet to automatically label nodes:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-labeler
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: node-labeler
  template:
    metadata:
      labels:
        app: node-labeler
    spec:
      serviceAccountName: node-labeler
      hostNetwork: true
      containers:
        - name: labeler
          image: bitnami/kubectl:latest
          command:
            - /bin/sh
            - -c
            - |
              NODE_NAME=$(cat /etc/hostname)
              ZONE=$(kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')

              # Assign rack based on zone
              case $ZONE in
                *-a) RACK="rack1" ;;
                *-b) RACK="rack2" ;;
                *-c) RACK="rack3" ;;
                *) RACK="rack1" ;;
              esac

              kubectl label node $NODE_NAME topology.clickhouse.com/rack=$RACK --overwrite
              kubectl label node $NODE_NAME workload=clickhouse --overwrite

              # Keep running
              sleep infinity
```

## Troubleshooting

### Pods not spreading correctly

```bash
# Check pod distribution
kubectl get pods -n clickhouse -o wide

# Check node labels
kubectl describe nodes | grep -A 10 Labels

# Check topology constraints
kubectl describe pod -n clickhouse <pod-name> | grep -A 20 "Topology Spread Constraints"
```

### Unschedulable pods

If pods can't be scheduled due to topology constraints:

```bash
# Check events
kubectl get events -n clickhouse --sort-by='.lastTimestamp'

# Check pod status
kubectl describe pod -n clickhouse <pod-name>
```

If you see `0/X nodes are available: Y Insufficient nodes for spreading`, you may need to:
1. Add more nodes
2. Adjust `whenUnsatisfiable` to `ScheduleAnyway` (less strict)
3. Increase `maxSkew` value

## Best Practices

1. **Consistent Labeling**: Use a consistent naming scheme for racks
2. **Document Mapping**: Keep a record of which nodes belong to which physical racks
3. **Automate**: Use scripts or DaemonSets to automatically label new nodes
4. **Validate**: Always verify pod distribution after labeling
5. **Monitor**: Set up alerts for uneven pod distribution
6. **Plan Capacity**: Ensure enough nodes in each zone/rack for desired spread

## References

- [Kubernetes Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)
- [Pod Affinity and Anti-Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity)
- [GKE Node Labels](https://cloud.google.com/kubernetes-engine/docs/how-to/creating-managing-labels)

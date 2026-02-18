# Performance

This section provides practical recommendations to improve performance for Wazuh Kubernetes deployments. Apply the controls that match your workload and environment.

## Performance drivers

- **Wazuh Indexer** is typically the main bottleneck (JVM heap, disk I/O, and CPU).
- **Wazuh Manager** load grows with the number of connected agents and event throughput.
- **Wazuh Dashboard** mainly affects interactive usage and depends on Indexer and Manager responsiveness.

For baseline resource sizing and prerequisites, see [Requirements](../requirements.md).

## Storage and persistent volumes

- Use low-latency storage for the Indexer PersistentVolumes. Performance depends heavily on disk I/O.
- Monitor disk space growth. Index data and persistent volumes can grow quickly in high-ingest environments.
- Configure appropriate `storageClassName` in the environment overlays (`envs/eks/` or `envs/local-env/`).

## Wazuh Indexer (OpenSearch)

The Indexer is typically the most resource-intensive component. Performance tuning focuses on JVM heap sizing, CPU allocation, and storage.

### JVM heap sizing

- Set the JVM heap explicitly using the `OPENSEARCH_JAVA_OPTS` environment variable in the indexer StatefulSet.
- Current default: `-Xms1g -Xmx1g` (1 GB heap)
- **Recommendations**:
  - Keep heap sizing conservative relative to available memory so the OS can cache filesystem data
  - Allocate 50% of pod memory to JVM heap, leaving the rest for OS filesystem caching
  - For production: Start with 4-8 GB heap and adjust based on monitoring
  - Oversized heap commonly degrades disk-heavy workloads due to longer GC pauses
- Ensure the Linux host meets the required `vm.max_map_count` prerequisite (set via init container in the deployment).

To adjust JVM heap size and memory allocation for the Indexer, edit the relevant configuration files:

- Update the `OPENSEARCH_JAVA_OPTS` environment variable in `wazuh/indexer_stack/wazuh-indexer/cluster/indexer-sts.yaml` or apply a Kustomize patch in the `envs/` directory.
- Modify the memory requests and limits in the resource specification within the same files or environment overlays.

Ensure that the memory limit is set appropriately to allow for both JVM heap and OS filesystem caching. Apply changes using `kubectl apply -k envs/<environment>/` and monitor performance after adjustments.

### CPU and memory allocation

The default resource allocation varies by environment:

- **Local deployment**:
  - CPU: 500m request, 1 core limit
  - Memory: 1 Gi request, 3 Gi limit
  - Replicas: 1

- **EKS deployment**:
  - CPU: 500m request, 1 core limit
  - Memory: 1 Gi request, 2 Gi limit
  - Replicas: 3

These defaults are suitable for development and testing environments with low to moderate workloads.
For production environments, adjust resource allocation based on your workload:

- Prioritize CPU availability during ingest peaks
- Higher CPU allocation improves indexing and query performance
- Allocate 50% to JVM heap (configure via `OPENSEARCH_JAVA_OPTS`)
- Reserve 50% for OS filesystem caching (improves disk I/O performance)

**How to adjust**:

Edit the environment-specific resource patches to match your requirements:

- EKS: `envs/eks/indexer-resources.yaml`
- Local: `envs/local-env/indexer-resources.yaml`

After editing, apply the changes with `kubectl apply -k envs/<environment>/`.

### Storage volume sizing

- Monitor index data growth and provision sufficient storage.
- Default PVC size: 500 Mi (development only)
- Monitor disk usage and expand PVCs before reaching 80% capacity
- Adjust storage size in the environment overlays (`indexer-resources.yaml`) and apply changes with `kubectl apply -k envs/<environment>/`.

### Indexer cluster scaling

- The default EKS deployment uses 3 indexer replicas for high availability, and only 1 replica for local deployments.
- Horizontal scaling (adding more replicas) improves:
  - Query performance (more nodes to distribute search load)
  - Indexing throughput (parallel processing)
  - Resilience (data replication across nodes)
- Update `discovery.seed_hosts` in the indexer StatefulSet (`wazuh/indexer_stack/wazuh-indexer/cluster/indexer-sts.yaml`) when adding nodes.
- Apply changes with `kubectl apply -k envs/<environment>/` and monitor cluster health and performance.

## Wazuh Manager

Manager performance depends on the number of connected agents, event processing rules, and active response configurations.

### Resource allocation

- Default resource limits are suitable for small deployments
- For production with higher event throughput, increase CPU and memory allocation
- Adjust resource requests and limits in the environment-specific resource patches:
  - EKS: `envs/eks/wazuh-master-resources.yaml` and `envs/eks/wazuh-worker-resources.yaml`
  - Local: `envs/local-env/wazuh-resources.yaml`

### Manager scaling

- The deployment includes a master node and worker nodes.
- **Master node**: Handles cluster coordination, API requests, and dashboard communication.
- **Worker nodes**: Handle agent connections and event processing.
- Scale worker nodes horizontally to distribute agent load:
  - Default: 2 worker replicas
  - If required: increase worker replicas in `wazuh/wazuh_managers/wazuh-worker-sts.yaml` and apply changes with `kubectl apply -k envs/<environment>/`.
- Ensure sufficient CPU and memory for event processing and rule evaluation.

### Storage for manager

Manager PersistentVolumes store logs, queues, and configuration.

- Default PVC size:
  - Local deployment: 500 Mi
  - EKS deployment:
    - Master node: 50 Gi
    - Worker nodes: 50 Gi

How to adjust: edit the `volumeClaimTemplates` section in the environment-specific resource patches:
    - EKS:
      - Master: `envs/eks/wazuh-master-resources.yaml`
      - Workers: `envs/eks/wazuh-worker-resources.yaml`
    - Local: Edit `envs/local-env/wazuh-resources.yaml` to add volume claim overrides
    - After editing, apply the changes with `kubectl apply -k envs/<environment>/`.

### Backpressure and queue management

- If you observe ingestion backpressure or delayed processing:
  - Validate that the manager has sufficient CPU and memory
  - Check that PersistentVolumes are not constrained by slow storage
  - Review manager logs for queue growth and connection retries
  - Consider adding more worker nodes to distribute load

## Wazuh Dashboard

- Dashboard responsiveness depends on Indexer and Manager health.
- Address Indexer/Manager resource constraints first when troubleshooting slow queries.

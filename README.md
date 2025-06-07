# K8s Manager Script Documentation

The K8s Manager script is for quickly setting up, deploying, and monitoring applications on Kubernetes with the KEDA (Kubernetes Event-Driven Autoscaling).

## Getting Started

### Prerequisites

Before diving in, make sure you have:

- A Kubernetes cluster (local or remote)
- Basic understanding of Kubernetes concepts
- Access to a terminal

## Script file ✅

[k8s-manager.sh](./k8s-manager.sh)

### Installation

Getting the script is straightforward:

```bash
# Make the script executable
chmod +x k8s-manager.sh
```

## Command Reference

The K8s Manager script comes with several commands to make your Kubernetes life easier:

Here is the overview of the script and commands - 

![Screenshot 2025-03-20 at 22.55.33.png](Documentation%201bcbd0cd3eaf804880efdce7d40b0559/Screenshot_2025-03-20_at_22.55.33.png)

### Checking and Installing kubectl

```bash
./k8s-manager.sh check-kubectl
```

This command checks if kubectl is installed on your system. If not, it automatically installs the appropriate version for your operating system (Linux, macOS, or Windows). The script detects your OS and uses the right installation method.

### Managing Kubernetes Contexts

```bash
./k8s-manager.sh context CONTEXT_NAME [path_to_kubeconfig]
```

Switch between different Kubernetes clusters or contexts with ease. This is super helpful when you're juggling multiple clusters (production, staging, development, etc.).

**Examples:**

```bash

./k8s-manager.sh context production # Switch to a context named "production"

./k8s-manager.sh context dev ~/.kube/dev-config # Use a specific kubeconfig file and switch to "dev-cluster"

```

### Installing Helm

```bash
./k8s-manager.sh install-helm
```

Helm is the package manager for Kubernetes, and you'll need it to install KEDA. This command checks if Helm is already installed. If not, it installs the latest version of Helm 3.

### Installing KEDA

```bash
./k8s-manager.sh install-keda
```

KEDA (Kubernetes Event-Driven Autoscaling) is the secret sauce that allows applications to scale based on events and metrics from various sources. This command:

1. Adds the KEDA Helm repository
2. Installs helm if the helm is not installed
3. Creates a dedicated namespace for KEDA
4. Installs KEDA using Helm
5. Waits for the KEDA operator to be ready

### Creating a Deployment

```bash
./k8s-manager.sh create-deployment
```

This interactive command helps creating a complete Kubernetes deployment with:

- A deployment resource with your container image
- A service to expose your application
- A KEDA ScaledObject for autoscaling and an HPA

The script will prompt for:

- deployment name,
- docker image,
- namespace (set to default if not provided),
- container ports (default is 80, if empty),
- CPU Request (default is 100m, if empty),
- Memory Request (default is 100m, if empty),
- CPU Limit (default is 128Mi, if empty),
- Memory Limit (default is 512Mi, if empty),
- CPU autoscaling target %(default is 70%)
- Memory autoscaling target %(default is 70%)

The deployment comes with CPU and memory-based autoscaling by default, and has a commented section for Kafka-based autoscaling that you can customize.

All configuration files are saved in the `config-files` directory with proper naming conventions, making it easy to track and version your deployments.

### Checking Deployment Health

```bash
./k8s-manager.sh check-health DEPLOYMENT_NAME
```

Need to check on your deployment? This command provides a comprehensive health check by:

1. Finding your deployment across all namespaces (no need to specify the namespace!)
2. Displaying deployment status and details
3. Showing pod status and resource usage
4. Checking service status
5. Displaying KEDA ScaledObject status and HPA information
6. Showing recent events related to your deployment
7. Listing the config files used for the deployment

This is incredibly useful for troubleshooting and monitoring your applications.

## KEDA Autoscaling

The K8s Manager script sets up deployments with KEDA autoscaling - it scales up when demand increases and scales down when things are quiet.

### CPU and Memory Scaling

By default, your deployments are configured to scale based on CPU and memory utilization:

```yaml
triggers:
- type: cpu
  metadata:
    type: Utilization
    value: "70"
# Memory trigger
- type: memory
  metadata:
    type: Utilization
    value: "70"

```

This means:

- If CPU utilization goes above 70%, KEDA will scale up the deployment
- If memory utilization goes above 70%, KEDA will also trigger scaling
- The deployment can scale from 1 to 10 pods (configurable)

### Event-Based Scaling

The script also includes a template for Kafka-based scaling (commented out by default):

```yaml
# - type: kafka
#   metadata:
#     bootstrapServers: my-cluster-kafka-bootstrap.kafka:9092
#     consumerGroup: my-group
#     topic: my-topic
#     lagThreshold: "10"

```

Uncomment and customize this section to enable scaling based on Kafka message lag. This is perfect for event-driven architectures where your application processes messages from a Kafka topic.

KEDA supports many other scalers beyond Kafka, including:

- RabbitMQ
- Redis
- Prometheus metrics
- AWS SQS/SNS
- Azure Service Bus/Event Hubs
- Google Cloud PubSub
- And many more!

## Troubleshooting

### Common Issues and Solutions

### "Error: Deployment not found"

If you see this when running check-health:

```
Error: Deployment not found with name: my-deployment in any namespace

```

Make sure:

- To spell the deployment name correctly
- The deployment was created successfully
- You have appropriate permissions to view the deployment

Try running `kubectl get deployments --all-namespaces` to see a list of all deployments.

### KEDA Installation Failures

If KEDA installation fails, check:

- That your cluster has internet access to pull the KEDA charts
- That you have permission to create resources in your cluster
- The Helm client and server versions are compatible

### Script Permissions Issues

If you see "Permission denied" errors:

```
-bash: ./k8s-manager.sh: Permission denied
```

Run this command to make the script executable:

```bash
chmod +x k8s-manager.sh
```

##

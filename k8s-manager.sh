#!/bin/bash

set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# Print with color
print_green() {
  printf "${GREEN}$1${NC}"
}

print_yellow() {
  printf "${YELLOW}$1${NC}"
}

print_red() {
  printf "${RED}$1${NC}"
}

# Function to check and install kubectl
check_kubectl() {
  print_yellow "Checking if kubectl is installed...\n"
  
  if ! command -v kubectl 2> /dev/null; then
    print_yellow "kubectl not found. Installing kubectl.\n"
    
    # Detect OS type
    OS="$(uname -s)"
    print_yellow "Detected OS: $OS \n"
    
    case "$OS" in
      Linux)
        print_yellow "Using Linux installation method\n"
        ARCH=$(uname -m)
        if [ "$ARCH" = "x86_64" ]; then
            KUBE_ARCH="amd64"
        else
            KUBE_ARCH="arm64"
        fi
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBE_ARCH}/kubectl"
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBE_ARCH}/kubectl.sha256"
        echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        ;;
      Darwin)
        print_yellow "Detected macOS system\n"
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/$(uname -m)/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        ;;
      *)
        print_red "Unsupported operating system: $OS\n"
        print_yellow "Please install kubectl manually\n"
        exit 1
        ;;
    esac
    
    if command -v kubectl &> /dev/null; then
      print_green "kubectl installed successfully!!!\n"
      printf "\n$(kubectl version --client -short)"
    else
      print_red "Failed to install kubectl. Please install it manually.\n"
      exit 1
    fi
  else
    print_green "\nkubectl is already installed!!! \n" 
    printf "\n$(kubectl version --client -short)"
  fi
}

# Function to set kubeconfig and context
context() {
  local kubeconfig="$1"
  local context_name="$2"
  # export KUBECONFIG="~/.kube/config"
  if [ -z "$kubeconfig" ]; then
    printf "No kubeconfig provided, using default $kubeconfig \n"
  else
    if [ -f "$kubeconfig" ]; then
      export KUBECONFIG="$kubeconfig"
      print_green "Using kubeconfig: $kubeconfig \n"
    else
      print_red "Kubeconfig file not found: $kubeconfig \n"
      exit 1
    fi
  fi
  
  # Before switching context, Display current context
  current_context=$(kubectl config current-context)
  print_green "Current context: $current_context \n"
  
  # Switching context if provided
  if [ -n "$context_name" ]; then
    printf "Switching to context: $context_name \n"
    
    # Check if the context exists
    if kubectl config get-contexts -o name | grep -q "^${context_name}$"; then
      kubectl config use-context "$context_name"
      print_green "Successfully switched to context: $context_name \n"
    else
      print_red "Context not found: $context_name \n"
      print_yellow "\nAvailable contexts: \n"
      kubectl config get-contexts
      exit 1
    fi
  else
    # List all the available contexts
    print_yellow "\nAvailable contexts:"
    kubectl config get-contexts
  fi
}

# Function to check if helm is already installed, if not, install Helm
install_helm() {
  print_yellow "Checking if Helm is installed.\n"
  
  if ! command -v helm 2> /dev/null; then
    print_yellow "Helm not found. Installing Helm!!\n"
    
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
    
    if command -v helm 2> /dev/null; then
      print_green "Helm installed successfully: $(helm version --short) \n"
    else
      print_red "Failed to install Helm. Please install it manually! \n"
      exit 1
    fi
  else
    print_green "Helm is already installed: $(helm version --short) \n"
  fi
}

# Function to check and install KEDA
check_keda() {
  print_yellow "Checking if KEDA is installed..\n"

  if command -v kubectl 2> /dev/null; then
  
    # Check if KEDA namespace exists
    if kubectl get namespace keda 2> /dev/null; then
      # Check if KEDA operator is running
      if kubectl get deployment keda-operator -n keda &> /dev/null; then
        print_green "KEDA is already installed and running.\n"
        return
      fi
    else
      print_yellow "KEDA namespace not found.\n"
    fi
    
    print_yellow "KEDA not found or not running. Installing KEDA...\n"

    install_helm
    
    # Add KEDA Helm repository
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    
    # Create KEDA namespace
    kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -
    
    # Install KEDA
    helm install keda kedacore/keda --namespace keda
    
    # Wait for KEDA operator to be ready
    print_yellow "Waiting for KEDA operator to be ready\n"
    kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda
    
    if [ $? -eq 0 ]; then
      print_green "KEDA installed successfully!\n"
      kubectl get deployment -n keda
    else
      print_red "Failed to install KEDA or timeout waiting for KEDA operator.\n"
      exit 1
    fi

  else
    print_red "\nkubectl not found!\n"
    print_yellow "\nFollow the below commands to proceed with installing KEDA.\n"
    printf "1. Please install kubectl, use : $0 check-kubectl\n"
    printf "2. Set cluster context and kubeconfig,  use : $0 context CONTEXT_NAME [path_to_kubeconfig]\n"
    printf "3. Lastly, run this script again, use : $0 install-keda\n"
    exit 1
  fi
}

# Function to install and enable metrics server
install_metrics_server() {
  print_yellow "Checking if Metrics Server is installed\n"
  
  if kubectl get deployment metrics-server -n kube-system 2>/dev/null; then
    print_green "Metrics Server is already installed!\n"
    kubectl get deployment metrics-server -n kube-system
    return 0
  fi
  
  print_yellow "Metrics Server not found. Installing Metrics Server\n"
  
  install_helm
  
  print_yellow "Adding metrics-server Helm repository\n"
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
  helm repo update
  
  print_yellow "Installing Metrics Server...\n"
  helm install metrics-server metrics-server/metrics-server \
    --namespace kube-system \
    --set args="{--kubelet-insecure-tls}"
  
  print_yellow "Waiting for Metrics Server to be ready...\n"
  kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system
  
  if [ $? -eq 0 ]; then
    print_green "Metrics Server installed successfully!\n"
    kubectl get deployment metrics-server -n kube-system
    
    print_yellow "Waiting for metrics API to be available\n"
    sleep 30
    
    if kubectl top nodes 2>/dev/null; then
      print_green "Metrics API is working! Here are the node metrics:\n"
      kubectl top nodes
    else
      print_yellow "Metrics API is not yet responding. It may take a few minutes to become available.\n"
      print_yellow "Check its status later with: kubectl top nodes\n"
    fi
  else
    print_red "Failed to install Metrics Server or timeout waiting for deployment.\n"
    exit 1
  fi
}

# Function to create a deployment, service, and HPA with KEDA
create_deployment() {
  print_yellow "Please provide the necessary details to create a deployment.\n"
  
  # Create config-files directory if it doesn't exist
  mkdir -p config-files
  
  # Deployment name validation function
  validate_kubernetes_name() {
    local name="$1"
    local field="$2"
    if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
      print_red "Error: Invalid $field name: $name"
      print_yellow "$field name must consist of lowercase alphanumeric characters or '-', and must start and end with an alphanumeric character."
      return 1
    fi
    return 0
  }

  # Docker image validation function
  validate_docker_image() {
    local image="$1"
    if [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*(/[a-zA-Z0-9][a-zA-Z0-9_.-]*)*:[a-zA-Z0-9_.-]*$ ]] && [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*(/[a-zA-Z0-9][a-zA-Z0-9_.-]*)*$ ]]; then
      print_red "Error: Invalid Docker image format: $image"
      print_yellow "Docker image should be in format: name:tag or name/path:tag"
      return 1
    fi
    return 0
  }

  # Numeric validation function
  validate_numeric() {
    local value="$1"
    local field="$2"
    local min="$3"
    local max="$4"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
      print_red "Error: $field must be a number"
      return 1
    fi
    if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
      print_red "Error: $field must be between $min and $max"
      return 1
    fi
    return 0
  }

  # Resource validation function
  validate_resource() {
    local value="$1"
    local field="$2"
    if [[ ! "$value" =~ ^[0-9]+[m]?$ ]] && [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      print_red "Error: Invalid $field format: $value"
      print_yellow "$field should be in format: 100m, 0.1, 1, etc."
      return 1
    fi
    return 0
  }

  # Memory validation function
  validate_memory() {
    local value="$1"
    local field="$2"
    if [[ ! "$value" =~ ^[0-9]+[KMGTPEkmgtpe]i?$ ]] && [[ ! "$value" =~ ^[0-9]+$ ]]; then
      print_red "Error: Invalid $field format: $value"
      print_yellow "$field should be in format: 128Mi, 1Gi, 512Ki, etc."
      return 1
    fi
    return 0
  }

  # Convert memory to bytes for comparison
  memory_to_bytes() {
    local value="$1"
    local number unit
    
    if [[ "$value" =~ ^([0-9]+)([KMGTPEkmgtpe]i?)$ ]]; then
      number="${BASH_REMATCH[1]}"
      unit="${BASH_REMATCH[2]}"
      
      case "$unit" in
        [Kk]i|[Kk]) number=$((number * 1024)) ;;
        [Mm]i|[Mm]) number=$((number * 1024 * 1024)) ;;
        [Gg]i|[Gg]) number=$((number * 1024 * 1024 * 1024)) ;;
        [Tt]i|[Tt]) number=$((number * 1024 * 1024 * 1024 * 1024)) ;;
        [Pp]i|[Pp]) number=$((number * 1024 * 1024 * 1024 * 1024 * 1024)) ;;
        [Ee]i|[Ee]) number=$((number * 1024 * 1024 * 1024 * 1024 * 1024 * 1024)) ;;
      esac
      
      echo "$number"
    else
      echo "$value"
    fi
  }

  # Validate percentage (for autoscaling targets)
  validate_percentage() {
    local value="$1"
    local field="$2"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
      print_red "Error: $field must be a number"
      return 1
    fi
    if [[ "$value" -lt 1 || "$value" -gt 100 ]]; then
      print_red "Error: $field must be between 1 and 100"
      return 1
    fi
    return 0
  }

  # Get and validate deployment name
  while true; do
    read -p "Enter deployment name: " DEPLOYMENT_NAME
    if validate_kubernetes_name "$DEPLOYMENT_NAME" "Deployment"; then
      break
    fi
  done

  # Get and validate Docker image
  while true; do
    read -p "Enter Docker image (e.g., nginx:latest): " DOCKER_IMAGE
    if validate_docker_image "$DOCKER_IMAGE"; then
      break
    fi
  done

  # Get and validate namespace
  while true; do
    read -p "Enter namespace (default if empty): " NAMESPACE
    NAMESPACE=${NAMESPACE:-default}
    if validate_kubernetes_name "$NAMESPACE" "Namespace"; then
      break
    fi
  done

  # Modified numeric validation function for ports
  validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      print_red "Error: Port must be a number"
      return 1
    fi
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
      print_red "Error: Port must be between 1 and 65535"
      return 1
    fi
    return 0
  }

  # Validate multiple ports (comma or space separated)
  validate_ports() {
    local ports="$1"
    # Replace commas with spaces for easier parsing
    ports="${ports//,/ }"
    
    for port in $ports; do
      if ! validate_port "$port"; then
        return 1
      fi
    done
    return 0
  }

  # Get and validate container ports (now multiple)
  while true; do
    read -p "Enter container port(s) (comma or space separated, e.g., 80,8080): " CONTAINER_PORTS
    CONTAINER_PORTS=${CONTAINER_PORTS:-80}
    if validate_ports "$CONTAINER_PORTS"; then
      break
    fi
  done

  # Get and validate CPU request
  while true; do
    read -p "Enter CPU request (e.g., 100m): " CPU_REQUEST
    CPU_REQUEST=${CPU_REQUEST:-100m}
    if validate_resource "$CPU_REQUEST" "CPU request"; then
      break
    fi
  done

  # Get and validate Memory request
  while true; do
    read -p "Enter Memory request (e.g., 128Mi): " MEMORY_REQUEST
    MEMORY_REQUEST=${MEMORY_REQUEST:-128Mi}
    if validate_memory "$MEMORY_REQUEST" "Memory request"; then
      break
    fi
  done

  # Get and validate CPU limit
  while true; do
    read -p "Enter CPU limit (e.g., 500m): " CPU_LIMIT
    CPU_LIMIT=${CPU_LIMIT:-500m}
    if validate_resource "$CPU_LIMIT" "CPU limit"; then
      break
    fi
  done

  # Get and validate Memory limit
  while true; do
    read -p "Enter Memory limit (e.g., 512Mi): " MEMORY_LIMIT
    MEMORY_LIMIT=${MEMORY_LIMIT:-512Mi}
    if validate_memory "$MEMORY_LIMIT" "Memory limit"; then
      break
    fi
  done

  # Get and validate CPU autoscaling target
  while true; do
    read -p "Enter CPU autoscaling target percentage (1-100, default: 70): " CPU_TARGET
    CPU_TARGET=${CPU_TARGET:-70}
    if validate_percentage "$CPU_TARGET" "CPU target"; then
      break
    fi
  done

  # Get and validate Memory autoscaling target
  while true; do
    read -p "Enter Memory autoscaling target percentage (1-100, default: 70): " MEMORY_TARGET
    MEMORY_TARGET=${MEMORY_TARGET:-70}
    if validate_percentage "$MEMORY_TARGET" "Memory target"; then
      break
    fi
  done

  # Get and validate service type
  while true; do
    print_yellow "\nSelect service type:\n"
    print_yellow "1. ClusterIP (default, only accessible within the cluster)\n"
    print_yellow "2. NodePort (exposes the service on each node's IP at a static port)\n"
    print_yellow "3. LoadBalancer (exposes the service externally using a cloud provider's load balancer)\n"
    read -p "Enter your choice (1-3, default: 1): " SERVICE_TYPE_CHOICE
    SERVICE_TYPE_CHOICE=${SERVICE_TYPE_CHOICE:-1}
    
    case "$SERVICE_TYPE_CHOICE" in
      1)
        SERVICE_TYPE="ClusterIP"
        break
        ;;
      2)
        SERVICE_TYPE="NodePort"
        break
        ;;
      3)
        SERVICE_TYPE="LoadBalancer"
        break
        ;;
      *)
        print_red "Invalid choice. Please enter 1, 2, or 3.\n"
        ;;
    esac
  done

  # Validate that limits are greater than or equal to requests
  # For CPU
  if [[ "$CPU_REQUEST" =~ ([0-9]+)m$ ]] && [[ "$CPU_LIMIT" =~ ([0-9]+)m$ ]]; then
    request_value="${BASH_REMATCH[1]}"
    limit_value="${BASH_REMATCH[1]}"
    if [[ "$request_value" -gt "$limit_value" ]]; then
      print_red "Error: CPU request ($CPU_REQUEST) cannot be greater than CPU limit ($CPU_LIMIT)"
      print_yellow "Please restart deployment creation with valid values"
      return 1
    fi
  fi

  # For Memory - convert to bytes then compare
  mem_request_bytes=$(memory_to_bytes "$MEMORY_REQUEST")
  mem_limit_bytes=$(memory_to_bytes "$MEMORY_LIMIT")
  
  if [[ "$mem_request_bytes" -gt "$mem_limit_bytes" ]]; then
    print_red "Error: Memory request ($MEMORY_REQUEST) cannot be greater than Memory limit ($MEMORY_LIMIT)"
    print_yellow "Please restart deployment creation with valid values"
    return 1
  fi
  
  # Create namespace if it doesn't exist
  kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  
  # File names with proper naming convention
  DEPLOYMENT_FILE="config-files/${DEPLOYMENT_NAME}-deployment.yaml"
  SERVICE_FILE="config-files/${DEPLOYMENT_NAME}-service.yaml"
  SCALEDOBJECT_FILE="config-files/${DEPLOYMENT_NAME}-scaledobject.yaml"
  
  # Create deployment YAML file with support for multiple ports
  cat > "${DEPLOYMENT_FILE}" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${DEPLOYMENT_NAME}
  template:
    metadata:
      labels:
        app: ${DEPLOYMENT_NAME}
    spec:
      containers:
      - name: ${DEPLOYMENT_NAME}
        image: ${DOCKER_IMAGE}
        ports:
EOF

  # Add each port to the deployment file
  # Replace commas with spaces for easier parsing
  PORTS_ARRAY="${CONTAINER_PORTS//,/ }"
  for port in $PORTS_ARRAY; do
    cat >> "${DEPLOYMENT_FILE}" <<EOF
        - containerPort: ${port}
EOF
  done

  # Complete the deployment file
  cat >> "${DEPLOYMENT_FILE}" <<EOF
        resources:
          requests:
            cpu: ${CPU_REQUEST}
            memory: ${MEMORY_REQUEST}
          limits:
            cpu: ${CPU_LIMIT}
            memory: ${MEMORY_LIMIT}
EOF

  # Create service YAML file with support for multiple ports
  cat > "${SERVICE_FILE}" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${DEPLOYMENT_NAME}-service
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
spec:
  selector:
    app: ${DEPLOYMENT_NAME}
  ports:
EOF

  # Add each port to the service file
  MAIN_PORT=$(echo $PORTS_ARRAY | awk '{print $1}')  # Use the first port as the main one
  for port in $PORTS_ARRAY; do
    cat >> "${SERVICE_FILE}" <<EOF
  - port: ${port}
    targetPort: ${port}
    name: port-${port}
EOF
  done

  # Complete the service file with the selected service type
  cat >> "${SERVICE_FILE}" <<EOF
  type: ${SERVICE_TYPE}
EOF

  # # Get Kafka configuration parameters
  # print_yellow "\nConfiguring Kafka event source for KEDA autoscaling:"
  
  
  # Create KEDA ScaledObject YAML file with both CPU/memory and Kafka triggers
  cat > "${SCALEDOBJECT_FILE}" <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: ${DEPLOYMENT_NAME}-scaledobject
  namespace: ${NAMESPACE}
  labels:
    app: ${DEPLOYMENT_NAME}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    name: ${DEPLOYMENT_NAME}
    kind: Deployment
  minReplicaCount: 1
  maxReplicaCount: 10
  advanced:
    horizontalPodAutoscalerConfig:                   
      name: keda-hpa-${DEPLOYMENT_NAME}               
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
          - type: Percent
            value: 100
            periodSeconds: 15
        scaleUp:
          stabilizationWindowSeconds: 0
          policies:
          - type: Percent
            value: 100
            periodSeconds: 15
          - type: Pods
            value: 4
            periodSeconds: 15
          selectPolicy: Max
  triggers:
  - type: cpu
    metadata:
      type: Utilization
      value: "${CPU_TARGET}"
  - type: memory
    metadata:
      type: Utilization
      value: "${MEMORY_TARGET}"
  # - type: kafka
  #   metadata:
  #     bootstrapServers: kafka.svc:9092
  #     consumerGroup: my-group
  #     topic: test-topic
  #     lagThreshold: "10"
EOF

  # Apply deployment, service, and ScaledObject
  print_yellow "Applying deployment - "
  kubectl apply -f "${DEPLOYMENT_FILE}"
  
  print_yellow "Applying service - "
  kubectl apply -f "${SERVICE_FILE}"
  
  print_yellow "Applying KEDA ScaledObject - "
  kubectl apply -f "${SCALEDOBJECT_FILE}"
   
  # Display deployment details
  print_green "\n Deployment created successfully!!\n"
  print_green "Deployment Name: ${DEPLOYMENT_NAME}\n"
  print_green "Namespace: ${NAMESPACE}\n"
  
  print_yellow "\nDeployment details:\n"
  kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}
  
  print_yellow "\nService details:\n"
  kubectl get service ${DEPLOYMENT_NAME}-service -n ${NAMESPACE}
  
  print_yellow "\nKEDA ScaledObject details:\n"
  kubectl get scaledobject ${DEPLOYMENT_NAME}-scaledobject -n ${NAMESPACE}
  
  print_green "\nYAML files saved to:\n"
  print_green "- ${DEPLOYMENT_FILE}\n"
  print_green "- ${SERVICE_FILE}\n"
  print_green "- ${SCALEDOBJECT_FILE}\n"

  # Wait for KEDA operator to be ready
  print_yellow "\nWaiting for Deployment to be ready.\n"
  kubectl wait --for=condition=available --timeout=300s deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE}
  kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}
  print_green "\n Deployment is ready!!!\n"
  
  # Display how to check deployment health
  print_green "\nTo check deployment health, run:"
  print_green "./$(basename $0) check-health ${DEPLOYMENT_NAME}\n"
}

# Function to check deployment health
check_health() {
  local deployment_name="$1"
  
  if [ -z "$deployment_name" ]; then
    print_red "\nNo deployment name provided.\n"
    print_yellow "Usage: ./$(basename $0) check-health DEPLOYMENT_NAME \n"
    exit 1
  fi
  
  # Get all namespaces
  NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')
  FOUND=false
  
  # Search for deployment by name in each namespace
  for ns in $NAMESPACES; do
    if kubectl get deployment ${deployment_name} -n ${ns} &>/dev/null; then
      NAMESPACE=$ns
      DEPLOYMENT_NAME=${deployment_name}
      print_green "Found deployment: ${DEPLOYMENT_NAME} in namespace: ${NAMESPACE} \n"
      FOUND=true
      break
    fi
  done
  
  # If not found, exit with error
  if [ "$FOUND" = false ]; then
    print_red "\nError: Deployment not found with name: ${deployment_name} in any namespace\n"
    print_yellow "\nAvailable deployments across all namespaces: \n"
    kubectl get deployments --all-namespaces
    exit 1
  fi
  
  # Check deployment status
  print_yellow "\nDeployment Status:\n"
  kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE}
  
  # Check pod status
  print_yellow "\nPod Status:\n"
  kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME} -o wide
  
  # Check service status
  print_yellow "\nService Status:\n"
  kubectl get service ${DEPLOYMENT_NAME}-service -n ${NAMESPACE} 2>/dev/null || echo "No service found for ${DEPLOYMENT_NAME}"
  
  # Check pod metrics if metrics server is available
  print_yellow "\nResource Usage:\n"
  if kubectl get apiservice v1beta1.metrics.k8s.io &>/dev/null; then
    kubectl top pods -n ${NAMESPACE} | grep ${DEPLOYMENT_NAME} || echo "\nNo metrics found for ${DEPLOYMENT_NAME} pods\n"
  else
    print_yellow "Metrics server not available. Cannot retrieve resource usage.\n"
  fi
  
  # Check KEDA ScaledObject status if it exists
  print_yellow "\nKEDA ScaledObject Status:\n"
  kubectl get scaledobject ${DEPLOYMENT_NAME}-scaledobject -n ${NAMESPACE} 2>/dev/null || echo "No service found for ${DEPLOYMENT_NAME}"

  print_yellow "\nHPA Status:\n"
  kubectl get hpa keda-hpa-${DEPLOYMENT_NAME}-scaledobject -n ${NAMESPACE} 2>/dev/null  || echo "No HPA found for ${DEPLOYMENT_NAME}"

  # Check if there are any events related to the deployment
  print_yellow "\nRecent Events:\n"
  kubectl get events -n ${NAMESPACE} --field-selector involvedObject.name=${DEPLOYMENT_NAME} --sort-by='.lastTimestamp' | tail -n 10
  
  # Show the YAML files if they exist in config-files directory
  print_yellow "\nConfig Files:\n"
  if [ -f "config-files/${DEPLOYMENT_NAME}-deployment.yaml" ]; then
    print_green "- config-files/${DEPLOYMENT_NAME}-deployment.yaml\n"
    print_green "- config-files/${DEPLOYMENT_NAME}-service.yaml\n"
    print_green "- config-files/${DEPLOYMENT_NAME}-scaledobject.yaml\n"
  else
    print_yellow "\nNo config files found in config-files directory.\n"
  fi
}

# Main function
main() {
  case "$1" in
    check-kubectl)
      check_kubectl
      # context "$2"
      ;;
    
    context)
      if [ -z "$2" ]; then
        print_red "No context specified.\n"
        print_yellow "\n Command usage: $0 context CONTEXT_NAME [path_to_kubeconfig]"
        exit 1
      fi
      context "$3" "$2"  # $3 is optional kubeconfig, $2 is required context
      ;;
    
    install-helm)
      install_helm
      ;;

    install-keda)
      check_keda
      print_green "KEDA Setup completed successfully!"
      ;;
      
    install-metrics-server)
      install_metrics_server
      ;;

    create-deployment)
      create_deployment
      ;;

    check-health)
      check_health "$2"
      ;;

    setup)
      check_kubectl
      context "$2"
      install_helm
      check_keda
      install_metrics_server
      print_green "Setup completed successfully!"
      create_deployment
      ;;
    *)

      echo "Usage: $0 {check-kubectl|context|install-helm|install-keda|install-metrics-server|create-deployment|check-health|setup} [options]"
      echo
      echo "Commands:"
      echo "  check-kubectl [path_to_kubeconfig]    - Setup kubectl and show contexts"
      echo "  context CONTEXT [path_to_kubeconfig]  - Switch to a different kubectl context"
      echo "  install-helm                          - Install Helm"
      echo "  install-keda                          - Install KEDA"
      echo "  install-metrics-server                - Install Kubernetes Metrics Server"
      echo "  create-deployment                     - Create a new deployment with service and KEDA scaling"
      echo "  check-health DEPLOYMENT_NAME          - Check health status of a deployment"
      echo "  setup [path_to_kubeconfig]            - Setup kubectl, Helm, KEDA, and create deployment"
      ;;
  esac
}

# Execute main function
main "$@"
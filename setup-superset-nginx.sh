#!/bin/bash
set -e

echo "Starting Apache Superset installation..."

## Step 1: Add Superset Helm repository
echo -e "\n[1/6] Adding Superset Helm repository..."
helm repo add superset https://apache.github.io/superset
helm repo update

## Step 2: Create Superset namespace
echo -e "\n[2/6] Creating Kubernetes namespace for Superset..."
kubectl create namespace superset || echo "Namespace 'superset' already exists"

## Step 3: Create values.yaml configuration file
echo -e "\n[3/6] Creating Superset configuration values.yaml..."
cat > /tmp/superset-values.yaml <<EOF
namespace: superset
service:
  type: NodePort
  port: 8088
  targetPort: http
  nodePort:
    http: 30037  # <-- Your desired NodePort
# Database configuration
postgresql:
  postgresqlUsername: supersetpostgres
  postgresqlPassword: SuperPGadmin@2024 # <-- Your desired Password
  postgresqlDatabase: superset
configOverrides:
  secret: |
    SECRET_KEY = '"EueUQ8aak53Fw62zQTK1bnnNByl38tuDf+pV5g00YQOvwrhc/Nm+sKNH"'
bootstrapScript: |
  #!/bin/bash
  
  # Install system-level dependencies
  apt-get update && apt-get install -y \
    python3-dev \
    libpq-dev \
    default-libmysqlclient-dev \
    build-essential \
    pkg-config
    
  # Install required Python packages - Your desired Pythom Module as needed
  pip install \
    psycopg2-binary==2.9.9 \   
    sqlalchemy==1.4.48 \
    flask-appbuilder==4.5.0 \
    marshmallow-sqlalchemy==0.28.2 \
    authlib \
    mysqlclient \
    clickhouse-connect \
    clickhouse-driver>=0.2.0 \
    clickhouse-sqlalchemy>=0.1.6

  # Create bootstrap file if it doesn't exist
  if [ ! -f ~/bootstrap ]; then
    echo "Running Superset with uid {{ .Values.runAsUser }}" > ~/bootstrap
  fi
EOF

## Step 4: Install Superset using Helm
echo -e "\n[4/6] Installing Superset with Helm..."
helm upgrade --install superset superset/superset \
  -n superset \
  -f /tmp/superset-values.yaml

## Step 5: Create Nginx reverse proxy
echo -e "\n[5/6] Setting up Nginx reverse proxy..."
kubectl create namespace nginx --dry-run=client -o yaml | kubectl apply -f -
cat > /tmp/nginx-proxy.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-reverse-proxy
  namespace: nginx
  labels:
    app: nginx-reverse-proxy
spec:
  hostNetwork: true
  containers:
    - name: nginx
      image: nginx:alpine
      ports:
        - containerPort: 80
          hostPort: 80
      volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
  volumes:
    - name: nginx-config
      configMap:
        name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx
data:
  default.conf: |
    server {
      listen 80;
      location / {
        proxy_pass http://127.0.0.1:30037;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      }
    }

EOF
kubectl apply -f /tmp/nginx-proxy.yaml

## Step 6: Verify installation
echo -e "\n[6/6] Verifying installation..."
echo "Waiting for pods to be ready..."
sleep 10  # Give some time for pods to initialize

echo -e "\nChecking all pods status:"
kubectl get pods -A

echo -e "\nSuperset installation complete!"
echo "You can access Superset at:"
echo " - Direct NodePort: http://<your-server-ip>:30037"
echo " - Through Nginx: http://<your-server-ip>"
root@ubuntu-1cpu-2gb-sg-sin1:/home/superset-k8s-deployment# cat setup-superset-nginx.sh 
#!/bin/bash
set -e

echo "Starting Apache Superset installation..."

## Step 1: Add Superset Helm repository
echo -e "\n[1/6] Adding Superset Helm repository..."
helm repo add superset https://apache.github.io/superset
helm repo update

## Step 2: Create Superset namespace
echo -e "\n[2/6] Creating Kubernetes namespace for Superset..."
kubectl create namespace superset || echo "Namespace 'superset' already exists"

## Step 3: Create values.yaml configuration file
echo -e "\n[3/6] Creating Superset configuration values.yaml..."
cat > /tmp/superset-values.yaml <<EOF
namespace: superset
service:
  type: NodePort
  port: 8088
  targetPort: http
  nodePort:
    http: 30037  # <-- Your desired NodePort
# Database configuration
postgresql:
  postgresqlUsername: supersetpostgres
  postgresqlPassword: SuperPGadmin@2024
  postgresqlDatabase: superset
configOverrides:
  secret: |
    SECRET_KEY = '"EueUQ8aak53Fw62zQTK1bnnNByl38tuDf+pV5g00YQOvwrhc/Nm+sKNH"'
bootstrapScript: |
  #!/bin/bash
  
  # Install system-level dependencies
  apt-get update && apt-get install -y \\
    python3-dev \\
    default-libmysqlclient-dev \\
    build-essential \\
    pkg-config
  # Install required Python packages
  pip install \\
    sqlalchemy==1.4.48 \\
    flask-appbuilder==4.5.0 \\
    marshmallow-sqlalchemy==0.28.2 \\
    authlib \\
    psycopg2-binary \\
    mysqlclient \\
    clickhouse-connect \\
    clickhouse-driver>=0.2.0 \\
    clickhouse-sqlalchemy>=0.1.6
  # Create bootstrap file if it doesn't exist
  if [ ! -f ~/bootstrap ]; then
    echo "Running Superset with uid {{ .Values.runAsUser }}" > ~/bootstrap
  fi
EOF

## Step 4: Install Superset using Helm
echo -e "\n[4/6] Installing Superset with Helm..."
helm upgrade --install superset superset/superset \
  -n superset \
  -f /tmp/superset-values.yaml

## Step 5: Create Nginx reverse proxy
echo -e "\n[5/6] Setting up Nginx reverse proxy..."
kubectl create namespace nginx --dry-run=client -o yaml | kubectl apply -f -
cat > /tmp/nginx-proxy.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-reverse-proxy
  namespace: nginx
  labels:
    app: nginx-reverse-proxy
spec:
  hostNetwork: true
  containers:
    - name: nginx
      image: nginx:alpine
      ports:
        - containerPort: 80
          hostPort: 80
      volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
  volumes:
    - name: nginx-config
      configMap:
        name: nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx
data:
  default.conf: |
    server {
      listen 80;
      location / {
        proxy_pass http://127.0.0.1:30037;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      }
    }

EOF
kubectl apply -f /tmp/nginx-proxy.yaml

## Step 6: Verify installation
echo -e "\n[6/6] Verifying installation..."
echo "Waiting for pods to be ready..."
sleep 10  # Give some time for pods to initialize

echo -e "\nChecking all pods status:"
kubectl get pods -A

echo -e "\nSuperset installation complete!"
echo "You can access Superset at:"
echo " - Direct NodePort: http://<your-server-ip>:30037"
echo " - Through Nginx: http://<your-server-ip>"

# Local Kubernetes GitOps Demo

A local multi-node Kubernetes environment deployed with k3d, Terraform, Argo CD and Helm.

The project contains a frontend, a backend API, MySQL and an automated database backup CronJob.

## Architecture

```text
Windows / WSL2
└── Docker Desktop
    └── k3d cluster
        ├── 1 server node
        ├── 2 agent nodes
        ├── Traefik
        ├── Argo CD
        │   ├── applications-root
        │   │   └── demo-stack
        │   └── infrastructure-root
        │       ├── mysql
        │       └── mysql-backup
        └── demo namespace
            ├── frontend
            ├── backend
            ├── MySQL
            ├── MySQL data PVC
            └── backup PVC
```

Terraform installs Argo CD and creates two root Argo CD Applications:

- `applications-root` monitors the `applications/` directory.
- `infrastructure-root` monitors the `infrastructure/` directory.

The root Applications create three child Applications:

- `demo-stack`
- `mysql`
- `mysql-backup`

## Repository structure

```text
.
├── applications
│   ├── demo-stack
│   ├── src
│   │   ├── backend
│   │   └── frontend
│   ├── templates
│   ├── Chart.yaml
│   └── values.yaml
├── cluster
│   ├── create-cluster.sh
│   └── delete-cluster.sh
├── infrastructure
│   ├── backup
│   ├── mysql
│   ├── templates
│   ├── Chart.yaml
│   └── values.yaml
└── terraform
    ├── applications.tf
    ├── main.tf
    ├── outputs.tf
    ├── providers.tf
    ├── variables.tf
    └── versions.tf
```

## Components

| Component | Implementation |
|---|---|
| Kubernetes | k3d with K3s |
| Cluster topology | 1 server and 2 agents |
| GitOps | Argo CD |
| Infrastructure bootstrap | Terraform |
| Application packaging | Helm |
| Ingress | Traefik |
| Database | MySQL using the Bitnami Helm chart |
| Storage | K3s local-path provisioner |
| Backups | Kubernetes CronJob and separate PVC |
| Frontend image | `ivanbabenko7/devops-demo-frontend:v1.0.0` |
| Backend image | `ivanbabenko7/devops-demo-backend:v1.0.0` |

## Local environment

The environment was tested on Windows 11 with WSL2, Ubuntu and Docker Desktop.

### WSL2

Run PowerShell as Administrator:

```powershell
wsl --install -d Ubuntu
wsl --set-default-version 2
```

Restart Windows when requested.

Verify the installation:

```powershell
wsl --status
wsl -l -v
```

The Ubuntu distribution must use WSL version 2.

### Docker Desktop

Install Docker Desktop and enable:

```text
Settings
└── Resources
    └── WSL Integration
        ├── Enable integration with my default WSL distro
        └── Ubuntu
```

The built-in Docker Desktop Kubernetes cluster is not required.

Verify Docker from Ubuntu:

```bash
docker version
docker run --rm hello-world
```

Do not install a separate Docker daemon inside Ubuntu when Docker Desktop WSL integration is used.

## Required tools

The following versions were used:

```text
kubectl   v1.36.2
Helm      v3.21.3
Terraform v1.15.8
k3d       v5.9.0
```

Install the base packages:

```bash
sudo apt update

sudo apt install -y \
  ca-certificates \
  curl \
  wget \
  unzip \
  jq \
  git \
  tree \
  openssl \
  dos2unix \
  shellcheck \
  python3 \
  python3-yaml
```

Install kubectl:

```bash
KUBECTL_VERSION="v1.36.2"

curl -fsSLo /tmp/kubectl \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

sudo install -m 0755 \
  /tmp/kubectl \
  /usr/local/bin/kubectl

rm -f /tmp/kubectl
```

Install Helm:

```bash
HELM_VERSION="v3.21.3"

curl -fsSLo /tmp/helm.tar.gz \
  "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"

tar -xzf /tmp/helm.tar.gz -C /tmp

sudo install -m 0755 \
  /tmp/linux-amd64/helm \
  /usr/local/bin/helm

rm -rf /tmp/linux-amd64 /tmp/helm.tar.gz
```

Install Terraform:

```bash
TERRAFORM_VERSION="1.15.8"

curl -fsSLo /tmp/terraform.zip \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

rm -rf /tmp/terraform-install
mkdir -p /tmp/terraform-install

unzip -q \
  /tmp/terraform.zip \
  -d /tmp/terraform-install

sudo install -m 0755 \
  /tmp/terraform-install/terraform \
  /usr/local/bin/terraform

rm -rf /tmp/terraform-install /tmp/terraform.zip
```

Install k3d:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \
  | TAG=v5.9.0 bash
```

Verify the tools:

```bash
docker version
kubectl version --client
helm version --short
terraform version
k3d version
```

## Clone the repository

```bash
mkdir -p ~/work
cd ~/work

git clone \
  https://github.com/ivanbabenko7/devops-gitops-demo.git

cd devops-gitops-demo
```

## Create the cluster

Make sure Docker Desktop is running.

```bash
./cluster/create-cluster.sh
```

Verify the context and nodes:

```bash
kubectl config current-context
kubectl get nodes -o wide
k3d cluster list
```

Expected topology:

```text
k3d-devops-demo-server-0    control-plane
k3d-devops-demo-agent-0     worker
k3d-devops-demo-agent-1     worker
```

The application ingress is exposed through:

```text
http://localhost:8080
```

## Configure Terraform variables

Create two random passwords:

```bash
ROOT_PASSWORD="$(openssl rand -hex 24)"
APP_PASSWORD="$(openssl rand -hex 24)"

while [[ "${ROOT_PASSWORD}" == "${APP_PASSWORD}" ]]; do
  APP_PASSWORD="$(openssl rand -hex 24)"
done
```

Create the local Terraform variables file:

```bash
umask 077

cat > terraform/terraform.tfvars <<TFVARS_EOF
git_repo_url = "https://github.com/ivanbabenko7/devops-gitops-demo.git"

mysql_root_password = "${ROOT_PASSWORD}"
mysql_app_password  = "${APP_PASSWORD}"
TFVARS_EOF

chmod 600 terraform/terraform.tfvars

unset ROOT_PASSWORD
unset APP_PASSWORD
```

The file is excluded by `.gitignore` and must not be committed.

## Deploy with Terraform

Initialize and validate the configuration:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

Review the plan:

```bash
terraform -chdir=terraform plan
```

Apply the configuration:

```bash
terraform -chdir=terraform apply
```

Confirm the apply when Terraform asks for approval.

Terraform creates:

```text
helm_release.argocd
kubectl_manifest.root_application["applications"]
kubectl_manifest.root_application["infrastructure"]
kubernetes_namespace_v1.workloads
kubernetes_secret_v1.mysql_auth
```

Verify the Terraform state:

```bash
terraform -chdir=terraform state list
```

A second plan should report no changes:

```bash
terraform -chdir=terraform plan
```

## Verify Argo CD

Wait for Argo CD:

```bash
kubectl -n argocd wait \
  --for=condition=Ready \
  pod \
  --all \
  --timeout=600s
```

Check the Applications:

```bash
kubectl -n argocd get applications \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Expected result:

```text
applications-root     Synced   Healthy
demo-stack            Synced   Healthy
infrastructure-root   Synced   Healthy
mysql                 Synced   Healthy
mysql-backup          Synced   Healthy
```

### Argo CD UI

Start a port-forward:

```bash
kubectl -n argocd \
  port-forward \
  svc/argocd-server \
  8081:80
```

Open:

```text
http://localhost:8081
```

Username:

```text
admin
```

Get the initial password:

```bash
kubectl -n argocd \
  get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' \
  | base64 -d

echo
```

## Verify application resources

```bash
kubectl -n demo get \
  pods,pvc,services,ingress,cronjob,jobs \
  -o wide
```

Expected running workloads:

```text
2 frontend pods
2 backend pods
1 MySQL pod
```

Expected PVCs:

```text
data-mysql-0
mysql-backups
```

Expected CronJob schedule:

```bash
kubectl -n demo get cronjob mysql-backup
```

```text
*/5 * * * *
```

## Verify the frontend and API

Open the frontend:

```text
http://localhost:8080
```

Check it from the command line:

```bash
curl -fsS \
  http://localhost:8080 \
  | grep '<title>'
```

Read the current visits:

```bash
curl -fsS \
  http://localhost:8080/api/visits \
  | jq
```

Create a visit:

```bash
curl -fsS \
  -X POST \
  http://localhost:8080/api/visits \
  -H 'Content-Type: application/json' \
  -d '{"source":"readme-test"}' \
  | jq
```

Check backend load balancing:

```bash
for request in $(seq 1 20); do
  curl -fsS \
    http://localhost:8080/api/visits \
    | jq -r '.servedBy'
done \
  | sort \
  | uniq -c
```

Both backend pod names should appear in the output.

## Verify data in MySQL

Load the root password into a temporary shell variable:

```bash
MYSQL_ROOT_PASSWORD="$(
  kubectl -n demo \
    get secret mysql-auth \
    -o jsonpath='{.data.mysql-root-password}' \
    | base64 -d
)"
```

Query the database:

```bash
kubectl -n demo exec mysql-0 -- \
  /opt/bitnami/mysql/bin/mysql \
  -uroot \
  -p"${MYSQL_ROOT_PASSWORD}" \
  -e '
    USE appdb;

    SELECT COUNT(*) AS total_visits
    FROM visits;

    SELECT id, source, created_at
    FROM visits
    ORDER BY id DESC
    LIMIT 10;
  '
```

Clear the shell variable:

```bash
unset MYSQL_ROOT_PASSWORD
```

## Verify persistence

Read the current count:

```bash
COUNT_BEFORE="$(
  curl -fsS \
    http://localhost:8080/api/visits \
    | jq -r '.count'
)"
```

Restart the MySQL pod:

```bash
kubectl -n demo delete pod mysql-0

until kubectl -n demo get pod mysql-0 >/dev/null 2>&1; do
  sleep 2
done

kubectl -n demo wait \
  --for=condition=Ready \
  pod/mysql-0 \
  --timeout=600s
```

Read the count again:

```bash
COUNT_AFTER="$(
  curl -fsS \
    http://localhost:8080/api/visits \
    | jq -r '.count'
)"

echo "Before: ${COUNT_BEFORE}"
echo "After:  ${COUNT_AFTER}"

test "${COUNT_BEFORE}" = "${COUNT_AFTER}" \
  && echo "Persistence check passed" \
  || echo "Persistence check failed"
```

## Verify scheduled backups

List the CronJob and Jobs:

```bash
kubectl -n demo get cronjob,jobs
```

Get the latest Job created by the CronJob:

```bash
SCHEDULED_JOB="$(
  kubectl -n demo get jobs -o json \
    | jq -r '
        [
          .items[]
          | select(
              any(
                .metadata.ownerReferences[]?;
                .kind == "CronJob"
                and .name == "mysql-backup"
              )
            )
          | select(
              (.metadata.name | contains("manual")) | not
            )
        ]
        | sort_by(.metadata.creationTimestamp)
        | last
        | .metadata.name // empty
      '
)"

echo "${SCHEDULED_JOB}"
```

Verify its owner and completion status:

```bash
kubectl -n demo \
  get job "${SCHEDULED_JOB}" \
  -o jsonpath='Job: {.metadata.name}{"\n"}Owner: {.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}Succeeded: {.status.succeeded}{"\n"}'
```

View the backup log:

```bash
kubectl -n demo logs \
  "job/${SCHEDULED_JOB}"
```

Expected log entries:

```text
mysqld is alive
Creating backup: /backups/appdb-<timestamp>.sql
Backup created successfully
```

## Inspect backup files

The dump is created with permissions for UID and GID `1001`.

Create a temporary inspector pod using the same user:

```bash
cat <<'INSPECTOR_EOF' | kubectl -n demo apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: backup-inspector
spec:
  automountServiceAccountToken: false
  restartPolicy: Never

  securityContext:
    runAsNonRoot: true
    runAsUser: 1001
    runAsGroup: 1001
    seccompProfile:
      type: RuntimeDefault

  containers:
    - name: inspector
      image: busybox:1.37
      command:
        - sh
        - -c
        - sleep 3600

      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL

      volumeMounts:
        - name: backups
          mountPath: /backups
          readOnly: true

  volumes:
    - name: backups
      persistentVolumeClaim:
        claimName: mysql-backups
INSPECTOR_EOF
```

Wait for the pod:

```bash
kubectl -n demo wait \
  --for=condition=Ready \
  pod/backup-inspector \
  --timeout=180s
```

Inspect the latest dump:

```bash
kubectl -n demo exec backup-inspector -- \
  sh -c '
    latest="$(
      find /backups \
        -maxdepth 1 \
        -type f \
        -name "*.sql" \
        | sort \
        | tail -n 1
    )"

    echo "Latest backup: ${latest}"
    ls -lh "${latest}"
    wc -c "${latest}"

    grep -E \
      "CREATE TABLE.*visits|INSERT INTO.*visits" \
      "${latest}" \
      | head
  '
```

Remove the temporary pod:

```bash
kubectl -n demo delete pod backup-inspector
```

## GitOps self-healing check

Change a managed Deployment manually:

```bash
kubectl -n demo scale \
  deployment/demo-stack-frontend \
  --replicas=1
```

Argo CD should return it to the replica count defined in Git:

```bash
kubectl -n demo get deployment demo-stack-frontend -w
```

The desired replica count should return to `2`.

## Cleanup

Stop any running port-forward with `Ctrl+C`.

Destroy the Terraform-managed resources:

```bash
terraform -chdir=terraform destroy
```

Delete the k3d cluster:

```bash
./cluster/delete-cluster.sh
```

Remove local Terraform secrets and state after the environment has been destroyed:

```bash
rm -f \
  terraform/terraform.tfvars \
  terraform/terraform.tfstate \
  terraform/terraform.tfstate.backup \
  terraform/*.tfplan
```

Verify cleanup:

```bash
k3d cluster list
kubectl config get-contexts
```

## Notes

- MySQL data and backup files use separate PersistentVolumeClaims.
- The MySQL password is stored in a Kubernetes Secret created by Terraform.
- Local secret files and Terraform state are excluded from Git.
- Application and infrastructure resources are reconciled by Argo CD.
- Deleting the k3d cluster removes the local volumes and their data.

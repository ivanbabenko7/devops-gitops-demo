# DevOps GitOps Demo

This repository contains a small Kubernetes environment that I built for a DevOps practical task.

The project runs locally in k3d and includes:

- a multi-node Kubernetes cluster;
- Argo CD installed with Terraform;
- a custom Helm chart for the frontend and backend;
- MySQL deployed through the Bitnami Helm chart;
- automatic MySQL backups to a separate PVC;
- GitOps synchronization from this repository.

This is a local demonstration environment, not a production setup.

## How it works

Terraform installs Argo CD and creates two root Argo CD Applications:

```text
applications-root
└── demo-stack
    ├── frontend
    └── backend

infrastructure-root
├── mysql
└── mysql-backup
```

After the initial `terraform apply`, application and infrastructure resources are managed by Argo CD.

## Repository structure

```text
.
├── applications/
│   ├── demo-stack/        # Helm chart for frontend and backend
│   ├── src/               # Application source code
│   └── templates/         # Argo CD child Application
├── cluster/
│   ├── create-cluster.sh
│   └── delete-cluster.sh
├── infrastructure/
│   ├── backup/            # Backup CronJob and PVC
│   ├── mysql/             # Values for the Bitnami MySQL chart
│   └── templates/         # Argo CD child Applications
├── scripts/
│   └── backup-inspector.yaml
└── terraform/
    ├── applications.tf
    ├── main.tf
    ├── providers.tf
    ├── variables.tf
    └── versions.tf
```

## Requirements

The following tools must be available locally:

- Docker;
- k3d;
- kubectl;
- Helm;
- Terraform;
- Git;
- jq;
- OpenSSL.

The project was tested from Ubuntu in WSL2 with Docker Desktop integration enabled.

Check the installed tools:

```bash
docker version
k3d version
kubectl version --client
helm version --short
terraform version
```

## 1. Clone the repository

```bash
mkdir -p ~/work
cd ~/work

git clone https://github.com/ivanbabenko7/devops-gitops-demo.git
cd devops-gitops-demo
```

## 2. Create the Kubernetes cluster

The script creates one server node and two agent nodes:

```bash
./cluster/create-cluster.sh
```

Check the active context and nodes:

```bash
kubectl config current-context
kubectl get nodes -o wide
k3d cluster list
```

There should be three ready nodes:

```text
1 control-plane node
2 worker nodes
```

The application ingress is exposed on:

```text
http://localhost:8080
```

## 3. Configure Terraform variables

Generate separate passwords for the MySQL root user and application user:

```bash
ROOT_PASSWORD="$(openssl rand -hex 24)"
APP_PASSWORD="$(openssl rand -hex 24)"

while [[ "${ROOT_PASSWORD}" == "${APP_PASSWORD}" ]]; do
  APP_PASSWORD="$(openssl rand -hex 24)"
done
```

Create the local variables file:

```bash
umask 077

cat > terraform/terraform.tfvars <<TFVARS_EOF
git_repo_url         = "https://github.com/ivanbabenko7/devops-gitops-demo.git"
mysql_root_password  = "${ROOT_PASSWORD}"
mysql_app_password   = "${APP_PASSWORD}"
TFVARS_EOF

chmod 600 terraform/terraform.tfvars

unset ROOT_PASSWORD
unset APP_PASSWORD
```

The file is excluded from Git and must not be committed.

## 4. Deploy Argo CD and the root Applications

Initialize and validate Terraform:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

Review the plan:

```bash
terraform -chdir=terraform plan
```

Apply it:

```bash
terraform -chdir=terraform apply
```

Terraform installs Argo CD, creates the `demo` namespace, creates the MySQL Secret and registers the two root Argo CD Applications.

Check the Terraform resources:

```bash
terraform -chdir=terraform state list
```

## 5. Check Argo CD

Wait until Argo CD is ready:

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

The following Applications should appear:

```text
applications-root
demo-stack
infrastructure-root
mysql
mysql-backup
```

After synchronization, they should be `Synced` and `Healthy`.

## 6. Open the Argo CD UI

Start a port-forward:

```bash
kubectl -n argocd port-forward \
  svc/argocd-server \
  8081:80
```

Open:

```text
http://localhost:8081
```

The username is:

```text
admin
```

Get the initial password:

```bash
kubectl -n argocd get secret \
  argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' \
  | base64 -d

echo
```

Stop the port-forward with `Ctrl+C` when it is no longer needed.

## 7. Check the deployed resources

```bash
kubectl -n demo get \
  pods,pvc,services,ingress,cronjob,jobs \
  -o wide
```

The namespace should contain:

- two frontend pods;
- two backend pods;
- one MySQL pod;
- a PVC for MySQL data;
- a separate PVC for backup files;
- the `mysql-backup` CronJob.

## 8. Test the frontend and backend

Open the frontend:

```text
http://localhost:8080
```

Check it from the terminal:

```bash
curl -fsS http://localhost:8080 | grep '<title>'
```

Read the current visit data:

```bash
curl -fsS http://localhost:8080/api/visits | jq
```

Create a new record:

```bash
curl -fsS \
  -X POST \
  http://localhost:8080/api/visits \
  -H 'Content-Type: application/json' \
  -d '{"source":"readme-test"}' \
  | jq
```

Read the data again:

```bash
curl -fsS http://localhost:8080/api/visits | jq
```

To check that traffic reaches both backend replicas:

```bash
for request in $(seq 1 20); do
  curl -fsS http://localhost:8080/api/visits \
    | jq -r '.servedBy'
done | sort | uniq -c
```

Both backend pod names should appear.

## 9. Check the data in MySQL

Load the root password into a temporary shell variable:

```bash
MYSQL_ROOT_PASSWORD="$(
  kubectl -n demo get secret mysql-auth \
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

Remove the password from the shell:

```bash
unset MYSQL_ROOT_PASSWORD
```

## 10. Check MySQL persistence

Save the current record count:

```bash
COUNT_BEFORE="$(
  curl -fsS http://localhost:8080/api/visits \
    | jq -r '.count'
)"

echo "Count before restart: ${COUNT_BEFORE}"
```

Delete the MySQL pod:

```bash
kubectl -n demo delete pod mysql-0
```

Wait for the replacement pod:

```bash
until kubectl -n demo get pod mysql-0 >/dev/null 2>&1; do
  sleep 2
done

kubectl -n demo wait \
  --for=condition=Ready \
  pod/mysql-0 \
  --timeout=600s
```

Wait until the API can reach MySQL again:

```bash
until curl -fsS http://localhost:8080/api/visits >/dev/null; do
  echo "Waiting for the backend and MySQL..."
  sleep 3
done
```

Read the count again:

```bash
COUNT_AFTER="$(
  curl -fsS http://localhost:8080/api/visits \
    | jq -r '.count'
)"

echo "Count before restart: ${COUNT_BEFORE}"
echo "Count after restart:  ${COUNT_AFTER}"

if [[ "${COUNT_BEFORE}" == "${COUNT_AFTER}" ]]; then
  echo "Persistence check: PASS"
else
  echo "Persistence check: FAIL"
fi
```

## 11. Check MySQL backups

The CronJob runs every five minutes:

```bash
kubectl -n demo get cronjob mysql-backup \
  -o custom-columns='NAME:.metadata.name,SCHEDULE:.spec.schedule,SUSPEND:.spec.suspend,LAST:.status.lastScheduleTime'
```

For an immediate test, create a Job from the CronJob template:

```bash
BACKUP_JOB="mysql-backup-manual-$(date +%s)"

kubectl -n demo create job \
  --from=cronjob/mysql-backup \
  "${BACKUP_JOB}"
```

Wait for it to finish:

```bash
kubectl -n demo wait \
  --for=condition=complete \
  "job/${BACKUP_JOB}" \
  --timeout=300s
```

Read its logs:

```bash
kubectl -n demo logs "job/${BACKUP_JOB}"
```

A successful run prints the path and size of the generated SQL file.

Scheduled and manual Jobs can be listed with:

```bash
kubectl -n demo get jobs \
  -l app.kubernetes.io/name=mysql-backup \
  --sort-by=.metadata.creationTimestamp
```

## 12. Inspect the backup PVC

Create a temporary Pod that mounts the backup PVC as read-only:

```bash
kubectl -n demo apply \
  -f scripts/backup-inspector.yaml
```

Wait until it is ready:

```bash
kubectl -n demo wait \
  --for=condition=Ready \
  pod/backup-inspector \
  --timeout=180s
```

Inspect the latest SQL dump:

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

    test -n "${latest}"

    echo "Latest backup: ${latest}"
    ls -lh "${latest}"
    wc -c "${latest}"

    echo
    echo "Database objects found in the dump:"

    grep -E \
      "CREATE TABLE.*visits|INSERT INTO.*visits" \
      "${latest}" \
      | head
  '
```

Remove the temporary Pod:

```bash
kubectl -n demo delete pod backup-inspector
```

## 13. Optional GitOps self-healing test

Change the frontend replica count directly in the cluster:

```bash
kubectl -n demo scale \
  deployment/demo-stack-frontend \
  --replicas=1
```

Watch the Deployment:

```bash
kubectl -n demo get \
  deployment/demo-stack-frontend \
  -w
```

Argo CD should restore the replica count defined in Git.

## Cleanup

Destroy the Terraform-managed resources:

```bash
terraform -chdir=terraform destroy
```

Delete the k3d cluster:

```bash
./cluster/delete-cluster.sh
```

Remove local Terraform secrets and state only after the environment has been destroyed:

```bash
rm -f \
  terraform/terraform.tfvars \
  terraform/terraform.tfstate \
  terraform/terraform.tfstate.backup \
  terraform/*.tfplan
```

## Notes and limitations

- MySQL data and backup files use separate PVCs.
- Both PVCs use the local k3d storage provisioner.
- Deleting the k3d cluster also deletes the local data.
- The backup PVC protects files from individual Job deletion, but it is not an off-cluster backup.
- Terraform state contains the MySQL passwords and must be treated as sensitive.
- The current demo uses a pinned legacy Bitnami MySQL image for compatibility with the selected chart version.
- A production setup should use a supported image, encrypted remote Terraform state, external secret management and remote backup storage.

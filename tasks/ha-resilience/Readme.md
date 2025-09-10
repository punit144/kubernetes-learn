---

# 📂 Task: HA & Resilience with Kubernetes

**Path:** `tasks/ha-resilience/`

---

## 🎯 Objective

Learn how to design **highly available (HA) and resilient** workloads in Kubernetes by:

1. Running an NGINX app with **3 replicas** behind a Service
2. Proving resilience by killing pods
3. Enforcing high availability using a **PodDisruptionBudget (PDB)**

---

## 🛠️ Steps Performed

### 1. Deployment with Replicas

* We created an NGINX **Deployment** with `replicas=3`.
* This ensures that even if one pod fails, Kubernetes automatically spins up another.

👉 File: `nginx-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
```

---

### 2. Service for Load Balancing

* We exposed the deployment using a **ClusterIP Service**.
* This load balances traffic across all 3 replicas.

👉 File: `nginx-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
```

---

### 3. Test HA by Killing Pods

1. Started a port-forward to access the service locally:

   ```bash
   kubectl port-forward svc/nginx-service 8080:80
   ```

   → Opened `http://localhost:8080` (default NGINX welcome page).

2. Deleted a pod manually:

   ```bash
   kubectl delete pod <nginx-pod-name>
   ```

   → Service stayed up, and Kubernetes rescheduled a replacement pod automatically.

✅ Proof of **resilience**: App stayed online despite a pod failure.

---

### 4. PodDisruptionBudget (PDB)

* Added a **PDB** to guarantee that at least **2 replicas** are always available, even during voluntary disruptions like node drains.

👉 File: `nginx-pdb.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nginx-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: nginx
```

Check:

```bash
kubectl get pdb nginx-pdb
```

Output:

```
NAME        MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
nginx-pdb   2               N/A               1
```

---

### 5. Testing the PDB

#### 🔹 Drain a Node

```bash
kubectl drain kind-worker --ignore-daemonsets --delete-emptydir-data
```

* Kubernetes tried evicting pods.
* One eviction was **blocked** by the PDB because evicting both would have left fewer than 2 replicas.

Message seen:

```
Cannot evict pod as it would violate the pod's disruption budget.
```

Then uncordon the node:

```bash
kubectl uncordon kind-worker
```

#### 🔹 Delete Pods Manually

```bash
kubectl delete pod <nginx-pod-name>
```

* Allowed if at least 2 pods remain.
* Blocked if it would leave <2 (depends on timing + drain scenario).

---

## 📊 Key Learnings

* **Deployment + replicas** = baseline resilience
* **Service** = load balancing across replicas
* **Deleting pods** = shows Kubernetes self-healing in action
* **PDB** = protects against too many voluntary disruptions, ensures HA guarantees

---

## ✅ Next Steps

* Automate tests with a script (`test-pdb.sh`) to show before/after state of PDB.
* Extend HA learning by deploying across multiple nodes and testing **node failures** with Kind.

---

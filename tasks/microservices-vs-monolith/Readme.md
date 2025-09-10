# 📊 Summary: Monolith vs Microservices

## ✅ What We Did

1. **Monolith (default namespace)**

   * Built a single Node.js app serving both **frontend HTML + API endpoint**.
   * Deployed as **1 Deployment + 1 Service**.
   * Verified that scaling & updates are coupled → frontend and backend are inseparable.

2. **Microservices (microservices-demo namespace)**

   * Split into **API (Express backend)** and **Frontend (NGINX + static HTML, reverse proxy to API)**.
   * Deployed as **2 Deployments + 2 Services**.
   * Verified pods running separately and frontend calling API through service DNS.

---

## 🔍 Key Learnings

* **Namespaces for isolation**
  Each app/task runs in its own namespace → makes cleanup, testing, and resource separation easier.

* **Monolith Pros/Cons**

  * ✅ Simpler to build and deploy (single container).
  * ❌ Tight coupling: can’t scale frontend and backend independently.
  * ❌ Any change requires redeploying the entire app.

* **Microservices Pros/Cons**

  * ✅ Independent scaling → scale API separately from frontend.
  * ✅ Independent deployments/updates → smaller blast radius.
  * ✅ Clear separation of concerns (frontend, API, DB).
  * ❌ More complexity (multiple services, networking, configs).

* **Kubernetes Service DNS**

  * `api-service.microservices-demo.svc.cluster.local` → shows how microservices discover each other inside the cluster.

---

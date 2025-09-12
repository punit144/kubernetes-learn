# 📘 Event-driven Patterns – Hands-on Guide

## 1. Overview

Event-driven architecture (EDA) allows services to **communicate via events** instead of direct calls.

* **Producer** → publishes events (messages).
* **Broker** → stores and routes events (Kafka, RabbitMQ).
* **Consumer** → subscribes and reacts to events.

This decouples services and enables **scalability, resilience, and real-time processing**.

We’ll explore this using:

* **Apache Kafka** (via Strimzi Operator on Kubernetes).
* **RabbitMQ** (via Bitnami Helm chart).

---

## 2. Deploy Kafka (Strimzi Operator)

### Step 1: Install Strimzi via Helm

```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update
kubectl create namespace kafka
helm install strimzi strimzi/strimzi-kafka-operator -n kafka
```

### Step 2: Deploy a Kafka cluster (KRaft mode)

```yaml
# kafka-kraft.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 4.0.0
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      inter.broker.protocol.version: "4.0"
      log.message.format.version: "4.0"
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
  # NodePool must be defined separately
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: my-cluster-kafka
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  replicas: 1
  roles:
    - broker
    - controller
  storage:
    type: ephemeral
```

Apply it:

```bash
kubectl apply -f kafka-kraft.yaml
kubectl get pods -n kafka
```

---

## 3. Create a Topic

```yaml
# kafka-topic.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: test-topic
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 3
  replicas: 1
```

Apply it:

```bash
kubectl apply -f kafka-topic.yaml
```

---

## 4. Producer and Consumer Microservices

### Producer Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-producer
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-producer
  template:
    metadata:
      labels:
        app: kafka-producer
    spec:
      containers:
        - name: producer
          image: python:3.11-slim
          command: ["/bin/sh", "-c"]
          args:
            - pip install kafka-python && python -u producer.py
          volumeMounts:
            - name: app-code
              mountPath: /app
          workingDir: /app
      volumes:
        - name: app-code
          configMap:
            name: producer-code
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: producer-code
  namespace: kafka
data:
  producer.py: |
    from kafka import KafkaProducer
    import time, json

    producer = KafkaProducer(bootstrap_servers='my-cluster-kafka-bootstrap.kafka:9092')

    while True:
        event = {"order_id": 1, "status": "CREATED"}
        producer.send('test-topic', json.dumps(event).encode('utf-8'))
        print("Produced:", event)
        time.sleep(3)
```

### Consumer Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-consumer
  namespace: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-consumer
  template:
    metadata:
      labels:
        app: kafka-consumer
    spec:
      containers:
        - name: consumer
          image: python:3.11-slim
          command: ["/bin/sh", "-c"]
          args:
            - pip install kafka-python && python -u consumer.py
          volumeMounts:
            - name: app-code
              mountPath: /app
          workingDir: /app
      volumes:
        - name: app-code
          configMap:
            name: consumer-code
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: consumer-code
  namespace: kafka
data:
  consumer.py: |
    from kafka import KafkaConsumer
    import json

    consumer = KafkaConsumer(
        'test-topic',
        bootstrap_servers='my-cluster-kafka-bootstrap.kafka:9092',
        auto_offset_reset='earliest',
        enable_auto_commit=True,
        group_id='my-group'
    )

    for message in consumer:
        print("Consumed:", json.loads(message.value.decode()))
```

---

## 5. Validate

Check pods:

```bash
kubectl get pods -n kafka
```

View logs:

```bash
kubectl logs -f deploy/kafka-producer -n kafka
kubectl logs -f deploy/kafka-consumer -n kafka
```

You should see:

* Producer → `Produced: {"order_id": 1, "status": "CREATED"}`
* Consumer → `Consumed: {"order_id": 1, "status": "CREATED"}`

---

## 6. RabbitMQ (Lightweight Alternative)

### Install RabbitMQ via Helm

```bash
kubectl create ns rabbitmq
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install rabbitmq bitnami/rabbitmq -n rabbitmq
kubectl get all -n rabbitmq
```

### Test with Producer/Consumer

* Use **pika** library in Python.
* Same pattern: producer publishes to exchange, consumer consumes from queue.

---

## 7. Next Experiments

1. **JSON events** → simulate order/payment services.
2. **Multiple consumers** → see how Kafka load balances vs broadcasts.
3. **RabbitMQ vs Kafka** → compare routing, persistence, and scaling.
4. **Monitoring** → install Prometheus/Grafana dashboards for Kafka & RabbitMQ.

---

✅ With this setup, you now have a **playground** for event-driven systems using both **Kafka** and **RabbitMQ**.

---

Do you want me to extend this doc into a **mini real-world project simulation** (e.g., Order → Payment → Notification flow with 3 services), so you can show it as a portfolio piece?

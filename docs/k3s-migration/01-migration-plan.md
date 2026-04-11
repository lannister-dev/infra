# План миграции Docker Swarm → K3s

## Текущая архитектура (Swarm)

```
Infra nodes (Swarm managers/workers):
  ├── traefik          (Ingress, TLS, dashboard)
  ├── monitoring       (Prometheus, Grafana, Alertmanager, node-exporter, cadvisor)
  ├── vault            (HashiCorp Vault)
  ├── swarmpit         (Swarm UI → убираем)
  ├── nats             (messaging для node-agent)
  ├── data-prod        (PostgreSQL + Redis)
  ├── data-dev         (PostgreSQL + Redis)
  └── control-api      (FastAPI, деплоится из отдельного репо)

VPN nodes (Swarm workers):
  ├── xray             (VPN proxy, global mode = на каждой ноде)
  └── node-agent       (отчитывается control plane)
```

## Целевая архитектура (K3s)

```
Infra nodes (K3s server + agents):
  ├── Traefik            (встроен в K3s, не деплоим отдельно)
  ├── cert-manager       (вместо Traefik ACME — более гибкое управление TLS)
  ├── kube-prometheus-stack (Helm: Prometheus + Grafana + Alertmanager + node-exporter)
  ├── vault              (Helm chart)
  ├── nats               (Helm chart)
  ├── data-prod ns       (PostgreSQL StatefulSet + Redis StatefulSet)
  ├── data-dev ns        (PostgreSQL StatefulSet + Redis StatefulSet)
  └── control-api        (Deployment + Service + Ingress)

VPN nodes (K3s agents):
  ├── xray               (DaemonSet с hostNetwork)
  └── node-agent          (DaemonSet)
```

---

## Фазы миграции

### Фаза 0: Подготовка (без миграции, текущий Swarm работает)

**Цель:** Создать K3s инфраструктуру рядом со Swarm, ничего не ломая.

#### 0.1 Структура директорий
```
k8s/                              # ← новая директория в infra репо
├── bootstrap/                    # Скрипты установки K3s
│   ├── install-server.sh         # Установка K3s server
│   └── install-agent.sh          # Установка K3s agent
├── namespaces/                   # Определение namespaces
│   └── namespaces.yml
├── charts/                       # Наши кастомные Helm charts
│   ├── vpn-xray/                 # xray + fallback
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   ├── vpn-node-agent/           # node-agent
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   ├── control-api/              # vpn-control-api
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   ├── data/                     # PostgreSQL + Redis
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── nats-custom/              # NATS с нашими настройками
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
├── values/                       # Переопределения values для окружений
│   ├── prod/
│   │   ├── vpn-xray.yaml
│   │   ├── control-api.yaml
│   │   ├── monitoring.yaml
│   │   └── data.yaml
│   └── dev/
│       ├── vpn-xray.yaml
│       ├── control-api.yaml
│       └── data.yaml
└── Makefile                      # make k3s-deploy, make k3s-status, etc.
```

#### 0.2 Ansible роль `k3s-server`
Аналог текущей `swarm-join`, но для K3s:
```
ansible/roles/k3s-server/
  tasks/main.yml    — curl install k3s, дождаться ready
  defaults/main.yml — k3s_version, k3s_args, flannel_backend
```

#### 0.3 Ansible роль `k3s-agent`
```
ansible/roles/k3s-agent/
  tasks/main.yml    — curl install k3s agent, join cluster
  defaults/main.yml — k3s_url, k3s_token
```

#### 0.4 Terraform
Текущий `terraform/infra-nodes` и `terraform/nodes` не меняются.
Ноды провижинятся так же — меняется только что на них ставится (k3s вместо docker swarm).

**Что делаем в этой фазе:**
- [ ] Создать `k8s/` структуру
- [ ] Создать роли `k3s-server` и `k3s-agent`
- [ ] Создать `k8s/bootstrap/` скрипты
- [ ] Создать `k8s/namespaces/namespaces.yml`

---

### Фаза 1: Monitoring (самый безопасный первый шаг)

**Почему первый:** Мониторинг не влияет на трафик пользователей.
Если что-то пойдёт не так — VPN продолжает работать.

**Что делаем:**

1. Установить K3s server на dev infra ноде (рядом со Swarm)
2. Развернуть `kube-prometheus-stack` через Helm

```bash
# kube-prometheus-stack заменяет:
# - prometheus       → Prometheus (с operator для автоконфигурации)
# - grafana          → Grafana (с автоимпортом дашбордов)
# - alertmanager     → Alertmanager
# - node-exporter    → node-exporter (DaemonSet на всех нодах)
# - cadvisor         → cAdvisor (не нужен — metrics-server встроен)

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values k8s/values/prod/monitoring.yaml
```

**values/prod/monitoring.yaml:**
```yaml
prometheus:
  prometheusSpec:
    retention: 14d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 20Gi

grafana:
  adminUser: admin
  adminPassword: <from-secret>
  ingress:
    enabled: true
    hosts:
      - grafana.example.com

alertmanager:
  config:
    # Твой текущий alertmanager.yml почти без изменений
    route:
      receiver: default-webhook
      group_by: [alertname, service]
```

**Что это даёт:**
- Один `helm install` вместо: Terraform configs + Docker volumes + Ansible deploy + 6 env vars
- Автоматическое обнаружение targets (не нужен docker_sd_configs)
- Grafana дашборды для K8s из коробки

**Что делаем:**
- [ ] Helm chart values для monitoring
- [ ] Перенести текущие alert rules
- [ ] Перенести Grafana дашборды
- [ ] Настроить Ingress для Grafana/Prometheus/Alertmanager

---

### Фаза 2: Data стеки (PostgreSQL + Redis)

**Новая концепция: StatefulSet**

Deployment подходит для stateless приложений (control-api, nginx).
Для баз данных используется **StatefulSet** — он гарантирует:
- Стабильные имена подов: `postgres-0`, `postgres-1` (не случайные)
- Привязку пода к его PVC (данные не теряются при рестарте)
- Порядок запуска/остановки (postgres-0 стартует первым)

```yaml
# Swarm: service с volumes
# K8s: StatefulSet с volumeClaimTemplates

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: data-prod
spec:
  serviceName: postgres     # обязательно для StatefulSet
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    spec:
      containers:
        - name: postgres
          image: postgres:16
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: postgres-password
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:      # ← автоматически создаёт PVC для каждого пода
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 10Gi
```

**Миграция данных:**
1. `pg_dump` из Swarm PostgreSQL
2. Поднять PostgreSQL в K3s
3. `pg_restore` в K3s PostgreSQL
4. Переключить control-api на новый адрес

**Что делаем:**
- [ ] Helm chart `k8s/charts/data/` (PostgreSQL + Redis StatefulSet)
- [ ] Secrets для паролей
- [ ] Миграция данных (backup/restore)

---

### Фаза 3: NATS + Vault

**NATS:** Используем официальный Helm chart:
```bash
helm repo add nats https://nats-io.github.io/k8s/helm/charts/
helm install nats nats/nats --namespace nats --create-namespace \
  --values k8s/values/prod/nats.yaml
```

**Vault:** Используем официальный Helm chart:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault --namespace vault --create-namespace \
  --values k8s/values/prod/vault.yaml
```

**Что делаем:**
- [ ] Values для NATS Helm chart
- [ ] Values для Vault Helm chart
- [ ] Миграция Vault данных (unseal keys, secrets)

---

### Фаза 4: Control Plane (vpn-control-api + бот)

Самый простой переход — это обычный stateless Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-api
  namespace: vpn-prod
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: control-api
          image: harbor.../control-api:latest
          ports:
            - containerPort: 8000
          envFrom:
            - secretRef:
                name: control-api-env    # все env vars из Secret
          readinessProbe:                # K8s проверяет готовность
            httpGet:
              path: /api/readyz
              port: 8000
          livenessProbe:                 # K8s перезапускает если мёртв
            httpGet:
              path: /api/readyz
              port: 8000
```

**Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: control-api
spec:
  rules:
    - host: api.lannister-dev.ru
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: control-api
                port:
                  number: 8000
```

**Что делаем:**
- [ ] Helm chart `k8s/charts/control-api/`
- [ ] Перенести env vars в K8s Secret
- [ ] Настроить CI: `helm upgrade` вместо `docker stack deploy`
- [ ] То же для бота

---

### Фаза 5: VPN ноды (самая сложная часть)

**Почему сложная:**
- xray использует `hostNetwork: true` + порт 443
- Нужна совместимость с WireGuard mesh
- node-agent должен отчитываться control plane
- K3s agent потребляет ~200MB RAM — на маленьких VPS это заметно

**Стратегия: поэтапная миграция нода за нодой.**

1. Добавить новую VPN ноду как K3s agent (не Swarm worker)
2. Развернуть xray + node-agent как DaemonSet
3. Проверить что VPN работает через эту ноду
4. Если ОК — следующая нода. Если нет — откатить.
5. После последней ноды — убрать Swarm VPN стеки

**DaemonSet для xray:**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: xray
  namespace: vpn-prod
spec:
  selector:
    matchLabels:
      app: xray
  template:
    spec:
      hostNetwork: true        # занимает порт 443 на хосте
      dnsPolicy: ClusterFirstWithHostNet
      nodeSelector:
        role: vpn
        channel: prod
      tolerations:             # разрешить запуск на VPN нодах
        - key: dedicated
          value: vpn
          effect: NoSchedule
      containers:
        - name: xray
          image: ghcr.io/xtls/xray-core:latest
          ports:
            - containerPort: 443
              hostPort: 443
          volumeMounts:
            - name: xray-config
              mountPath: /etc/xray/config.json
              subPath: config.json
      volumes:
        - name: xray-config
          configMap:
            name: xray-config
```

**Что делаем:**
- [ ] Роль `k3s-agent` вместо `swarm-join` для VPN нод
- [ ] Helm chart `k8s/charts/vpn-xray/`
- [ ] Helm chart `k8s/charts/vpn-node-agent/`
- [ ] Адаптировать WireGuard reconcile
- [ ] Тестирование на одной ноде
- [ ] Поэтапный rollout

---

### Фаза 6: Cleanup

После полной миграции:
- Удалить Docker Swarm стеки
- Удалить `docker/stacks/` директорию
- Удалить Swarm-специфичные Terraform ресурсы (docker_config, docker_network, docker_volume)
- Удалить Swarm-специфичные Ansible playbooks или адаптировать под K3s
- Обновить CI workflows

---

## Порядок и зависимости

```
Фаза 0 (подготовка)
  │
  ├── Фаза 1 (monitoring) ── независима, безопасна
  │
  ├── Фаза 2 (data) ── нужна до Фазы 4
  │
  ├── Фаза 3 (nats + vault) ── нужна до Фазы 5
  │
  ├── Фаза 4 (control-api) ── зависит от Фазы 2 (нужен PostgreSQL в K3s)
  │
  └── Фаза 5 (VPN ноды) ── зависит от Фазы 3 (нужен NATS в K3s)
        │
        └── Фаза 6 (cleanup)
```

## Timeline (примерный)

| Фаза | Что | Риск |
|------|-----|------|
| 0 | Структура, роли, bootstrap | Нулевой — ничего не трогаем |
| 1 | Monitoring | Низкий — не влияет на трафик |
| 2 | Data | Средний — нужен downtime для pg_dump/restore |
| 3 | NATS + Vault | Средний — нужно пересоздать secrets |
| 4 | Control API | Средний — переключение DNS |
| 5 | VPN ноды | Высокий — одна нода за раз, с проверкой |
| 6 | Cleanup | Низкий — удаление старого |

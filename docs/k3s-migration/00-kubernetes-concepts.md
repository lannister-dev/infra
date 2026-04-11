# Kubernetes для тех, кто знает Docker Swarm

## Главная идея

Kubernetes (K8s) — это оркестратор контейнеров, как и Docker Swarm.
Разница: Swarm прост, но ограничен. K8s сложнее, но даёт полный контроль.

K3s — это **тот же Kubernetes**, просто упакованный в один бинарник.
Все команды, манифесты, Helm charts — идентичны полному K8s.

---

## Словарь: Swarm → Kubernetes

| Docker Swarm | Kubernetes | Что это |
|---|---|---|
| Node (manager) | **Control Plane Node** (server) | Управляющая нода. В K3s — `k3s server` |
| Node (worker) | **Worker Node** (agent) | Рабочая нода. В K3s — `k3s agent` |
| Service | **Deployment** + **Service** | В K8s это разделено на 2 объекта (см. ниже) |
| Stack (compose file) | **Helm Chart** или набор манифестов | Группа связанных ресурсов |
| `docker stack deploy` | `helm install` или `kubectl apply` | Деплой |
| Docker Config | **ConfigMap** | Конфигурация, монтируется в контейнер |
| Docker Secret | **Secret** | То же что ConfigMap, но base64 + ограниченный доступ |
| Overlay Network | **Не нужно** — K8s делает это автоматически | Все поды видят друг друга через DNS |
| Placement constraint | **nodeSelector** / **affinity** | Куда ставить под |
| `mode: global` | **DaemonSet** | Запустить на каждой подходящей ноде |
| `mode: replicated` | **Deployment** | Запустить N реплик где угодно |
| Traefik labels | **Ingress** / **IngressRoute** | Маршрутизация HTTP трафика |

---

## Основные сущности K8s (с примерами из твоей инфры)

### Pod — минимальная единица

Pod = один или несколько контейнеров, запущенных вместе.
Аналогия в Swarm: один task сервиса.

```yaml
# Ты никогда не создаёшь Pod напрямую.
# Это делает Deployment или DaemonSet.
```

### Deployment — "я хочу N реплик этого приложения"

Твой `control-api` в Swarm:
```yaml
# Swarm:
services:
  control-api:
    image: harbor.../control-api:latest
    deploy:
      replicas: 2
      placement:
        constraints:
          - node.labels.kind == prod
```

В Kubernetes:
```yaml
# K8s:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-api          # имя деплоймента
spec:
  replicas: 2                # сколько реплик (как replicas в Swarm)
  selector:
    matchLabels:
      app: control-api       # по какому лейблу находить поды
  template:                  # шаблон пода
    metadata:
      labels:
        app: control-api     # лейбл пода (должен совпадать с selector)
    spec:
      nodeSelector:
        kind: prod           # аналог placement constraint
      containers:
        - name: control-api
          image: harbor.../control-api:latest
          ports:
            - containerPort: 8000
          resources:          # лимиты ресурсов (в Swarm это deploy.resources)
            requests:
              cpu: 250m       # 0.25 CPU (как reservations.cpus)
              memory: 128Mi
            limits:
              cpu: "1"
              memory: 512Mi
```

**Что даёт Deployment чего нет в Swarm:**
- `kubectl rollout undo` — мгновенный откат на предыдущую версию
- `kubectl rollout status` — статус раскатки в реальном времени
- Хранит историю N ревизий (Swarm хранит только текущую)

### DaemonSet — "запустить на каждой подходящей ноде"

Твой xray в Swarm `mode: global`:
```yaml
# Swarm:
services:
  xray:
    deploy:
      mode: global
      placement:
        constraints:
          - node.labels.role == vpn
          - node.labels.channel != dev
```

В Kubernetes:
```yaml
# K8s:
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: xray
spec:
  selector:
    matchLabels:
      app: xray
  template:
    spec:
      nodeSelector:
        role: vpn            # только на VPN нодах
      hostNetwork: true      # занять порты хоста напрямую (как mode: host в Swarm)
      containers:
        - name: xray
          image: ghcr.io/xtls/xray-core:latest
          ports:
            - containerPort: 443
              hostPort: 443   # публикация на хост (как published: 443, mode: host)
```

**DaemonSet vs Deployment:** DaemonSet гарантирует ровно 1 под на каждой подходящей ноде.
Deployment запускает N реплик, и планировщик сам решает на каких нодах.

### Service — "как найти мои поды по сети"

В Swarm сеть неявная — сервисы видят друг друга по имени.
В K8s нужно создать объект Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: control-api           # DNS имя: control-api.default.svc.cluster.local
spec:                          # или просто: control-api (внутри того же namespace)
  selector:
    app: control-api           # найти поды с этим лейблом
  ports:
    - port: 8000               # порт сервиса
      targetPort: 8000         # порт контейнера
```

Теперь любой под в кластере может обратиться к `http://control-api:8000`.

**Аналогия:** В Swarm ты пишешь `nats:4222` и overlay сеть маршрутит.
В K8s ты пишешь `nats:4222` и Service маршрутит. Разница — нужно явно создать Service.

### ConfigMap и Secret — "конфигурация и секреты"

Docker Config → ConfigMap:
```yaml
# В Swarm ты делал:
# docker config create prometheus_config__abc123 prometheus.yml

# В K8s:
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
    ...
```

Docker Secret → Secret:
```yaml
# В Swarm: echo "password" | docker secret create db_password -
# В K8s:
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:                    # K8s сам закодирует в base64
  postgres-password: "my_password"
  redis-password: "my_password"
```

Монтирование в контейнер:
```yaml
containers:
  - name: postgres
    volumeMounts:
      - name: db-secret
        mountPath: /run/secrets/postgres-password
        subPath: postgres-password     # один файл, не директория
        readOnly: true
volumes:
  - name: db-secret
    secret:
      secretName: db-credentials
```

**Главное отличие от Swarm:**
- В Swarm configs/secrets immutable — при изменении создаёшь новый с новым именем.
  Поэтому у тебя `prometheus_config__abc123` (хэш в имени).
- В K8s ConfigMap/Secret mutable — просто обновляешь содержимое.
  Чтобы поды перезапустились, используют annotation с checksum.

### Ingress — "маршрутизация HTTP снаружи"

В Swarm ты вешал Traefik labels на сервис:
```yaml
# Swarm:
deploy:
  labels:
    - "traefik.http.routers.grafana.rule=Host(`grafana.example.com`)"
    - "traefik.http.routers.grafana.entrypoints=websecure"
```

В K8s есть встроенная абстракция — Ingress:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana       # имя K8s Service
                port:
                  number: 3000
  tls:
    - hosts:
        - grafana.example.com
      secretName: grafana-tls       # TLS сертификат (cert-manager)
```

**K3s бонус:** Traefik уже встроен как Ingress Controller.
Тебе не нужно его деплоить — K3s сделал это за тебя.

### Namespace — "изоляция окружений"

В Swarm у тебя стеки: `vpn`, `vpn-dev`, `monitoring`, `data-prod`, `data-dev`.
В K8s — namespaces:

```bash
kubectl create namespace vpn-prod
kubectl create namespace vpn-dev
kubectl create namespace monitoring
kubectl create namespace data-prod
```

Ресурсы в разных namespaces изолированы по имени.
`postgres` в namespace `data-prod` и `postgres` в `data-dev` — разные сервисы.
Обращение между namespaces: `postgres.data-prod.svc.cluster.local`.

### PersistentVolume (PV) + PersistentVolumeClaim (PVC) — "хранилище"

В Swarm: `volumes: prometheus_data: driver: local`.
В K8s хранилище двухуровневое:

```yaml
# PersistentVolumeClaim — "мне нужно 10Gi хранилища"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
spec:
  accessModes: [ReadWriteOnce]   # один под пишет
  resources:
    requests:
      storage: 10Gi
```

K3s использует local-path provisioner — автоматически создаёт директорию на ноде.
Для продакшена можно добавить Longhorn (распределённое хранилище от Rancher).

### Helm — "пакетный менеджер для K8s"

Helm chart = шаблонизированный набор K8s манифестов + values.yaml.

```bash
# Установить Prometheus + Grafana + Alertmanager одной командой:
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml

# Обновить:
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml

# Откатить:
helm rollback monitoring 1
```

**Аналогия:** `helm install` = `docker stack deploy -c monitoring.yml monitoring`,
но с шаблонизацией, версионированием и rollback.

---

## Как K3s устроен

```
                    ┌─────────────────────────┐
                    │    K3s Server (manager)  │
                    │                         │
                    │  API Server             │  ← kubectl обращается сюда
                    │  Scheduler              │  ← решает на какую ноду ставить под
                    │  Controller Manager     │  ← следит что desired = actual
                    │  Embedded etcd/SQLite   │  ← хранит состояние кластера
                    │  Traefik (Ingress)      │  ← встроен в K3s
                    │  CoreDNS               │  ← DNS внутри кластера
                    │  Flannel (CNI)          │  ← сеть между подами
                    └───────────┬─────────────┘
                                │
                    ┌───────────┴─────────────┐
                    │                         │
          ┌─────────┴──┐            ┌─────────┴──┐
          │ K3s Agent   │            │ K3s Agent   │
          │ (VPN node)  │            │ (VPN node)  │
          │             │            │             │
          │  kubelet    │            │  kubelet    │
          │  xray pod   │            │  xray pod   │
          │  agent pod  │            │  agent pod  │
          └─────────────┘            └─────────────┘
```

**Установка K3s Server (на infra manager ноде):**
```bash
curl -sfL https://get.k3s.io | sh -
# Через 30 секунд у тебя работающий Kubernetes кластер
# kubectl уже работает
```

**Присоединение Agent (на VPN ноде):**
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://<server-ip>:6443 \
  K3S_TOKEN=<token> sh -
# Нода появится в кластере через 10 секунд
```

Сравни с текущим Swarm:
```bash
docker swarm join --token <token> <manager-ip>:2377
```

Почти идентично.

---

## Ключевые команды

| Задача | Docker Swarm | Kubernetes |
|---|---|---|
| Список нод | `docker node ls` | `kubectl get nodes` |
| Список сервисов | `docker service ls` | `kubectl get deployments -A` |
| Логи сервиса | `docker service logs vpn_xray` | `kubectl logs -l app=xray` |
| Масштабирование | `docker service scale web=3` | `kubectl scale deploy web --replicas=3` |
| Деплой | `docker stack deploy -c file.yml name` | `kubectl apply -f file.yml` или `helm install` |
| Удалить стек | `docker stack rm monitoring` | `helm uninstall monitoring` |
| Зайти в контейнер | `docker exec -it <id> sh` | `kubectl exec -it <pod> -- sh` |
| Статус раскатки | (нет аналога) | `kubectl rollout status deploy/web` |
| Откат | (переразвернуть) | `kubectl rollout undo deploy/web` |
| Лейблы ноды | `docker node update --label-add` | `kubectl label node <name> role=vpn` |

---

## Что НЕ меняется при миграции

1. **Docker images** — те же самые. K8s запускает те же контейнеры.
2. **Terraform для VPS** — провижининг нод не меняется. Только вместо `docker swarm join` будет `k3s agent`.
3. **WireGuard** — mesh остаётся. K3s Flannel может использовать WireGuard как backend.
4. **CI/CD** — GitHub Actions. Вместо `docker stack deploy` будет `helm upgrade`.
5. **Harbor** — образы по-прежнему хранятся там.

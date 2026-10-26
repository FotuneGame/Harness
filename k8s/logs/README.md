# logs: мониторинг

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-logs` |
| Namespace | `logs` |
| Узел | `core` |
| Charts | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack), [jaeger](https://github.com/jaegertracing/helm-charts) |
| `templates/dashboards/` | Дашборды Grafana |
| `templates/emails/` | Шаблон писем Alertmanager |
| `templates/exporter.yaml`, `files/platform_exporter.py` | Метрики сети подов, места в `volumes/`, GPU (nvidia-smi), тревог Alertmanager |
| Данные | `volumes/logs/{prometheus,alertmanager,grafana}` |

## Адреса

| Сервис | Адрес | Вход |
|---|---|---|
| Grafana | https://grafana.local | Vault `logs/grafana` |
| Prometheus | `logs-prometheus.logs:9090` | — |
| Jaeger | https://jaeger.local | — |
| Jaeger OTLP | `jaeger.logs:4317` (gRPC), `jaeger.logs:4318` (HTTP) | — |
| Alertmanager | `logs-alertmanager.logs:9093` | — |

## Команды

- Для применения изменений: `./cluster.sh up`
- Для создания тестовой тревоги: `kubectl exec -n logs alertmanager-logs-alertmanager-0 -c alertmanager -- amtool alert add TestAlert severity=warning --annotation=summary="Проверка" --alertmanager.url=http://localhost:9093`
- Для просмотра журнала Alertmanager: `kubectl logs -n logs alertmanager-logs-alertmanager-0 -c alertmanager --tail=20`

## Важно

- Почта отправителя — Vault `logs/smtp`: `username` — адрес ящика, `password` — пароль приложения почты.
- Сервер, отправитель и получатели — `alertmanager.config` в `values.yaml`.
- Тестовая тревога приходит письмом примерно через 30 секунд и закрывается сама через 5 минут.
- Тревоги на дашборде — из Alertmanager (сборщик `platform-exporter`, раз в 15 секунд): из правил Prometheus и отправленные вручную.
- Стартовая страница Grafana — дашборд Platform overview: тревоги, узлы, CPU, RAM, диск, сеть и GPU по namespace, подключения, запросы и размер баз.
- Загрузку GPU по процессам драйвер в WSL2 не отдаёт: GPU и VRAM показаны по узлу, по подам llama.cpp — токены/с, запросы, CPU и RAM.
- Проценты CPU и памяти узлов на Platform overview — от лимитов узлов в `terraform/variables.tf` (их передаёт Ansible), как в Docker Desktop.
- Графики CPU и памяти контейнеров в стандартных дашбордах пусты: в minikube с Docker cAdvisor не видит контейнеры.
- Веб-интерфейсов Prometheus и Alertmanager нет: тревоги — таблица внизу Platform overview и Grafana → Alerting → Alert rules, запросы PromQL — Grafana → Explore.

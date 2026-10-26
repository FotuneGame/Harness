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
| Данные | `volumes/logs/{prometheus,alertmanager,grafana}` |

## Адреса

| Сервис | Адрес | Вход |
|---|---|---|
| Grafana | https://grafana.local | Vault `logs/grafana` |
| Prometheus | https://prometheus.local | — |
| Jaeger | https://jaeger.local | — |
| Jaeger OTLP | `jaeger.logs:4317` (gRPC), `jaeger.logs:4318` (HTTP) | — |
| Alertmanager | `logs-alertmanager.logs:9093` | — |

## Команды

- Для применения изменений: `./cluster.sh up`
- Для проверки отправки писем: `kubectl exec -n logs alertmanager-logs-alertmanager-0 -c alertmanager -- amtool alert add TestAlert severity=warning --annotation=summary="Проверка" --alertmanager.url=http://localhost:9093`
- Для просмотра журнала Alertmanager: `kubectl logs -n logs alertmanager-logs-alertmanager-0 -c alertmanager --tail=20`

## Важно

- Почта отправителя — Vault `logs/smtp`: `username` — адрес ящика, `password` — пароль приложения почты.
- Сервер, отправитель и получатели — `alertmanager.config` в `values.yaml`.
- Тестовое письмо приходит примерно через 30 секунд.
- Стартовая страница Grafana — дашборд Platform overview: тревоги, узлы, namespace, базы.
- Графики CPU и памяти контейнеров в стандартных дашбордах пусты: в minikube с Docker cAdvisor не видит контейнеры.
- Веб-интерфейса Alertmanager нет, тревоги видны в Grafana и в письмах.

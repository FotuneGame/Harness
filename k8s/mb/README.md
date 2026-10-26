# mb: Kafka окружения

## Состав

| Параметр | Значение |
|---|---|
| Релизы | `mb-dev`, `mb-stage`, `mb-prod` |
| Namespace | `mb-<env>` |
| Узел | `core` |
| Charts | [kafka](https://github.com/bitnami/charts/tree/main/bitnami/kafka), [kafka-ui](https://github.com/kafbat/helm-charts) |
| Внутренний адрес | `kafka.mb-<env>:9092` |
| Веб-интерфейс | `https://platform.local/<env>/kafka` |
| Данные | `volumes/mb/<env>/kafka` |

## Команды

- Для установки окружения: `./cluster.sh up --dev`
- Для просмотра подов: `kubectl get pods -n mb-dev`

## Важно

- Kafka работает без авторизации, доступна только подам своего окружения.
- Kafka UI без авторизации: не открывайте `ports open 0.0.0.0` в общей сети.

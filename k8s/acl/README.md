# acl: Keycloak окружения

## Состав

| Параметр | Значение |
|---|---|
| Релизы | `acl-dev`, `acl-stage`, `acl-prod` |
| Namespace | `acl-<env>` |
| Узел | `core` |
| Chart | [keycloak](https://github.com/bitnami/charts/tree/main/bitnami/keycloak) |
| Внутренний адрес | `keycloak.acl-<env>:8080/<env>/keycloak` |
| Веб-интерфейс | `https://platform.local/<env>/keycloak` |
| Вход администратора | Vault `acl/<env>/keycloak` |
| База | PostgreSQL `db-<env>`, Vault `db/<env>/keycloak` |

## Команды

- Для установки окружения: `./cluster.sh up --dev`
- Для просмотра журнала: `kubectl logs -n acl-dev statefulset/keycloak`

## Важно

- Своих томов нет, данные хранятся в PostgreSQL окружения.
- Без `db-<env>` Keycloak не запускается.

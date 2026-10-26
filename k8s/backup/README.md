# backup: резервные копии

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-backup` |
| Namespace | `backup` |
| Узел | `core` |
| Charts | [k8up](https://github.com/k8up-io/k8up), [minio](https://github.com/bitnami/charts/tree/main/bitnami/minio) |
| `templates/schedules.yaml` | Schedule K8up в каждом namespace из `schedule.namespaces` |
| `restore/` | Шаблоны `./cluster.sh restore` |
| Расписание | каждый день в 02:00 UTC |
| Хранение | 7 последних, 7 ежедневных |
| Данные | `volumes/backups/volumes/<путь как в volumes>` |
| Пароль шифрования | Vault `backup/restic` |

## Команды

- Для просмотра списка копий: `./cluster.sh backups`
- Для восстановления PVC из последней копии: `./cluster.sh restore db-dev data-postgresql-0`
- Для восстановления PVC из конкретной копии: `./cluster.sh restore proxy tls e92f23ae`

## Важно

- Пропущенную копию (сервер был выключен) создают `start` и `up`.
- Восстановление останавливает сервисы с этим PVC и запускает их снова.
- Прежние данные остаются в `.before-restore-<время>` внутри тома, удалите их после проверки.
- Без Vault `backup/restic` копии не восстановить.
- Веб-интерфейса MinIO нет.

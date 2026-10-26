# foundation: namespace и тома

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-foundation` |
| Namespace релиза | `default` |
| Chart | свой (`templates/`) |
| `templates/namespaces.yaml` | Namespace, метка `platform.env`, NetworkPolicy окружений |
| `templates/storage.yaml` | StorageClass `local`, PersistentVolume `pv-<путь>` |

## Настройки (`values.yaml`)

| Ключ | Значение |
|---|---|
| `namespaces` | Общие namespace |
| `environments.names` | Окружения: `dev`, `stage`, `prod` |
| `environments.folders` | Папки окружений, узел, tolerations, тома |
| `environments.allowNamespaces` | Namespace с доступом к окружениям: `logs`, `proxy` |
| `environments.usedBy` | Исключения сети: `vcs` → PostgreSQL и Redis `db-prod` |
| `volumes` | Тома общих папок |

## Команды

- Для применения изменений: `./cluster.sh up`
- Для просмотра томов: `kubectl get pv`
- Для просмотра NetworkPolicy окружения: `kubectl get networkpolicy -n db-dev`

## Важно

- PersistentVolume — hostPath `/volumes/<путь>`, политика Retain: данные остаются в `volumes/` после удаления PVC.
- Новый том: запись в `volumes` или `environments.folders.<папка>.volumes` (`claim` — имя PVC из chart) и каталог с `.gitkeep` в `volumes/`.

# vcs: GitLab

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `gitlab` |
| Namespace | `vcs` |
| Узел | `core` |
| Charts | [gitlab](https://gitlab.com/gitlab-org/charts/gitlab), [minio](https://github.com/bitnami/charts/tree/main/bitnami/minio) |
| `templates/registry.yaml` | Container Registry (`registry:2`) |
| База и Redis | PostgreSQL и Redis (база 1) в `db-prod` |
| Данные | `volumes/vcs/{gitaly,registry,minio,rails}` |

## Адреса

| Сервис | Адрес | Вход |
|---|---|---|
| GitLab | https://gitlab.local | Vault `vcs/gitlab-root` |
| Container Registry | https://registry.local | токен GitLab |

## Команды

- Для установки и обновления: `./cluster.sh up`
- Для входа в registry: `docker login registry.local`
- Для отправки проекта: `git push https://gitlab.local/<группа>/<проект>.git`

## Важно

- `volumes/vcs/rails/gitlab-rails-secret.json` — ключи шифрования базы: без них GitLab отвечает ошибкой 500.
- PostgreSQL и Redis `db-prod` ставятся всегда, даже без `--prod`.
- https://registry.local — только API, образы видны в GitLab: проект → Deploy → Container Registry.
- В CI образы собираются через kaniko с `--registry-certificate registry.local=/etc/docker/certs.d/registry.local/ca.crt`.

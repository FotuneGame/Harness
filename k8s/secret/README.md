# secret: Vault

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-secret` |
| Namespace | `secret` |
| Узел | `core` |
| Charts | [vault](https://github.com/hashicorp/vault-helm), [vault-secrets-operator](https://github.com/hashicorp/vault-secrets-operator) |
| `templates/vault-secrets.yaml` | VaultStaticSecret по списку `secrets` |
| Адрес | https://vault.local |
| Вход | метод Userpass, `admin` |
| Данные | `volumes/secret` |

## Секреты, заполняемые вручную

| Путь Vault | Ключи | Для чего |
|---|---|---|
| `logs/smtp` | `username`, `password` | Почта Alertmanager |
| `cicd/gitlab-runner` | `runner-token`, `runner-registration-token` | GitLab Runner |
| `cicd/argocd-gitlab` | `type`, `url`, `username`, `password` | Доступ Argo CD к GitLab |
| `vcs/registry` | `username`, `password` | Secret `gitlab-registry` в `app-<env>` |

## Команды

- Для разблокировки Vault: `./cluster.sh unseal`
- Для применения изменений списка секретов: `./cluster.sh up`
- Для проверки секретов в namespace: `kubectl get vaultstaticsecret -n app-dev`

## Важно

- 5 unseal key и пароль `admin` выводятся один раз при первом `up`, сохраните их.
- После каждого запуска Vault запечатан: `start`, `up` и `unseal` просят 3 ключа.
- Секрет Kubernetes появляется через 1–2 минуты после записи в Vault.
- Остальные пароли создаются при первом `up` (`platform_vault_seed` в `ansible/roles/platform/defaults/main.yml`).
- Удаление `volumes/secret` теряет все пароли: удаляйте `volumes/` только целиком.

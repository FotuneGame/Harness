# cicd: Argo CD, GitLab Runner, Kyverno

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-cicd` |
| Namespace | `cicd` |
| Узел | `core` |
| Charts | [argo-cd](https://github.com/argoproj/argo-helm), [gitlab-runner](https://gitlab.com/gitlab-org/charts/gitlab-runner), [kyverno](https://github.com/kyverno/kyverno) |
| Адрес Argo CD | https://argocd.local |
| Вход Argo CD | Vault `cicd/argocd` |

## Секреты Vault

| Путь | Ключи | Результат |
|---|---|---|
| `cicd/gitlab-runner` | `runner-token`, `runner-registration-token` | GitLab Runner включён |
| `cicd/argocd-gitlab` | `type=git`, `url=http://gitlab-webservice-default.vcs.svc.cluster.local:8181/<группа>`, `username`, `password` | Argo CD читает репозитории группы |

## Команды

- Для применения изменений: `./cluster.sh up`
- Для регистрации приложения в Argo CD: `kubectl apply -f example/node/deploy/argocd-dev.yaml`
- Для просмотра приложений: `kubectl get applications -n cicd`

## Важно

- Токен раннера: GitLab → Admin area → CI/CD → Runners → Create instance runner.
- Пароль для `cicd/argocd-gitlab` — personal access token со scope `read_repository`.
- Без `cicd/gitlab-runner` GitLab Runner выключен; после записи токена выполните `./cluster.sh up`.
- Подключение Argo CD к GitLab подхватывается за 1–2 минуты или после `./cluster.sh up`.
- Kyverno монтирует `/app-data` подам `app-<env>` (политика из `k8s/app`).
- Задачи CI запускаются без привилегий, docker-in-docker не работает.

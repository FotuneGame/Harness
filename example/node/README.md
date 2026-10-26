# node-example

## Команды

- Для установки зависимостей: `npm install`
- Для проброса сервисов dev и создания `.env` (терминал 1): `npm run dev`
- Для запуска с документацией на http://localhost:3000/docs (терминал 2): `npm start`
- Для запуска тестов без кластера: `npm test`
- Для проверки кода: `npm run lint`
- Для регистрации приложения dev в Argo CD: `kubectl apply -f deploy/argocd-dev.yaml`
- Для проверки пода в кластере: `kubectl get pods -n app-dev`
- Для проброса приложения из кластера на http://localhost:81: `kubectl port-forward -n app-dev svc/node-example 81:80`

## Развёртывание

| Шаг | Действие |
|---|---|
| 1 | Группа `main` и проект `node` в GitLab |
| 2 | GitLab Runner: токен в Vault `cicd/gitlab-runner`, `./cluster.sh up` |
| 3 | Argo CD: personal access token (`read_repository`) в Vault `cicd/argocd-gitlab` |
| 4 | Group access token → переменная CI/CD группы `GITOPS_TOKEN` (Masked) |
| 5 | Deploy token группы (`read_registry`) в Vault `vcs/registry` |
| 6 | `image` в `deploy/values.yaml`, `repoURL` в `deploy/argocd-*.yaml` |
| 7 | `git push` в `https://gitlab.local/main/node.git`, pipeline проходит полностью |
| 8 | `kubectl apply -f deploy/argocd-dev.yaml` |
| 9 | Проверка: http://localhost:81/health после проброса |

## Окружения

| Окружение | Запуск | Регистрация в Argo CD |
|---|---|---|
| dev | push в основную ветку | `kubectl apply -f deploy/argocd-dev.yaml` |
| stage | ручной `deploy-stage` в pipeline | `kubectl apply -f deploy/argocd-stage.yaml` |
| prod | тег версии и ручной `deploy-prod` | `kubectl apply -f deploy/argocd-prod.yaml` |

## Важно

- Шаги 1–5 выполняются один раз, подробно — в «Руководство пользователя.docx».
- Регистрация stage и prod — после их первого pipeline.
- Таблицы PostgreSQL создаются по `*.entity.ts` при запуске (`synchronize`), для важных данных нужны миграции TypeORM.

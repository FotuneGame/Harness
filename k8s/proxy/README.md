# proxy: NGINX Ingress

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-proxy` |
| Namespace | `proxy` |
| Узел | `core` |
| Chart | [ingress-nginx](https://github.com/kubernetes/ingress-nginx) |
| `templates/routes.yaml` | Ingress по списку `routes` |
| `templates/node-hosts.yaml` | DaemonSet: имена `*.local` и CA registry на узлах |
| Сертификат | `volumes/proxy/tls` |

## Адреса

| Адрес | Сервис |
|---|---|
| https://gitlab.local | GitLab |
| https://registry.local | Container Registry (API) |
| https://vault.local | Vault |
| https://argocd.local | Argo CD |
| https://grafana.local | Grafana |
| https://jaeger.local | Jaeger |
| `https://platform.local/<env>/<сервис>` | pgadmin, redis, clickhouse, kibana, kafka, keycloak, llama |

## Команды

- Для открытия адресов на этом компьютере: `./cluster.sh ports open`
- Для открытия адресов в локальной сети: `./cluster.sh ports open 0.0.0.0`
- Для открытия адресов одного окружения: `./cluster.sh ports open --dev`
- Для закрытия адресов окружения: `./cluster.sh ports close --dev`
- Для закрытия всех адресов: `./cluster.sh ports close`
- Для доверия сертификату в Windows (из WSL): `certutil.exe -user -addstore Root "$(wslpath -w volumes/proxy/tls/ca.crt)"`
- Для доверия сертификату в Ubuntu: `sudo cp volumes/proxy/tls/ca.crt /usr/local/share/ca-certificates/platform.crt && sudo update-ca-certificates`

## Важно

- Новый адрес — запись в `routes`; имя попадает в hosts и сертификат при `./cluster.sh up`.
- `stripPath: true` убирает путь перед передачей сервису.
- После установки сертификата перезапустите браузер.
- `ports open 0.0.0.0` открывает сервисы в сеть, часть из них без авторизации.

#!/usr/bin/env bash
# Локальная разработка против сервисов кластера: пишет .env с паролями из
# Secret namespace app и пробрасывает порты (Ctrl+C — закрыть).
# Kafka снаружи кластера недоступна (брокер сообщает внутренний адрес).
set -euo pipefail
cd "$(dirname "$0")/.."

secret() { kubectl get secret -n app "$1" -o "jsonpath={.data.$2}" | base64 -d; }

cat > .env <<EOF
POSTGRES_HOST=localhost
POSTGRES_USER=$(secret postgresql-credentials username)
POSTGRES_PASSWORD=$(secret postgresql-credentials password)
POSTGRES_DB=$(secret postgresql-credentials username)
REDIS_HOST=localhost
REDIS_PASSWORD=$(secret redis-credentials password)
CLICKHOUSE_URL=http://localhost:8123
CLICKHOUSE_USER=$(secret clickhouse-credentials username)
CLICKHOUSE_PASSWORD=$(secret clickhouse-credentials password)
CLICKHOUSE_DB=$(secret clickhouse-credentials username)
ELASTICSEARCH_URL=http://localhost:9200
S3_URL=http://localhost:9000
S3_ACCESS_KEY=$(secret minio-credentials username)
S3_SECRET_KEY=$(secret minio-credentials password)
LLM_URL=http://localhost:8081
KEYCLOAK_ISSUER=https://keycloak.local/realms/master
KEYCLOAK_JWKS_URL=http://localhost:8080/realms/master/protocol/openid-connect/certs
OTLP_URL=http://localhost:4318
EOF
echo ".env записан. Запуск приложения в другом терминале: npm start"

trap 'kill 0' EXIT
kubectl port-forward -n db svc/postgresql 5432 &
kubectl port-forward -n db svc/redis-master 6379 &
kubectl port-forward -n db svc/clickhouse 8123 &
kubectl port-forward -n db svc/elasticsearch 9200 &
kubectl port-forward -n backup svc/minio 9000 &
kubectl port-forward -n llm svc/llama 8081:8080 &
kubectl port-forward -n acl svc/keycloak 8080 &
kubectl port-forward -n logs svc/jaeger 4318 &
wait

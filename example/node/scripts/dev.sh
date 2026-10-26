#!/usr/bin/env bash
# Kafka снаружи кластера недоступна: брокер сообщает внутренний адрес.
set -euo pipefail
cd "$(dirname "$0")/.."

secret() { kubectl get secret -n app-dev "$1" -o "jsonpath={.data.$2}" | base64 -d; }

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
LLM_URL=http://localhost:8081/dev/llama
KEYCLOAK_ISSUER=https://platform.local/dev/keycloak/realms/master
KEYCLOAK_JWKS_URL=http://localhost:8080/dev/keycloak/realms/master/protocol/openid-connect/certs
OTLP_URL=http://localhost:4318
EOF
echo ".env записан. Запуск приложения в другом терминале: npm start"

trap 'kill 0' EXIT
kubectl port-forward -n db-dev svc/postgresql 5432 &
kubectl port-forward -n db-dev svc/redis-master 6379 &
kubectl port-forward -n db-dev svc/clickhouse 8123 &
kubectl port-forward -n db-dev svc/elasticsearch 9200 &
kubectl port-forward -n llm-dev svc/llama 8081:8080 &
kubectl port-forward -n acl-dev svc/keycloak 8080 &
kubectl port-forward -n logs svc/jaeger 4318 &
wait

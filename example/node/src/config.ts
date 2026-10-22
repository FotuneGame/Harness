// Настройки из переменных окружения. В кластере их задаёт deploy/ (пароли —
// Secret из Vault), локально — файл .env (scripts/dev.sh). Пустой адрес сервиса
// выключает его: приложение работает без него, /health показывает "disabled".
try {
  process.loadEnvFile();
} catch {
  // .env нет: переменные уже в окружении.
}

const env = (name: string, fallback = '') => process.env[name] || fallback;

export const config = {
  name: env('APP_NAME', 'node-example'),
  port: Number(env('PORT', '3000')),
  // Постоянная папка приложения: в кластере volumes/app/<приложение>.
  appDataPath: env('APP_DATA_PATH', './app-data'),

  postgres: {
    host: env('POSTGRES_HOST', 'localhost'),
    port: Number(env('POSTGRES_PORT', '5432')),
    username: env('POSTGRES_USER', 'app'),
    password: env('POSTGRES_PASSWORD'),
    database: env('POSTGRES_DB', 'app'),
  },
  redis: {
    host: env('REDIS_HOST'),
    password: env('REDIS_PASSWORD'),
  },
  clickhouse: {
    url: env('CLICKHOUSE_URL'),
    username: env('CLICKHOUSE_USER', 'app'),
    password: env('CLICKHOUSE_PASSWORD'),
    database: env('CLICKHOUSE_DB', 'app'),
  },
  elasticsearch: {
    url: env('ELASTICSEARCH_URL'),
  },
  kafka: {
    brokers: env('KAFKA_BROKERS').split(',').filter(Boolean),
  },
  s3: {
    url: env('S3_URL'),
    accessKey: env('S3_ACCESS_KEY'),
    secretKey: env('S3_SECRET_KEY'),
    bucket: env('S3_BUCKET', 'app'),
  },
  llm: {
    url: env('LLM_URL'),
    model: env('LLM_MODEL', 'Qwen2.5-0.5B-Instruct'),
  },
  keycloak: {
    issuer: env('KEYCLOAK_ISSUER'),
    jwksUrl: env('KEYCLOAK_JWKS_URL'),
  },
  tracing: {
    url: env('OTLP_URL'),
  },
};

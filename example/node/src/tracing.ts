// Трейсы HTTP-запросов и вызовов PostgreSQL, Redis, Kafka и др. в Jaeger.
// Импортируется первым в main.ts: инструментация подключается до библиотек.
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { config } from './config';

if (config.tracing.url) {
  const sdk = new NodeSDK({
    serviceName: config.name,
    traceExporter: new OTLPTraceExporter({
      url: `${config.tracing.url}/v1/traces`,
    }),
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-fs': { enabled: false },
      }),
    ],
  });
  sdk.start();
  process.once('SIGTERM', () => void sdk.shutdown());
}

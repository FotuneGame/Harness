import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { DataSource } from 'typeorm';
import { ClickHouseService } from '../src/connections/clickhouse.service';
import { ElasticsearchService } from '../src/connections/elasticsearch.service';
import { KafkaService } from '../src/connections/kafka.service';
import { KeycloakService } from '../src/connections/keycloak.service';
import { LlmService } from '../src/connections/llm.service';
import { RedisService } from '../src/connections/redis.service';
import { S3Service } from '../src/connections/s3.service';
import { HealthController } from '../src/health/health.controller';

// Пример теста: контроллер работает без настоящих сервисов — они заменены
// заглушками, PostgreSQL отвечает так, как задано в тесте.
describe('HealthController', () => {
  const query = jest.fn();
  const disabled = (name: string) => ({ name, enabled: false });
  let app: INestApplication;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      controllers: [HealthController],
      providers: [
        { provide: DataSource, useValue: { query } },
        { provide: RedisService, useValue: disabled('redis') },
        { provide: ClickHouseService, useValue: disabled('clickhouse') },
        { provide: ElasticsearchService, useValue: disabled('elasticsearch') },
        { provide: KafkaService, useValue: disabled('kafka') },
        { provide: S3Service, useValue: disabled('s3') },
        { provide: LlmService, useValue: disabled('llm') },
        { provide: KeycloakService, useValue: disabled('keycloak') },
      ],
    }).compile();
    app = module.createNestApplication();
    await app.init();
  });

  afterEach(() => app.close());

  it('GET /health/live — процесс отвечает', () =>
    request(app.getHttpServer())
      .get('/health/live')
      .expect(200, { status: 'ok' }));

  it('GET /health — PostgreSQL доступен, выключенные сервисы disabled', async () => {
    query.mockResolvedValue([]);
    const { body } = await request(app.getHttpServer())
      .get('/health')
      .expect(200);
    expect(body.services.postgres).toBe('ok');
    expect(body.services.redis).toBe('disabled');
  });

  it('GET /health — ошибка PostgreSQL даёт 503', async () => {
    query.mockRejectedValue(new Error('нет связи'));
    const { body } = await request(app.getHttpServer())
      .get('/health')
      .expect(503);
    expect(body.services.postgres).toBe('error: нет связи');
  });
});

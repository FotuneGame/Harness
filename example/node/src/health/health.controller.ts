import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { access, constants, mkdir } from 'node:fs/promises';
import { DataSource } from 'typeorm';
import { config } from '../config';
import { ClickHouseService } from '../connections/clickhouse.service';
import { Connection } from '../connections/connection';
import { ElasticsearchService } from '../connections/elasticsearch.service';
import { KafkaService } from '../connections/kafka.service';
import { KeycloakService } from '../connections/keycloak.service';
import { LlmService } from '../connections/llm.service';
import { RedisService } from '../connections/redis.service';
import { S3Service } from '../connections/s3.service';

@ApiTags('health')
@Controller('health')
export class HealthController {
  private readonly connections: Connection[];

  constructor(
    dataSource: DataSource,
    redis: RedisService,
    clickhouse: ClickHouseService,
    elasticsearch: ElasticsearchService,
    kafka: KafkaService,
    s3: S3Service,
    llm: LlmService,
    keycloak: KeycloakService,
  ) {
    this.connections = [
      {
        name: 'postgres',
        enabled: true,
        ping: () => dataSource.query('SELECT 1'),
      },
      redis,
      clickhouse,
      elasticsearch,
      kafka,
      s3,
      llm,
      keycloak,
      {
        name: 'app-data',
        enabled: true,
        ping: async () => {
          await mkdir(config.appDataPath, { recursive: true });
          await access(config.appDataPath, constants.W_OK);
        },
      },
    ];
  }

  // Проба Kubernetes: процесс отвечает.
  @Get('live')
  live() {
    return { status: 'ok' };
  }

  // Состояние всех подключений: ok, disabled или текст ошибки.
  @Get()
  async check() {
    const services: Record<string, string> = {};
    await Promise.all(
      this.connections.map(async (connection) => {
        services[connection.name] = await HealthController.status(connection);
      }),
    );
    const failed = Object.values(services).some((s) => s.startsWith('error'));
    if (failed) throw new ServiceUnavailableException({ services });
    return { services };
  }

  private static async status(connection: Connection) {
    if (!connection.enabled) return 'disabled';
    const timeout = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('нет ответа 5 с')), 5000).unref(),
    );
    try {
      await Promise.race([connection.ping(), timeout]);
      return 'ok';
    } catch (error) {
      return `error: ${(error as Error).message}`;
    }
  }
}

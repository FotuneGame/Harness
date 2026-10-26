import { Global, Module } from '@nestjs/common';
import { ClickHouseService } from './clickhouse.service';
import { ElasticsearchService } from './elasticsearch.service';
import { KafkaService } from './kafka.service';
import { KeycloakService } from './keycloak.service';
import { LlmService } from './llm.service';
import { RedisService } from './redis.service';
import { S3Service } from './s3.service';

const connections = [
  RedisService,
  ClickHouseService,
  ElasticsearchService,
  KafkaService,
  S3Service,
  LlmService,
  KeycloakService,
];

@Global()
@Module({
  providers: connections,
  exports: connections,
})
export class ConnectionsModule {}

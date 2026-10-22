import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ClickHouseClient, createClient } from '@clickhouse/client';
import { config } from '../config';
import { Connection, ensure } from './connection';

@Injectable()
export class ClickHouseService implements Connection, OnModuleDestroy {
  readonly name = 'clickhouse';
  readonly enabled = Boolean(config.clickhouse.url);
  private readonly clickhouse = this.enabled
    ? createClient({
        url: config.clickhouse.url,
        username: config.clickhouse.username,
        password: config.clickhouse.password,
        database: config.clickhouse.database,
      })
    : null;

  get client(): ClickHouseClient {
    return ensure(this.clickhouse, 'CLICKHOUSE_URL');
  }

  async ping() {
    const result = await this.client.ping();
    if (!result.success) throw result.error;
  }

  async onModuleDestroy() {
    await this.clickhouse?.close();
  }
}

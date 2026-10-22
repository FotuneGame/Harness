import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Client } from '@elastic/elasticsearch';
import { config } from '../config';
import { Connection, ensure } from './connection';

@Injectable()
export class ElasticsearchService implements Connection, OnModuleDestroy {
  readonly name = 'elasticsearch';
  readonly enabled = Boolean(config.elasticsearch.url);
  private readonly elasticsearch = this.enabled
    ? new Client({ node: config.elasticsearch.url })
    : null;

  get client(): Client {
    return ensure(this.elasticsearch, 'ELASTICSEARCH_URL');
  }

  ping() {
    return this.client.ping();
  }

  async onModuleDestroy() {
    await this.elasticsearch?.close();
  }
}

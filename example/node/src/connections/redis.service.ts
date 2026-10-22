import { Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import { config } from '../config';
import { Connection, ensure } from './connection';

@Injectable()
export class RedisService implements Connection, OnModuleDestroy {
  readonly name = 'redis';
  readonly enabled = Boolean(config.redis.host);
  private readonly redis = this.enabled
    ? new Redis({ host: config.redis.host, password: config.redis.password })
    : null;

  get client(): Redis {
    return ensure(this.redis, 'REDIS_HOST');
  }

  ping() {
    return this.client.ping();
  }

  async onModuleDestroy() {
    await this.redis?.quit();
  }
}

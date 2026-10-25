import { Injectable } from '@nestjs/common';
import { Client } from 'minio';
import { Readable } from 'node:stream';
import { config } from '../config';
import { Connection, ensure } from './connection';

// Файлы в MinIO (S3): bucket config.s3.bucket, доступ только к нему.
@Injectable()
export class S3Service implements Connection {
  readonly name = 's3';
  readonly enabled = Boolean(config.s3.url);
  private readonly s3 = this.enabled ? S3Service.connect() : null;

  get client(): Client {
    return ensure(this.s3, 'S3_URL');
  }

  async put(key: string, body: Buffer, contentType: string) {
    await this.client.putObject(config.s3.bucket, key, body, body.length, {
      'Content-Type': contentType,
    });
  }

  get(key: string): Promise<Readable> {
    return this.client.getObject(config.s3.bucket, key);
  }

  async ping() {
    if (!(await this.client.bucketExists(config.s3.bucket))) {
      throw new Error(`Нет bucket ${config.s3.bucket}`);
    }
  }

  private static connect() {
    const url = new URL(config.s3.url);
    return new Client({
      endPoint: url.hostname,
      port: Number(url.port) || undefined,
      useSSL: url.protocol === 'https:',
      accessKey: config.s3.accessKey,
      secretKey: config.s3.secretKey,
    });
  }
}

import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Consumer, Kafka, logLevel, Producer } from 'kafkajs';
import { config } from '../config';
import { Connection, ensure } from './connection';

@Injectable()
export class KafkaService implements Connection, OnModuleDestroy {
  readonly name = 'kafka';
  readonly enabled = config.kafka.brokers.length > 0;
  private readonly kafka = this.enabled
    ? new Kafka({
        clientId: config.name,
        brokers: config.kafka.brokers,
        logLevel: logLevel.WARN,
      })
    : null;
  private producer?: Promise<Producer>;
  private readonly consumers: Consumer[] = [];

  get client(): Kafka {
    return ensure(this.kafka, 'KAFKA_BROKERS');
  }

  async send(topic: string, message: unknown) {
    this.producer ??= this.connectProducer();
    const producer = await this.producer;
    await producer.send({
      topic,
      messages: [{ value: JSON.stringify(message) }],
    });
  }

  // Группа потребителей на топик: каждое сообщение обработает один под.
  async subscribe<T>(topic: string, handler: (message: T) => Promise<unknown>) {
    await this.createTopic(topic);
    const consumer = this.client.consumer({
      groupId: `${config.name}-${topic}`,
    });
    this.consumers.push(consumer);
    await consumer.connect();
    await consumer.subscribe({ topic });
    await consumer.run({
      eachMessage: async ({ message }) => {
        await handler(JSON.parse(message.value?.toString() ?? 'null') as T);
      },
    });
  }

  async ping() {
    const admin = this.client.admin();
    await admin.connect();
    try {
      await admin.listTopics();
    } finally {
      await admin.disconnect();
    }
  }

  async onModuleDestroy() {
    await Promise.all(this.consumers.map((consumer) => consumer.disconnect()));
    await (await this.producer)?.disconnect();
  }

  private async connectProducer() {
    const producer = this.client.producer();
    await producer.connect();
    return producer;
  }

  private async createTopic(topic: string) {
    const admin = this.client.admin();
    await admin.connect();
    try {
      if (!(await admin.listTopics()).includes(topic)) {
        await admin.createTopics({ topics: [{ topic }], waitForLeaders: true });
      }
    } finally {
      await admin.disconnect();
    }
  }
}

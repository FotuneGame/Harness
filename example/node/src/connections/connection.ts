import { ServiceUnavailableException } from '@nestjs/common';

export interface Connection {
  name: string;
  enabled: boolean;
  ping(): Promise<unknown>;
}

// Клиент выключенного сервиса: ошибка 503 с именем нужной переменной.
export function ensure<T>(client: T | null, setting: string): T {
  if (!client) {
    throw new ServiceUnavailableException(`Сервис не настроен: ${setting}`);
  }
  return client;
}

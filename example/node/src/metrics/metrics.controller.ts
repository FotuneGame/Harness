import { Controller, Get, Header } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { collectDefaultMetrics, Counter, register } from 'prom-client';

// Метрики для Prometheus (ServiceMonitor в deploy/): стандартные метрики Node.js
// и свои, как notesCreated.
collectDefaultMetrics();

export const notesCreated = new Counter({
  name: 'notes_created_total',
  help: 'Созданные заметки',
});

@ApiExcludeController()
@Controller('metrics')
export class MetricsController {
  @Get()
  @Header('Content-Type', register.contentType)
  metrics() {
    return register.metrics();
  }
}

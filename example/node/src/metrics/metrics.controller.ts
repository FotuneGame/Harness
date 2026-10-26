import { Controller, Get, Header } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { collectDefaultMetrics, Counter, register } from 'prom-client';

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

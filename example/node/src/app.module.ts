import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthController } from './auth/auth.controller';
import { config } from './config';
import { ConnectionsModule } from './connections/connections.module';
import { HealthController } from './health/health.controller';
import { MetricsController } from './metrics/metrics.controller';
import { NotesModule } from './notes/notes.module';

@Module({
  imports: [
    // Для данных, которые нельзя терять при изменении схемы, нужны миграции TypeORM.
    TypeOrmModule.forRoot({
      type: 'postgres',
      ...config.postgres,
      autoLoadEntities: true,
      synchronize: true,
    }),
    ConnectionsModule,
    NotesModule,
  ],
  controllers: [HealthController, MetricsController, AuthController],
})
export class AppModule {}

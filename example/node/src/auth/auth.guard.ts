import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { JWTPayload } from 'jose';
import { KeycloakService } from '../connections/keycloak.service';

export type AuthRequest = Request & { user: JWTPayload };

// Пропускает запросы с действительным токеном Keycloak:
// заголовок Authorization: Bearer <access token>. Данные токена — request.user.
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly keycloak: KeycloakService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const [type, token] = request.headers.authorization?.split(' ') ?? [];
    if (type !== 'Bearer' || !token) {
      throw new UnauthorizedException('Нужен заголовок Authorization: Bearer');
    }
    try {
      request.user = await this.keycloak.verify(token);
    } catch (error) {
      if (!this.keycloak.enabled) throw error;
      throw new UnauthorizedException('Неверный или просроченный токен');
    }
    return true;
  }
}

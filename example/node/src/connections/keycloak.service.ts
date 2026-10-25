import { Injectable } from '@nestjs/common';
import { createRemoteJWKSet, JWTPayload, jwtVerify } from 'jose';
import { config } from '../config';
import { Connection, ensure } from './connection';

// Проверка токенов Keycloak: подпись по ключам realm (JWKS) и издатель.
@Injectable()
export class KeycloakService implements Connection {
  readonly name = 'keycloak';
  readonly enabled = Boolean(config.keycloak.jwksUrl);
  private readonly jwks = this.enabled
    ? createRemoteJWKSet(new URL(config.keycloak.jwksUrl))
    : null;

  async verify(token: string): Promise<JWTPayload> {
    const { payload } = await jwtVerify(
      token,
      ensure(this.jwks, 'KEYCLOAK_JWKS_URL'),
      { issuer: config.keycloak.issuer },
    );
    return payload;
  }

  async ping() {
    const response = await fetch(config.keycloak.jwksUrl);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
  }
}

import { Controller, Get, Req, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthGuard, type AuthRequest } from './auth.guard';

@ApiTags('auth')
@Controller()
export class AuthController {
  @Get('me')
  @UseGuards(AuthGuard)
  @ApiBearerAuth()
  me(@Req() request: AuthRequest) {
    return request.user;
  }
}

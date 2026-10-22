import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class CreateNoteDto {
  @ApiProperty({ example: 'Покупки' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  title: string;

  @ApiProperty({ example: 'Молоко, хлеб, сыр' })
  @IsString()
  text: string;
}

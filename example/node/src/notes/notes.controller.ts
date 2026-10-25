import {
  Body,
  Controller,
  Get,
  Param,
  ParseIntPipe,
  Post,
  Query,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { CreateNoteDto } from './create-note.dto';
import { NotesService } from './notes.service';

@ApiTags('notes')
@Controller('notes')
export class NotesController {
  constructor(private readonly notes: NotesService) {}

  @Post()
  create(@Body() dto: CreateNoteDto) {
    return this.notes.create(dto);
  }

  @Get()
  list() {
    return this.notes.list();
  }

  @Get('search')
  search(@Query('q') query: string) {
    return this.notes.search(query);
  }

  @Get('stats')
  stats() {
    return this.notes.stats();
  }

  @Get(':id')
  get(@Param('id', ParseIntPipe) id: number) {
    return this.notes.get(id);
  }

  @Post(':id/file')
  @UseInterceptors(FileInterceptor('file'))
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: { file: { type: 'string', format: 'binary' } },
    },
  })
  attach(
    @Param('id', ParseIntPipe) id: number,
    @UploadedFile() file: Express.Multer.File,
  ) {
    return this.notes.attach(id, file);
  }

  @Get(':id/file')
  async download(@Param('id', ParseIntPipe) id: number) {
    const { name, stream } = await this.notes.download(id);
    return new StreamableFile(stream, {
      disposition: `attachment; filename*=UTF-8''${encodeURIComponent(name)}`,
    });
  }

  @Post(':id/summary')
  summarize(@Param('id', ParseIntPipe) id: number) {
    return this.notes.summarize(id);
  }
}

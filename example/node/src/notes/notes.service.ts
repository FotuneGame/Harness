import {
  Injectable,
  NotFoundException,
  OnApplicationBootstrap,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Readable } from 'node:stream';
import { Repository } from 'typeorm';
import { ClickHouseService } from '../connections/clickhouse.service';
import { ElasticsearchService } from '../connections/elasticsearch.service';
import { KafkaService } from '../connections/kafka.service';
import { LlmService } from '../connections/llm.service';
import { RedisService } from '../connections/redis.service';
import { S3Service } from '../connections/s3.service';
import { notesCreated } from '../metrics/metrics.controller';
import { CreateNoteDto } from './create-note.dto';
import { Note } from './note.entity';

const CACHE_KEY = 'notes:list';
const TOPIC = 'notes.created';
const INDEX = 'notes';

// Выключенные сервисы пропускаются.
@Injectable()
export class NotesService implements OnApplicationBootstrap {
  constructor(
    @InjectRepository(Note) private readonly notes: Repository<Note>,
    private readonly redis: RedisService,
    private readonly elasticsearch: ElasticsearchService,
    private readonly kafka: KafkaService,
    private readonly clickhouse: ClickHouseService,
    private readonly s3: S3Service,
    private readonly llm: LlmService,
  ) {}

  async onApplicationBootstrap() {
    if (!this.kafka.enabled || !this.clickhouse.enabled) return;
    await this.clickhouse.client.command({
      query: `CREATE TABLE IF NOT EXISTS note_events (
        note_id UInt32,
        title String,
        created_at DateTime DEFAULT now()
      ) ENGINE = MergeTree ORDER BY created_at`,
    });
    await this.kafka.subscribe<Note>(TOPIC, (note) =>
      this.clickhouse.client.insert({
        table: 'note_events',
        values: [{ note_id: note.id, title: note.title }],
        format: 'JSONEachRow',
      }),
    );
  }

  async create(dto: CreateNoteDto) {
    const note = await this.notes.save(this.notes.create(dto));
    if (this.redis.enabled) await this.redis.client.del(CACHE_KEY);
    if (this.elasticsearch.enabled) {
      await this.elasticsearch.client.index({
        index: INDEX,
        id: String(note.id),
        document: { title: note.title, text: note.text },
      });
    }
    if (this.kafka.enabled) await this.kafka.send(TOPIC, note);
    notesCreated.inc();
    return note;
  }

  async list(): Promise<Note[]> {
    if (this.redis.enabled) {
      const cached = await this.redis.client.get(CACHE_KEY);
      if (cached) return JSON.parse(cached) as Note[];
    }
    const notes = await this.notes.find({ order: { id: 'DESC' }, take: 100 });
    if (this.redis.enabled) {
      await this.redis.client.set(CACHE_KEY, JSON.stringify(notes), 'EX', 30);
    }
    return notes;
  }

  async get(id: number) {
    const note = await this.notes.findOneBy({ id });
    if (!note) throw new NotFoundException(`Нет заметки ${id}`);
    return note;
  }

  async search(query: string) {
    const result = await this.elasticsearch.client.search<{
      title: string;
      text: string;
    }>({
      index: INDEX,
      ignore_unavailable: true,
      query: { multi_match: { query, fields: ['title', 'text'] } },
    });
    return result.hits.hits.map((hit) => ({
      id: Number(hit._id),
      ...hit._source,
    }));
  }

  async stats() {
    const result = await this.clickhouse.client.query({
      query: `SELECT toDate(created_at) AS day, count() AS notes
        FROM note_events GROUP BY day ORDER BY day`,
      format: 'JSONEachRow',
    });
    return result.json();
  }

  async attach(id: number, file: Express.Multer.File) {
    const note = await this.get(id);
    // multer передаёт имя файла в кодировке latin1.
    const name = Buffer.from(file.originalname, 'latin1').toString('utf8');
    note.file = `notes/${id}/${name}`;
    await this.s3.put(note.file, file.buffer, file.mimetype);
    if (this.redis.enabled) await this.redis.client.del(CACHE_KEY);
    return this.notes.save(note);
  }

  async download(id: number): Promise<{ name: string; stream: Readable }> {
    const { file } = await this.get(id);
    if (!file) throw new NotFoundException(`У заметки ${id} нет файла`);
    return { name: file.split('/').pop()!, stream: await this.s3.get(file) };
  }

  async summarize(id: number) {
    const note = await this.get(id);
    const summary = await this.llm.chat(
      `Кратко перескажи заметку в одном предложении.\n\n${note.title}\n${note.text}`,
    );
    return { summary };
  }
}

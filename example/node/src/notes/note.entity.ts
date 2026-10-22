import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';

// Таблица note в PostgreSQL.
@Entity()
export class Note {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  title: string;

  @Column('text')
  text: string;

  // Ключ прикреплённого файла в S3.
  @Column({ type: 'varchar', nullable: true })
  file: string | null;

  @CreateDateColumn()
  createdAt: Date;
}

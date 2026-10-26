import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';

@Entity()
export class Note {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  title: string;

  @Column('text')
  text: string;

  @Column({ type: 'varchar', nullable: true })
  file: string | null;

  @CreateDateColumn()
  createdAt: Date;
}

import { Injectable } from '@nestjs/common';
import { config } from '../config';
import { Connection, ensure } from './connection';

@Injectable()
export class LlmService implements Connection {
  readonly name = 'llm';
  readonly enabled = Boolean(config.llm.url);

  async chat(prompt: string): Promise<string> {
    const response = await fetch(`${this.url}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: config.llm.model,
        messages: [{ role: 'user', content: prompt }],
      }),
    });
    if (!response.ok) throw new Error(`LLM: HTTP ${response.status}`);
    const data = (await response.json()) as {
      choices: { message: { content: string } }[];
    };
    return data.choices[0].message.content;
  }

  async ping() {
    const response = await fetch(`${this.url}/health`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
  }

  private get url() {
    return ensure(config.llm.url || null, 'LLM_URL');
  }
}

import createClient from 'openapi-fetch';
import type { paths } from './schema.gen';

export function makeClient(baseUrl: string) {
  return createClient<paths>({ baseUrl });
}

export type { paths } from './schema.gen';

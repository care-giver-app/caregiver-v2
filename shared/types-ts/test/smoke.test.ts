import { describe, expect, it } from 'vitest';
import { makeClient } from '../src/client';

const DEV_URL = process.env.CAREGIVER_DEV_URL;

describe('generated client /health smoke', () => {
  it.runIf(DEV_URL)('returns 200 OK with expected shape', async () => {
    const client = makeClient(DEV_URL!);
    const { data, response } = await client.GET('/health');
    expect(response.status).toBe(200);
    expect(data?.status).toBe('ok');
    expect(typeof data?.version).toBe('string');
    expect(typeof data?.timestamp).toBe('string');
  });
});

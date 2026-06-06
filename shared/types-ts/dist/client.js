import createClient from 'openapi-fetch';
export function makeClient(baseUrl) {
    return createClient({ baseUrl });
}

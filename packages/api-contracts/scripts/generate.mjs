import { readFile, writeFile } from 'node:fs/promises';
const str = { type: 'string' },
  uuid = { type: 'string', format: 'uuid' },
  integer = { type: 'integer' },
  instant = { type: 'string', format: 'date-time' },
  boolean = { type: 'boolean' };
const obj = (properties, required = Object.keys(properties)) => ({
  type: 'object',
  properties,
  required,
  additionalProperties: false,
});
const enumS = (values) => ({ type: 'string', enum: values.split('|') });
const point = obj({
  lat: { type: 'number', minimum: -90, maximum: 90 },
  lng: { type: 'number', minimum: -180, maximum: 180 },
});
const schemas = {
  Point: point,
  Tokens: obj({ accessToken: str, refreshToken: str, expiresIn: integer }),
  BusTrip: {
    type: 'object',
    properties: {
      id: uuid,
      operator_id: uuid,
      route_name: str,
      registration: str,
      status: enumS(
        'SCHEDULED|BOARDING|RUNNING|DELAYED|STOPPED|BREAKDOWN|DIVERTED|CANCELLED|COMPLETED',
      ),
      version: integer,
      departure_at: instant,
      delay_minutes: integer,
      locationQuality: enumS('LIVE|STALE|UNAVAILABLE'),
      recorded_at: { anyOf: [instant, { type: 'null' }] },
      lat: { type: ['number', 'null'] },
      lng: { type: ['number', 'null'] },
      timeSource: { const: 'SCHEDULED' },
      eta: { type: 'null' },
    },
    required: ['id', 'status', 'version'],
  },
  BusStatus: obj({
    status: enumS(
      'SCHEDULED|BOARDING|RUNNING|DELAYED|STOPPED|BREAKDOWN|DIVERTED|CANCELLED|COMPLETED',
    ),
    version: { type: 'integer', minimum: 1 },
    reason: { type: 'string', minLength: 1, maxLength: 240 },
    delayMinutes: { type: 'integer', minimum: 0, maximum: 720 },
  }),
  Location: obj({
    ...point.properties,
    accuracyM: { type: 'integer', minimum: 0, maximum: 100 },
    recordedAt: instant,
  }),
  Error: obj({ statusCode: integer, message: str }),
  Event: obj({
    id: str,
    topic: enumS('bus.created.v1|bus.status.v1|bus.location.v1'),
    version: integer,
    payload: { type: 'object', additionalProperties: true },
    created_at: instant,
  }),
};
const requests = {
  'POST auth/otp/request': obj({ phone: { type: 'string', pattern: '^\\+91[6-9][0-9]{9}$' } }),
  'POST auth/otp/verify': obj({
    challengeId: uuid,
    code: { type: 'string', pattern: '^\\d{6}$' },
    consentVersion: str,
  }),
  'POST auth/refresh': obj({ refreshToken: str }),
  'PATCH me': obj({ name: str, language: enumS('en|ml') }),
  'POST me/data-requests': obj({ kind: enumS('EXPORT|DELETE') }),
  'POST me/device-tokens': obj({ token: str, platform: enumS('android|ios') }),
  'POST bus/trips/:id/status': { $ref: '#/components/schemas/BusStatus' },
  'POST bus/trips/:id/location': { $ref: '#/components/schemas/Location' },
  'POST operator/routes': obj({
    operatorId: uuid,
    name: str,
    stops: {
      type: 'array',
      minItems: 2,
      maxItems: 100,
      items: obj({
        ...point.properties,
        name: str,
        offsetMinutes: { type: 'integer', minimum: 0, maximum: 1440 },
      }),
    },
  }),
  'POST operator/services': obj({
    operatorId: uuid,
    routeVersionId: uuid,
    vehicleId: uuid,
    crewId: uuid,
    departureAt: instant,
    serviceDate: { type: 'string', format: 'date' },
  }),
  'POST shared-trips': obj({
    vehicleId: uuid,
    departureAt: instant,
    capacity: { type: 'integer', minimum: 1, maximum: 12 },
    farePaise: { type: 'integer', minimum: 0 },
    stops: { type: 'array', minItems: 2, items: obj({ ...point.properties, name: str }) },
  }),
  'POST shared-trips/:id/reservations': obj({
    seats: { type: 'integer', minimum: 1, maximum: 12 },
    pickupSequence: { type: 'integer', minimum: 0 },
    dropoffSequence: { type: 'integer', minimum: 1 },
  }),
  'POST shared-trips/:id/status': obj({
    status: enumS('BOARDING|IN_PROGRESS|COMPLETED|CANCELLED'),
  }),
  'POST reservations/:id/boarding': obj({ status: enumS('BOARDED|NO_SHOW') }),
  'POST driver/availability': obj({ online: boolean }),
  'POST bookings': obj({ pickup: point, dropoff: point, category: enumS('AUTO|TAXI') }),
  'POST bookings/:id/accept': obj({ vehicleId: uuid }),
  'POST bookings/:id/status': obj({
    status: enumS('ARRIVED|IN_PROGRESS|COMPLETED|CANCELLED'),
    version: integer,
  }),
};
const source = await readFile(
  new URL('../../../services/api/src/main.ts', import.meta.url),
  'utf8',
);
const paths = {};
for (const m of source.matchAll(/@(Get|Post|Patch|Delete)\('([^']+)'\)/g)) {
  const method = m[1].toUpperCase(),
    p = m[2],
    route = '/' + p.replaceAll(':id', '{id}'),
    k = method + ' ' + p;
  const auth =
    !p.startsWith('auth/otp/') && !['auth/refresh', 'health', 'ready', 'openapi.json'].includes(p);
  const parameters = [];
  if (p.includes(':id')) parameters.push({ name: 'id', in: 'path', required: true, schema: uuid });
  if (p === 'bus/trips')
    for (const name of ['date', 'origin', 'destination'])
      parameters.push({
        name,
        in: 'query',
        required: name === 'date',
        schema: { type: 'string', ...(name === 'date' ? { format: 'date' } : {}) },
      });
  if (p.startsWith('operator/') && method === 'GET')
    parameters.push({ name: 'operatorId', in: 'query', required: true, schema: uuid });
  if (p.endsWith('/events'))
    parameters.push({
      name: 'after',
      in: 'query',
      schema: { type: 'string', pattern: '^[0-9]{1,18}$' },
    });
  if (['POST bookings', 'POST bookings/:id/cash', 'POST shared-trips/:id/reservations'].includes(k))
    parameters.push({
      name: 'Idempotency-Key',
      in: 'header',
      required: true,
      schema: { type: 'string', minLength: 8, maxLength: 100 },
    });
  if (k === 'POST auth/otp/request')
    parameters.push({
      name: 'X-Sandbox-Key',
      in: 'header',
      required: true,
      schema: str,
      description: 'Local fixture-only sandbox access. Production provider not configured.',
    });
  let responseSchema = { type: 'object', additionalProperties: true };
  if (['POST auth/otp/verify', 'POST auth/refresh'].includes(k))
    responseSchema = { $ref: '#/components/schemas/Tokens' };
  if (k === 'GET bus/trips/:id') responseSchema = { $ref: '#/components/schemas/BusTrip' };
  if (['GET bus/trips', 'GET crew/trips'].includes(k))
    responseSchema = { type: 'array', items: { $ref: '#/components/schemas/BusTrip' } };
  if (k === 'GET bus/trips/:id/events')
    responseSchema = { type: 'array', items: { $ref: '#/components/schemas/Event' } };
  if (
    [
      'GET shared-trips',
      'GET driver/shared-trips',
      'GET bookings',
        'GET me/reservations',
      'GET driver/vehicles',
      'GET operator/audit',
    ].includes(k)
  )
    responseSchema = { type: 'array', items: { type: 'object', additionalProperties: true } };
  const responses = {
    [method === 'POST' ? '201' : '200']: {
      description: 'Successful server response',
      content: { 'application/json': { schema: responseSchema } },
    },
  };
  for (const status of ['400', '401', '403', '404', '409', '429', '500'])
    responses[status] = {
      description: 'Rejected request; do not assume a mutation succeeded',
      content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } },
    };
  paths[route] ??= {};
  paths[route][method.toLowerCase()] = {
    operationId: method.toLowerCase() + '_' + p.replaceAll(/[^a-zA-Z0-9]/g, '_'),
    summary: k,
    security: auth ? [{ bearer: [] }] : [],
    parameters,
    ...(requests[k]
      ? {
          requestBody: { required: true, content: { 'application/json': { schema: requests[k] } } },
        }
      : {}),
    responses,
  };
}
await writeFile(
  new URL('../openapi.json', import.meta.url),
  JSON.stringify(
    {
      openapi: '3.1.0',
      info: {
        title: 'RuralConnect API',
        version: '0.1.0',
        description:
          'Development contract. Some peripheral responses remain generic; see DELIVERY_STATUS.md.',
      },
      servers: [{ url: 'http://localhost:3001/v1' }],
      paths,
      components: { securitySchemes: { bearer: { type: 'http', scheme: 'bearer' } }, schemas },
    },
    null,
    2,
  ) + '\n',
);

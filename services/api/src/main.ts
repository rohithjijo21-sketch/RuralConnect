import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import { runtimeConfig } from './config.js';
import { readFile } from 'node:fs/promises';
import { NestFactory } from '@nestjs/core';
import {
  Module,
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  Headers,
  Req,
  Inject,
  ExceptionFilter,
  Catch,
  HttpException,
  ValidationPipe,
} from '@nestjs/common';
import { z, ZodError } from 'zod';
import helmet from 'helmet';
import { WebSocketServer, WebSocket } from 'ws';
import { Auth, phoneSchema } from './auth.js';
import { Bus } from './bus.js';
import { BusOwner } from './bus-owner.js';
import { Bookings } from './bookings.js';
import { PrivateRides } from './private-rides.js';
import { pool } from './db.js';
import { busStates } from './domain.js';
const uuid = z.string().uuid(),
  short = z.string().trim().min(1).max(240),
  date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  instant = z.iso.datetime({ offset: true });
const point = z
  .object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) })
  .strict();
const id = (s: string) => uuid.parse(s);
const key = (s: string) => z.string().min(8).max(100).parse(s);
@Catch()
class Errors implements ExceptionFilter {
  catch(error: any, host: any) {
    const res = host.switchToHttp().getResponse();
    const status =
      error.type === 'entity.too.large'
        ? 413
        : error instanceof SyntaxError && (error as any).status === 400
          ? 400
          : error instanceof ZodError
            ? 400
            : error instanceof HttpException
              ? error.getStatus()
              : error.code === '23505'
                ? 409
                : 500;
    if (status === 500)
      console.error(
        JSON.stringify({ level: 'error', code: error.code ?? 'internal', name: error.name }),
      );
    res.status(status).json({
      statusCode: status,
      requestId: host.switchToHttp().getRequest().requestId,
      message:
        error instanceof ZodError
          ? 'Invalid request'
          : status === 500
            ? 'Internal server error'
            : status === 409
              ? 'Resource conflict'
              : error.message,
    });
  }
}
@Controller('v1')
class Api {
  constructor(
    @Inject(Auth) private auth: Auth,
    @Inject(Bus) private bus: Bus,
    @Inject(Bookings) private bookings: Bookings,
    @Inject(BusOwner) private owner: BusOwner,
    @Inject(PrivateRides) private rides: PrivateRides,
  ) {}
  @Get('openapi.json') async spec() {
    return JSON.parse(
      await readFile(
        new URL('../../../packages/api-contracts/openapi.json', import.meta.url),
        'utf8',
      ),
    );
  }
  @Get('health') health() {
    return { status: 'ok' };
  }
  @Get('ready') async ready() {
    const r = await pool.query(
      "SELECT 1 FROM schema_migrations WHERE name='005_private_rides.sql'",
    );
    if (!r.rowCount) throw new HttpException('Migrations required', 503);
    return { status: 'ready' };
  }
  @Post('auth/otp/request') request(
    @Body() b: unknown,
    @Headers('x-sandbox-key') k: string,
    @Req() req: any,
  ) {
    const v = z.object({ phone: phoneSchema }).strict().parse(b);
    return this.auth.request(v.phone, k ?? '', req.ip ?? 'unknown');
  }
  @Post('auth/otp/verify') verify(@Body() b: unknown) {
    const v = z
      .object({ challengeId: uuid, code: z.string().regex(/^\d{6}$/), consentVersion: short })
      .strict()
      .parse(b);
    return this.auth.verify(v.challengeId, v.code, v.consentVersion);
  }
  @Post('auth/beta/redeem') redeemBeta(@Body() b: unknown, @Req() req: any) {
    const v = z
      .object({
        phone: phoneSchema,
        inviteCode: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        consentVersion: short,
      })
      .strict()
      .parse(b);
    return this.auth.redeemBeta(v.phone, v.inviteCode, v.consentVersion, req.ip ?? 'unknown');
  }
  @Post('auth/refresh') refresh(@Body() b: unknown) {
    return this.auth.refresh(
      z
        .object({ refreshToken: z.string().min(32).max(100) })
        .strict()
        .parse(b).refreshToken,
    );
  }
  @Post('auth/logout') logout(@Headers('authorization') h: string) {
    return this.auth.logout(h);
  }
  @Get('me') async me(@Headers('authorization') h: string) {
    const a = await this.auth.actor(h);
    return {
      ...(await pool.query('SELECT id,name,language FROM users WHERE id=$1', [a.id])).rows[0],
      roles: a.roles,
      operatorIds: (
        await pool.query('SELECT operator_id FROM operator_members WHERE user_id=$1', [a.id])
      ).rows.map((r) => r.operator_id),
    };
  }
  @Patch('me') async profile(@Headers('authorization') h: string, @Body() b: unknown) {
    const a = await this.auth.actor(h),
      v = z
        .object({ name: short, language: z.enum(['en', 'ml']) })
        .strict()
        .parse(b);
    await pool.query('UPDATE users SET name=$1,language=$2 WHERE id=$3', [
      v.name,
      v.language,
      a.id,
    ]);
    return v;
  }
  @Post('me/data-requests') async dataRequest(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    const a = await this.auth.actor(h),
      v = z
        .object({ kind: z.enum(['EXPORT', 'DELETE']) })
        .strict()
        .parse(b);
    return (
      await pool.query(
        'INSERT INTO data_requests(user_id,kind) VALUES($1,$2) RETURNING id,kind,status',
        [a.id, v.kind],
      )
    ).rows[0];
  }
  @Post('me/device-tokens') async device(@Headers('authorization') h: string, @Body() b: unknown) {
    const a = await this.auth.actor(h),
      v = z
        .object({ token: z.string().min(20).max(4096), platform: z.enum(['android', 'ios']) })
        .strict()
        .parse(b);
    await pool.query(
      'INSERT INTO device_tokens(user_id,token,platform) VALUES($1,$2,$3) ON CONFLICT(token) DO UPDATE SET user_id=$1,updated_at=now()',
      [a.id, v.token, v.platform],
    );
    return { registered: true };
  }
  @Get('bus/trips') async trips(
    @Headers('authorization') h: string,
    @Query('date') d: string,
    @Query('origin') o?: string,
    @Query('destination') dest?: string,
  ) {
    await this.auth.actor(h);
    if ((o && !dest) || (!o && dest))
      throw new HttpException('Origin and destination required together', 400);
    return this.bus.search(
      date.parse(d),
      o ? short.parse(o) : undefined,
      dest ? short.parse(dest) : undefined,
    );
  }
  @Get('bus/trips/:id') async trip(@Headers('authorization') h: string, @Param('id') t: string) {
    await this.auth.actor(h);
    return this.bus.detail(id(t));
  }
  @Get('crew/trips') async crew(@Headers('authorization') h: string) {
    const a = await this.auth.actor(h);
    this.auth.require(a, 'BUS_CREW');
    return (
      await pool.query(
        "SELECT t.*,r.name route_name,v.registration FROM trip_instances t JOIN driver_assignments d ON d.trip_id=t.id JOIN route_versions rv ON rv.id=t.route_version_id JOIN bus_routes r ON r.id=rv.route_id JOIN vehicles v ON v.id=t.vehicle_id WHERE d.user_id=$1 AND t.service_date=(now() AT TIME ZONE 'Asia/Kolkata')::date ORDER BY departure_at",
        [a.id],
      )
    ).rows;
  }
  @Post('bus/trips/:id/status') async status(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    const a = await this.auth.actor(h),
      v = z
        .object({
          status: z.enum(busStates),
          reason: short,
          delayMinutes: z.number().int().min(0).max(720).default(0),
          version: z.number().int().positive(),
        })
        .strict()
        .parse(b);
    return this.bus.status(a, id(t), v);
  }
  @Post('bus/trips/:id/location') async location(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    const a = await this.auth.actor(h);
    await this.auth.rate('gps:' + a.id, 60, 60);
    return this.bus.location(
      a,
      id(t),
      point
        .extend({ accuracyM: z.number().int().min(0).max(100), recordedAt: instant })
        .strict()
        .parse(b),
    );
  }
  @Post('bus/trips/:id/subscribe') async subscribe(
    @Headers('authorization') h: string,
    @Param('id') t: string,
  ) {
    const a = await this.auth.actor(h);
    await this.bus.detail(id(t));
    await pool.query(
      'INSERT INTO notification_subscriptions(user_id,trip_id) VALUES($1,$2) ON CONFLICT DO NOTHING',
      [a.id, t],
    );
    return { subscribed: true };
  }
  @Get('bus/trips/:id/events') async events(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Query('after') after = '0',
  ) {
    await this.auth.actor(h);
    await this.bus.detail(id(t));
    const cursor = z
      .string()
      .regex(/^\d{1,18}$/)
      .parse(after);
    return (
      await pool.query(
        'SELECT id,topic,resource_id,version,payload,created_at FROM events WHERE resource_id=$1 AND id>$2 ORDER BY id LIMIT 100',
        [t, cursor],
      )
    ).rows;
  }
  @Get('bus-owner/workspace') ownerWorkspace(@Headers('authorization') h: string) {
    return this.auth.actor(h).then((a) => this.owner.workspace(a));
  }
  @Post('bus-owner/apply') async ownerApply(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    const v = z.object({ name: short }).strict().parse(b);
    return this.owner.register(await this.auth.actor(h), v.name);
  }
  @Post('bus-owner/vehicles') async ownerVehicle(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    const v = z
      .object({
        registration: z
          .string()
          .trim()
          .min(4)
          .max(24)
          .regex(/^[A-Za-z0-9 -]+$/),
        capacity: z.number().int().min(1).max(100),
      })
      .strict()
      .parse(b);
    return this.owner.vehicle(await this.auth.actor(h), v.registration, v.capacity);
  }
  @Post('bus-owner/plans') async ownerPlan(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    const v = z
      .object({
        name: short,
        routeVersionId: uuid,
        vehicleId: uuid,
        crewId: uuid,
        departureTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
        startDate: z.iso.date(),
        endDate: z.iso.date(),
        weekdays: z.array(z.number().int().min(1).max(7)).min(1).max(7),
        excludedDates: z.array(z.iso.date()).max(366),
      })
      .strict()
      .parse(b);
    return this.owner.plan(await this.auth.actor(h), v);
  }
  @Post('bus-owner/plans/:id/publish') async ownerPublish(
    @Headers('authorization') h: string,
    @Param('id') p: string,
    @Body() b: unknown,
  ) {
    const v = z.object({ fromDate: z.iso.date(), toDate: z.iso.date() }).strict().parse(b);
    return this.owner.publish(await this.auth.actor(h), id(p), v.fromDate, v.toDate);
  }
  @Get('operator/resources') async resources(
    @Headers('authorization') h: string,
    @Query('operatorId') op: string,
  ) {
    const a = await this.auth.actor(h);
    const db = await pool.connect();
    try {
      await this.bus.operator(db, a, id(op));
      return {
        vehicles: (
          await db.query(
            "SELECT id,registration,capacity FROM vehicles WHERE operator_id=$1 AND approved AND category='BUS'",
            [op],
          )
        ).rows,
        crew: (
          await db.query(
            "SELECT u.id,u.name FROM users u JOIN operator_members m ON m.user_id=u.id JOIN user_roles r ON r.user_id=u.id WHERE m.operator_id=$1 AND r.role='BUS_CREW'",
            [op],
          )
        ).rows,
        routes: (
          await db.query(
            'SELECT rv.id,r.name FROM route_versions rv JOIN bus_routes r ON r.id=rv.route_id WHERE r.operator_id=$1',
            [op],
          )
        ).rows,
      };
    } finally {
      db.release();
    }
  }
  @Post('operator/routes') async route(@Headers('authorization') h: string, @Body() b: unknown) {
    return this.bus.createRoute(
      await this.auth.actor(h),
      z
        .object({
          operatorId: uuid,
          name: short,
          stops: z
            .array(point.extend({ name: short, offsetMinutes: z.number().int().min(0).max(1440) }))
            .min(2)
            .max(100),
        })
        .strict()
        .parse(b),
    );
  }
  @Post('operator/services') async service(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    return this.bus.createService(
      await this.auth.actor(h),
      z
        .object({
          operatorId: uuid,
          routeVersionId: uuid,
          vehicleId: uuid,
          crewId: uuid,
          departureAt: instant,
          serviceDate: date,
        })
        .strict()
        .parse(b),
    );
  }
  @Get('operator/audit') async audit(
    @Headers('authorization') h: string,
    @Query('operatorId') op: string,
  ) {
    const a = await this.auth.actor(h),
      db = await pool.connect();
    try {
      await this.bus.operator(db, a, id(op));
      return (
        await db.query(
          'SELECT action,resource_id,detail,created_at FROM audit_logs WHERE operator_id=$1 ORDER BY id DESC LIMIT 100',
          [op],
        )
      ).rows;
    } finally {
      db.release();
    }
  }
  @Get('shared-trips') async shared(@Headers('authorization') h: string) {
    await this.auth.actor(h);
    return this.bookings.sharedList();
  }
  @Post('shared-trips') async createShared(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    return this.bookings.sharedCreate(
      await this.auth.actor(h),
      z
        .object({
          vehicleId: uuid,
          departureAt: instant,
          capacity: z.number().int().min(1).max(12),
          farePaise: z.number().int().min(0).max(1000000),
          stops: z
            .array(point.extend({ name: short }))
            .min(2)
            .max(50),
        })
        .strict()
        .parse(b),
    );
  }
  @Post('shared-trips/:id/reservations') async reserve(
    @Headers('authorization') h: string,
    @Headers('idempotency-key') k: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    return this.bookings.reserve(
      await this.auth.actor(h),
      id(t),
      z
        .object({
          seats: z.number().int().min(1).max(12),
          pickupSequence: z.number().int().min(0).max(49),
          dropoffSequence: z.number().int().min(1).max(49),
        })
        .strict()
        .parse(b),
      key(k),
    );
  }
  @Delete('reservations/:id') async cancel(
    @Headers('authorization') h: string,
    @Param('id') r: string,
  ) {
    return this.bookings.cancelReservation(await this.auth.actor(h), id(r));
  }
  @Post('shared-trips/:id/status') async sharedStatus(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    return this.bookings.sharedStatus(
      await this.auth.actor(h),
      id(t),
      z
        .object({ status: z.enum(['BOARDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']) })
        .strict()
        .parse(b).status,
    );
  }
  @Get('driver/shared-trips') async driverShared(@Headers('authorization') h: string) {
    return this.bookings.driverShared(await this.auth.actor(h));
  }
  @Post('reservations/:id/boarding') async boarding(
    @Headers('authorization') h: string,
    @Param('id') r: string,
    @Body() b: unknown,
  ) {
    return this.bookings.boarding(
      await this.auth.actor(h),
      id(r),
      z
        .object({ status: z.enum(['BOARDED', 'NO_SHOW']) })
        .strict()
        .parse(b).status,
    );
  }
  @Post('driver/availability') async online(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    const a = await this.auth.actor(h);
    this.auth.require(a, 'DRIVER');
    const v = z.object({ online: z.boolean() }).strict().parse(b);
    const r = await pool.query(
      "UPDATE driver_profiles SET online=$1 WHERE user_id=$2 AND verification='APPROVED' RETURNING online",
      [v.online, a.id],
    );
    if (!r.rowCount) throw new HttpException('Approval required', 403);
    return r.rows[0];
  }
  @Get('driver/vehicles') async vehicles(@Headers('authorization') h: string) {
    const a = await this.auth.actor(h);
    this.auth.require(a, 'DRIVER');
    return (
      await pool.query(
        'SELECT id,registration,category,capacity,approved FROM vehicles WHERE driver_id=$1',
        [a.id],
      )
    ).rows;
  }
  @Get('me/reservations') async myReservations(@Headers('authorization') h: string) {
    const actor = await this.auth.actor(h);
    return (
      await pool.query(
        'SELECT r.id,r.trip_id,r.pickup_sequence,r.dropoff_sequence,r.seats,r.fare_paise,r.status,r.created_at,t.departure_at,p.name pickup_name,d.name dropoff_name FROM seat_reservations r JOIN shared_trips t ON t.id=r.trip_id JOIN shared_trip_stops p ON p.trip_id=r.trip_id AND p.sequence=r.pickup_sequence JOIN shared_trip_stops d ON d.trip_id=r.trip_id AND d.sequence=r.dropoff_sequence WHERE r.passenger_id=$1 ORDER BY r.created_at DESC LIMIT 100',
        [actor.id],
      )
    ).rows;
  }
  @Get('driver/availability') async availability(@Headers('authorization') h: string) {
    return this.rides.availability(await this.auth.actor(h));
  }
  @Post('driver/location') async driverLocation(
    @Headers('authorization') h: string,
    @Body() b: unknown,
  ) {
    return this.rides.location(
      await this.auth.actor(h),
      z
        .object({
          lat: z.number().min(-90).max(90),
          lng: z.number().min(-180).max(180),
          accuracyM: z.number().int().min(0).max(100),
          recordedAt: instant,
        })
        .strict()
        .parse(b),
    );
  }
  @Get('driver/offers') async offers(@Headers('authorization') h: string) {
    return this.rides.offers(await this.auth.actor(h));
  }
  @Post('bookings/:id/reject') async rejectOffer(
    @Headers('authorization') h: string,
    @Param('id') t: string,
  ) {
    return this.rides.reject(await this.auth.actor(h), id(t));
  }
  @Post('bookings/quote') async quote(@Headers('authorization') h: string, @Body() b: unknown) {
    const a = await this.auth.actor(h);
    this.auth.require(a, 'PASSENGER');
    return this.rides.quote(
      z
        .object({ pickup: point, dropoff: point, category: z.enum(['AUTO', 'TAXI']) })
        .strict()
        .parse(b),
    );
  }
  @Get('bookings/:id') async rideDetail(
    @Headers('authorization') h: string,
    @Param('id') t: string,
  ) {
    return this.rides.detail(await this.auth.actor(h), id(t));
  }
  @Post('bookings/:id/confirm-pickup') async confirmPickup(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    return this.rides.confirmPickup(
      await this.auth.actor(h),
      id(t),
      z.object({ version: z.number().int().positive() }).strict().parse(b).version,
    );
  }
  @Get('bookings') async bookingsList(
    @Headers('authorization') h: string,
    @Query('as') as: unknown,
  ) {
    return this.rides.list(
      await this.auth.actor(h),
      z.enum(['driver', 'passenger']).optional().parse(as),
    );
  }
  @Post('bookings') async booking(
    @Headers('authorization') h: string,
    @Headers('idempotency-key') k: string,
    @Body() b: unknown,
  ) {
    return this.bookings.privateCreate(
      await this.auth.actor(h),
      z
        .object({
          pickup: point,
          dropoff: point,
          category: z.enum(['AUTO', 'TAXI']),
          pickupLabel: short.optional(),
          dropoffLabel: short.optional(),
          expectedFarePaise: z.number().int().nonnegative().optional(),
        })
        .strict()
        .parse(b),
      key(k),
    );
  }
  @Post('bookings/:id/accept') async accept(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    return this.bookings.privateAccept(
      await this.auth.actor(h),
      id(t),
      z.object({ vehicleId: uuid }).strict().parse(b).vehicleId,
    );
  }
  @Post('bookings/:id/status') async bookingStatus(
    @Headers('authorization') h: string,
    @Param('id') t: string,
    @Body() b: unknown,
  ) {
    const v = z
      .object({
        status: z.enum(['ARRIVED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']),
        version: z.number().int().positive(),
      })
      .strict()
      .parse(b);
    return this.bookings.privateStatus(await this.auth.actor(h), id(t), v.status, v.version);
  }
  @Post('bookings/:id/cash') async cash(
    @Headers('authorization') h: string,
    @Headers('idempotency-key') k: string,
    @Param('id') t: string,
  ) {
    return this.bookings.cash(await this.auth.actor(h), id(t), key(k));
  }
}
@Module({ controllers: [Api], providers: [Auth, Bus, Bookings, BusOwner, PrivateRides] })
class App {}
export async function bootstrap(port = Number(process.env.PORT ?? 3001)) {
  const config = runtimeConfig();
  const app = await NestFactory.create<import('@nestjs/platform-express').NestExpressApplication>(
    App,
    { logger: ['error', 'warn', 'log'], bodyParser: false },
  );
  const express = app.getHttpAdapter().getInstance();
  express.disable('x-powered-by');
  // Render's managed ingress terminates TLS and is the sole network entry point
  // for this Free web service. Trust only the immediate hop, per Render guidance.
  express.set(
    'trust proxy',
    config.renderIngress ? 1 : config.trustedProxies.length ? config.trustedProxies : false,
  );
  app.use((req: any, res: any, next: any) => {
    const requestId = randomUUID();
    req.requestId = requestId;
    res.setHeader('X-Request-ID', requestId);
    res.setHeader('Cache-Control', 'no-store');
    if (config.requireHttps && !req.secure && !['/v1/health', '/v1/ready'].includes(req.path)) {
      res.status(400).json({ message: 'HTTPS required', requestId });
      return;
    }
    next();
  });
  app.useBodyParser('json', { limit: '64kb' });
  app.use(helmet());
  app.enableCors({
    origin: config.adminOrigin,
    exposedHeaders: ['X-Request-ID'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'X-Sandbox-Key'],
    methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  });
  app.useGlobalFilters(new Errors());
  const auth = app.get(Auth);
  app.use(async (req: any, res: any, next: any) => {
    if (req.path === '/v1/health' || req.path === '/v1/openapi.json') {
      next();
      return;
    }
    try {
      await auth.rate('http:' + hashIp(req.ip ?? 'unknown'), 300, 60);
      next();
    } catch (error) {
      const limited = error instanceof HttpException && error.getStatus() === 429;
      res.status(limited ? 429 : 503).json({
        message: limited ? 'Request limit exceeded' : 'Service temporarily unavailable',
        requestId: req.requestId,
      });
    }
  });
  await app.listen(port, '0.0.0.0');
  const wss = new WebSocketServer({ noServer: true, maxPayload: 4096 });
  app.getHttpServer().on('upgrade', async (req: any, socket: any, head: any) => {
    try {
      const forwarded =
        (config.renderIngress || config.trustedProxies.length > 0) &&
        express.get('trust proxy fn')(socket.remoteAddress, 0);
      if (
        config.requireHttps &&
        !socket.encrypted &&
        !(forwarded && req.headers['x-forwarded-proto'] === 'https')
      )
        throw new Error('HTTPS required');
      await auth.rate('ws-connect:' + hashIp(socket.remoteAddress ?? 'unknown'), 30, 60);
      const a = await auth.actor(req.headers.authorization);
      await auth.rate('ws:' + a.id, 10, 60);
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname !== '/v1/live') throw new Error();
      const tripId = id(url.searchParams.get('tripId') ?? '');
      const initialCursor = z
        .string()
        .regex(/^\d{1,18}$/)
        .parse(url.searchParams.get('after') ?? '0');
      await app.get(Bus).detail(tripId);
      wss.handleUpgrade(req, socket, head, (ws) => {
        let cursor = initialCursor,
          busy = false;
        const poll = async () => {
          if (busy || ws.readyState !== WebSocket.OPEN) return;
          busy = true;
          try {
            await auth.actor(req.headers.authorization);
            const events = (
              await pool.query(
                'SELECT id,topic,version,payload,created_at FROM events WHERE resource_id=$1 AND id>$2 ORDER BY id LIMIT 100',
                [tripId, cursor],
              )
            ).rows;
            for (const event of events) {
              if (ws.bufferedAmount > 1048576) {
                ws.close(1013, 'Refetch required');
                break;
              }
              ws.send(JSON.stringify(event));
              cursor = event.id;
            }
          } catch {
            ws.close(1008, 'Session expired');
          } finally {
            busy = false;
          }
        };
        const timer = setInterval(poll, 2000);
        ws.on('close', () => clearInterval(timer));
        ws.on('error', () => clearInterval(timer));
        void poll();
      });
    } catch {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  });
  app.enableShutdownHooks();
  return app;
}
function hashIp(ip: string) {
  return ip.replace(/[^a-zA-Z0-9:.]/g, '').slice(0, 80);
}
if (!process.env.RURALCONNECT_TEST_IMPORT) void bootstrap();

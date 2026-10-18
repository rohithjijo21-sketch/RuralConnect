/** Provider contracts only. Implementations require approved credentials and separate tests. */
export interface OtpProvider {
  send(input: {
    phone: string;
    code: string;
    requestId: string;
  }): Promise<{ providerReference: string }>;
}
export interface PaymentGateway {
  createIntent(input: {
    amountPaise: number;
    currency: 'INR';
    idempotencyKey: string;
  }): Promise<{ id: string; checkoutUrl: string }>;
  verifyWebhook(
    rawBody: Buffer,
    signature: string,
  ): Promise<{
    eventId: string;
    intentId: string;
    status: 'SUCCEEDED' | 'FAILED';
    amountPaise: number;
  }>;
  refund(input: {
    paymentId: string;
    amountPaise: number;
    idempotencyKey: string;
  }): Promise<{ id: string; status: 'PENDING' | 'SUCCEEDED' }>;
}
export interface NotificationProvider {
  send(input: {
    deviceToken: string;
    eventId: string;
    title: string;
    body: string;
  }): Promise<{ providerReference: string }>;
}
export interface DocumentStorage {
  createRestrictedUpload(input: {
    ownerId: string;
    mimeType: string;
    bytes: number;
  }): Promise<{ objectKey: string; uploadUrl: string }>;
  scan(objectKey: string): Promise<'CLEAN' | 'REJECTED' | 'PENDING'>;
}
export interface RoutingProvider {
  roadRoute(input: {
    origin: { lat: number; lng: number };
    destination: { lat: number; lng: number };
  }): Promise<{
    distanceMeters: number;
    durationSeconds: number;
    geometry: unknown;
    source: string;
  }>;
}
export class DisabledGateway implements PaymentGateway {
  async createIntent(): Promise<never> {
    throw Error('Digital payments disabled: approved gateway not configured');
  }
  async verifyWebhook(): Promise<never> {
    throw Error('No payment result accepted without authoritative signed verification');
  }
  async refund(): Promise<never> {
    throw Error('Refund provider not configured');
  }
}

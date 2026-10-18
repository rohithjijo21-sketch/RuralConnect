export type Role = 'PASSENGER' | 'DRIVER' | 'BUS_CREW' | 'OPERATOR' | 'ADMIN';
export type MinorUnits = number & { readonly __integerPaise: unique symbol };
export type LocationQuality = 'LIVE' | 'STALE' | 'UNAVAILABLE';
export type EventEnvelope<T> = {
  id: string;
  topic: string;
  version: number;
  payload: T;
  created_at: string;
};

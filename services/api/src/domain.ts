import { createHash, randomBytes } from 'node:crypto';
export const roles = ['PASSENGER', 'DRIVER', 'BUS_CREW', 'OPERATOR', 'ADMIN'] as const;
export type Role = (typeof roles)[number];
export type Actor = { id: string; roles: Role[] };
export const busStates = [
  'SCHEDULED',
  'BOARDING',
  'RUNNING',
  'DELAYED',
  'STOPPED',
  'BREAKDOWN',
  'DIVERTED',
  'CANCELLED',
  'COMPLETED',
] as const;
export type BusState = (typeof busStates)[number];
const transitions: Record<BusState, readonly BusState[]> = {
  SCHEDULED: ['BOARDING', 'CANCELLED'],
  BOARDING: ['RUNNING', 'DELAYED', 'CANCELLED', 'BREAKDOWN'],
  RUNNING: ['DELAYED', 'STOPPED', 'BREAKDOWN', 'DIVERTED', 'COMPLETED'],
  DELAYED: ['BOARDING', 'RUNNING', 'STOPPED', 'BREAKDOWN', 'CANCELLED', 'COMPLETED'],
  STOPPED: ['RUNNING', 'BREAKDOWN', 'CANCELLED'],
  BREAKDOWN: ['RUNNING', 'CANCELLED'],
  DIVERTED: ['RUNNING', 'DELAYED', 'BREAKDOWN', 'COMPLETED', 'CANCELLED'],
  CANCELLED: ['SCHEDULED'],
  COMPLETED: [],
};
export function canTransition(from: BusState, to: BusState, operator: boolean) {
  return transitions[from].includes(to) && (from !== 'CANCELLED' || operator);
}
export function hash(value: string) {
  return createHash('sha256').update(value).digest('hex');
}
export function token() {
  return randomBytes(32).toString('base64url');
}
export function fresh(at: string | Date | null, now = Date.now()) {
  if (!at) return false;
  const age = now - new Date(at).getTime();
  return age >= -10_000 && age <= 60_000;
}
export function plausible(
  previous: { lat: number; lng: number; at: Date } | null,
  next: { lat: number; lng: number; at: Date },
  now = Date.now(),
) {
  const age = now - next.at.getTime();
  if (
    !Number.isFinite(next.lat) ||
    !Number.isFinite(next.lng) ||
    next.lat < -90 ||
    next.lat > 90 ||
    next.lng < -180 ||
    next.lng > 180 ||
    age > 120_000 ||
    age < -10_000
  )
    return false;
  if (!previous) return true;
  const seconds = (next.at.getTime() - previous.at.getTime()) / 1000;
  if (seconds <= 0) return false;
  const rad = Math.PI / 180,
    dlat = (next.lat - previous.lat) * rad,
    dlng = (next.lng - previous.lng) * rad;
  const a =
    Math.sin(dlat / 2) ** 2 +
    Math.cos(previous.lat * rad) * Math.cos(next.lat * rad) * Math.sin(dlng / 2) ** 2;
  return (6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))) / seconds <= 55;
}
export function safeFare(seats: number, farePaise: number) {
  if (
    !Number.isSafeInteger(seats) ||
    seats < 1 ||
    !Number.isSafeInteger(farePaise) ||
    farePaise < 0 ||
    !Number.isSafeInteger(seats * farePaise)
  )
    throw new Error('Invalid fare');
  return seats * farePaise;
}

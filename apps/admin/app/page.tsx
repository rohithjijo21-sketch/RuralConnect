'use client';
import { useState, useEffect, useCallback } from 'react';
import type { components } from '../../../packages/api-contracts/generated';
type Trip = Required<components['schemas']['BusTrip']>;
const base = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3001/v1';
export default function Page() {
  const [access, setAccess] = useState(''),
    [phone, setPhone] = useState(''),
    [sandboxKey, setSandboxKey] = useState(''),
    [challenge, setChallenge] = useState(''),
    [code, setCode] = useState(''),
    [consent, setConsent] = useState(false),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false),
    [trips, setTrips] = useState<Trip[]>([]),
    [me, setMe] = useState<any>(null),
    [op, setOp] = useState(''),
    [tab, setTab] = useState('services'),
    [resources, setResources] = useState<any>(null),
    [audit, setAudit] = useState<any[]>([]),
    [reason, setReason] = useState(''),
    [delay, setDelay] = useState(10),
    [lastSync, setLastSync] = useState('');
  const api = useCallback(
    async (path: string, method = 'GET', body?: unknown) => {
      const r = await fetch(base + path, {
        method,
        cache: 'no-store',
        headers: {
          'Content-Type': 'application/json',
          ...(access ? { Authorization: 'Bearer ' + access } : {}),
          ...(sandboxKey ? { 'X-Sandbox-Key': sandboxKey } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      const data = await r.json();
      if (!r.ok) {
        if (r.status === 401) setAccess('');
        throw Error(data.message ?? 'Request failed');
      }
      return data;
    },
    [access, sandboxKey],
  );
  async function run(task: () => Promise<void>) {
    setBusy(true);
    setError('');
    try {
      await task();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Connection failed');
    } finally {
      setBusy(false);
    }
  }
  const load = useCallback(async () => {
    const date = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Kolkata',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());
    const data = await api('/bus/trips?date=' + date);
    setTrips(data);
    setLastSync(new Date().toLocaleTimeString());
  }, [api]);
  useEffect(() => {
    if (!access) return;
    void api('/me')
      .then((u) => {
        setMe(u);
        setOp(u.operatorIds[0] ?? '');
      })
      .catch((e) => setError(e.message));
    void load().catch((e) => setError(e.message));
    const timer = setInterval(() => void load().catch((e) => setError(e.message)), 5000);
    return () => clearInterval(timer);
  }, [access, api, load]);
  useEffect(() => {
    if (!op || !access) return;
    void api('/operator/resources?operatorId=' + op)
      .then(setResources)
      .catch((e) => setError(e.message));
  }, [op, access, api]);
  async function status(t: Trip, status: string) {
    if (!reason.trim()) throw Error('Enter a reason before changing service status');
    await api('/bus/trips/' + t.id + '/status', 'POST', {
      status,
      reason,
      delayMinutes: status === 'DELAYED' ? delay : 0,
      version: t.version,
    });
    await load();
  }
  if (!access)
    return (
      <>
        <header>
          <b>RuralConnect</b>
          <span>Operations</span>
        </header>
        <main style={{ maxWidth: 520 }}>
          <p className="eyebrow">Kerala transport network</p>
          <h1>Keep every journey connected.</h1>
          <section className="card">
            <h2>Operator sign in</h2>
            <p className="warning">
              Development sandbox · fixture accounts only. No SMS is sent. Production OTP is not
              configured.
            </p>
            {error && (
              <p role="alert" className="error">
                {error}
              </p>
            )}
            <form
              onSubmit={(e) => {
                e.preventDefault();
                void run(async () => {
                  if (!challenge) {
                    const r = await api('/auth/otp/request', 'POST', { phone });
                    setChallenge(r.challengeId);
                  } else {
                    if (!consent) throw Error('Consent required');
                    const r = await api('/auth/otp/verify', 'POST', {
                      challengeId: challenge,
                      code,
                      consentVersion: 'development-v1',
                    });
                    setAccess(r.accessToken);
                    setSandboxKey('');
                  }
                });
              }}
            >
              <label>
                Phone (+91)
                <input
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  required
                  pattern="\+91[6-9][0-9]{9}"
                  autoComplete="tel"
                />
              </label>
              <label>
                Local sandbox access key
                <input
                  type="password"
                  value={sandboxKey}
                  onChange={(e) => setSandboxKey(e.target.value)}
                  required={!challenge}
                />
              </label>
              {challenge && (
                <>
                  <label>
                    Configured local OTP
                    <input
                      value={code}
                      onChange={(e) => setCode(e.target.value)}
                      pattern="[0-9]{6}"
                      required
                      autoComplete="one-time-code"
                    />
                  </label>
                  <label className="row">
                    <input
                      style={{ width: 'auto' }}
                      type="checkbox"
                      checked={consent}
                      onChange={(e) => setConsent(e.target.checked)}
                    />
                    I accept the development privacy/terms notice. Do not enter real personal data.
                  </label>
                </>
              )}
              <button disabled={busy}>
                {busy
                  ? 'Connecting…'
                  : challenge
                    ? 'Verify and sign in'
                    : 'Request sandbox challenge'}
              </button>
            </form>
          </section>
        </main>
      </>
    );
  const allowed = me?.roles?.some((r: string) => ['ADMIN', 'OPERATOR'].includes(r));
  return (
    <>
      <header>
        <div>
          <b>RuralConnect</b>
          <div className="muted" style={{ color: '#b3d5bf' }}>
            Operations / Kerala
          </div>
        </div>
        <button
          onClick={() =>
            void run(async () => {
              await api('/auth/logout', 'POST');
              setAccess('');
              setMe(null);
            })
          }
        >
          Sign out
        </button>
      </header>
      <main>
        <p className="eyebrow">Service control</p>
        <h1>Today's network</h1>
        <p className="muted">
          Backend refetch every 5 seconds · Last successful sync {lastSync || 'pending'} · Times
          shown in your device timezone
        </p>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        {!allowed ? (
          <p className="warning">
            This account has no operator permissions. Sign in with an authorised operator fixture.
          </p>
        ) : (
          <>
            <div className="row">
              <label>
                Operator
                <select value={op} onChange={(e) => setOp(e.target.value)}>
                  {me?.operatorIds?.map((id: string) => (
                    <option key={id}>{id}</option>
                  ))}
                </select>
              </label>
              <button onClick={() => void run(load)} disabled={busy}>
                Refresh
              </button>
            </div>
            <nav>
              {['services', 'create', 'audit'].map((t) => (
                <button
                  key={t}
                  onClick={() => {
                    setTab(t);
                    if (t === 'audit')
                      void run(async () => setAudit(await api('/operator/audit?operatorId=' + op)));
                  }}
                >
                  {t}
                </button>
              ))}
            </nav>
            {tab === 'services' && (
              <>
                <div className="card row">
                  <label>
                    Incident reason
                    <input
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                      maxLength={240}
                    />
                  </label>
                  <label>
                    Delay minutes
                    <input
                      type="number"
                      value={delay}
                      min={1}
                      max={720}
                      onChange={(e) => setDelay(Number(e.target.value))}
                    />
                  </label>
                </div>
                <div className="grid">
                  {trips
                    .filter((t) => (t as any).operator_id === op)
                    .map((t) => (
                      <article className="card" key={t.id}>
                        <div className="row">
                          <span className="badge">{t.status}</span>
                          <span className="muted">v{t.version}</span>
                        </div>
                        <h2>{t.route_name}</h2>
                        <p>
                          {t.registration} · {new Date(t.departure_at).toLocaleTimeString()}
                        </p>
                        <p className="muted">
                          Scheduled departure · Reported delay {t.delay_minutes} min · No computed
                          ETA
                        </p>
                        <p className={t.locationQuality === 'LIVE' ? 'badge' : 'warning'}>
                          GPS: {t.locationQuality}
                          {t.recorded_at
                            ? ' · ' + new Date(t.recorded_at).toLocaleTimeString()
                            : ''}
                        </p>
                        {t.lat !== null && t.lng !== null && (
                          <p>
                            <a
                              href={
                                'https://www.openstreetmap.org/?mlat=' +
                                t.lat +
                                '&mlon=' +
                                t.lng +
                                '#map=15/' +
                                t.lat +
                                '/' +
                                t.lng
                              }
                              target="_blank"
                              rel="noreferrer"
                            >
                              View reported position on OpenStreetMap ↗
                            </a>
                          </p>
                        )}
                        <div className="row">
                          {[
                            'DELAYED',
                            'CANCELLED',
                            ...(t.status === 'CANCELLED' ? ['SCHEDULED'] : []),
                          ].map((s) => (
                            <button
                              key={s}
                              disabled={busy}
                              onClick={() => void run(() => status(t, s))}
                            >
                              {s === 'SCHEDULED'
                                ? 'Reinstate'
                                : s === 'DELAYED'
                                  ? 'Report delay'
                                  : 'Cancel service'}
                            </button>
                          ))}
                        </div>
                      </article>
                    ))}
                </div>
                {!trips.some((t) => (t as any).operator_id === op) && (
                  <p className="card">
                    No dated services for this operator today. Create a route and service or seed
                    demo fixtures.
                  </p>
                )}
              </>
            )}
            {tab === 'create' && (
              <div className="grid">
                <RouteForm
                  busy={busy}
                  submit={(body) =>
                    run(async () => {
                      await api('/operator/routes', 'POST', {
                        operatorId: op,
                        ...(body as Record<string, unknown>),
                      });
                      setResources(await api('/operator/resources?operatorId=' + op));
                      setTab('services');
                    })
                  }
                />
                <ServiceForm
                  resources={resources}
                  busy={busy}
                  submit={(body) =>
                    run(async () => {
                      await api('/operator/services', 'POST', {
                        operatorId: op,
                        ...(body as Record<string, unknown>),
                      });
                      await load();
                      setTab('services');
                    })
                  }
                />
              </div>
            )}
            {tab === 'audit' && (
              <section className="card">
                <h2>Operator audit trail</h2>
                {audit.length ? (
                  audit.map((a, i) => (
                    <div key={i}>
                      <p>
                        {a.action} · {new Date(a.created_at).toLocaleString()}
                      </p>
                      <pre>{JSON.stringify(a.detail)}</pre>
                    </div>
                  ))
                ) : (
                  <p>No audit entries.</p>
                )}
              </section>
            )}
          </>
        )}
      </main>
    </>
  );
}
function RouteForm({ submit, busy }: { submit: (body: unknown) => void; busy: boolean }) {
  const [name, setName] = useState(''),
    [text, setText] = useState(''),
    [error, setError] = useState('');
  return (
    <form
      className="card"
      onSubmit={(e) => {
        e.preventDefault();
        try {
          const stops = text
            .split('\n')
            .filter(Boolean)
            .map((line) => {
              const [name, lat, lng, offsetMinutes] = line.split(',');
              if (
                !name ||
                ![lat, lng, offsetMinutes].every(
                  (n) => n !== undefined && n.trim() !== '' && Number.isFinite(Number(n)),
                )
              )
                throw Error('Check each stop row');
              return {
                name,
                lat: Number(lat),
                lng: Number(lng),
                offsetMinutes: Number(offsetMinutes),
              };
            });
          submit({ name, stops });
        } catch (e) {
          setError(String(e));
        }
      }}
    >
      <h2>Create route version</h2>
      <label>
        Route name
        <input required value={name} onChange={(e) => setName(e.target.value)} />
      </label>
      <label>
        Stops (one per line: name, latitude, longitude, minutes from start)
        <textarea required rows={6} value={text} onChange={(e) => setText(e.target.value)} />
      </label>
      {error && <p role="alert">{error}</p>}
      <button disabled={busy}>Create route</button>
    </form>
  );
}
function ServiceForm({
  submit,
  resources,
  busy,
}: {
  submit: (body: unknown) => void;
  resources: any;
  busy: boolean;
}) {
  return (
    <form
      className="card"
      onSubmit={(e) => {
        e.preventDefault();
        const f = new FormData(e.currentTarget);
        const departure = new Date(String(f.get('departure')));
        const serviceDate = new Intl.DateTimeFormat('en-CA', {
          timeZone: 'Asia/Kolkata',
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
        }).format(departure);
        submit({
          routeVersionId: f.get('route'),
          vehicleId: f.get('vehicle'),
          crewId: f.get('crew'),
          departureAt: departure.toISOString(),
          serviceDate,
        });
      }}
    >
      <h2>Assign dated service</h2>
      {[
        ['route', 'routes', 'name'],
        ['vehicle', 'vehicles', 'registration'],
        ['crew', 'crew', 'name'],
      ].map(([name, list, label]) => (
        <label key={name}>
          {name}
          <select name={name} required>
            <option value="">Select {name}</option>
            {resources?.[list]?.map((r: any) => (
              <option key={r.id} value={r.id}>
                {r[label]}
              </option>
            ))}
          </select>
        </label>
      ))}
      <label>
        Departure (device local time)
        <input required name="departure" type="datetime-local" />
      </label>
      <button disabled={busy}>Create and assign</button>
    </form>
  );
}

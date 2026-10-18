# Product requirements and navigation

Launch geography: Kerala; timezone Asia/Kolkata; currency INR in integer paise. Initial languages English/Malayalam. Real drivers, buses and timetable data require operator review. Demo routes are clearly labelled and must never be used as official schedules.

## Roles and permissions

| Action                                | Passenger | Auto/taxi driver                          | Assigned bus crew        | Owning operator          | Admin                    |
| ------------------------------------- | --------- | ----------------------------------------- | ------------------------ | ------------------------ | ------------------------ |
| Read published bus services           | yes       | yes                                       | yes                      | yes                      | yes                      |
| View crew assignments                 | no        | no                                        | own                      | via operator resources   | via scoped tools         |
| Submit bus status/GPS                 | no        | no                                        | assigned trip only       | owned trip               | yes                      |
| Reinstate cancelled bus               | no        | no                                        | no                       | owned trip               | yes                      |
| Create routes/services; inspect audit | no        | no                                        | no                       | member operator only     | explicit operator scope  |
| Reserve shared seats                  | own       | only with passenger role                  | only with passenger role | only with passenger role | only with passenger role |
| Publish shared service                | no        | approved driver/vehicle                   | no                       | no                       | no                       |
| Accept private booking                | no        | approved online driver, matching category | no                       | no                       | no                       |
| Record cash                           | no        | assigned driver, completed booking        | no                       | no                       | no                       |
| Profile/device/data requests          | self      | self                                      | self                     | self                     | self                     |

No public role-management endpoint exists. Demo operator setup is local seeding. Driver document approval, provisioning and administrator MFA are unfinished; commercial onboarding must stay closed.

## Navigation map

- Passenger: sandbox sign-in → bus search → service status / alert subscription; shared services → first-to-final stop one-seat request → backend confirmation.
- Bus: sandbox sign-in → today's assigned services → selected service → explicit state changes / reason → foreground GPS sharing controls.
- Driver: sandbox sign-in → owned vehicles → online/offline → shared-trip publish form / reservations / boarding and trip status controls. Private offers, finances and document onboarding screens remain pending.
- Operator: sandbox sign-in → operator scope → services / route creation / dated bus-and-crew assignment / audit history.
- Admin: uses backend ADMIN permission for scoped bus operations. Full system administration navigation remains pending.

## Experience contracts

No continuous location permission is required for browsing. GPS unavailable/stale is explicit. Cached schedules never claim current availability or live positions. Offline mutations are not confirmed. State/version conflict prompts refetch. Buttons use generous tap targets; bus UI warns against interaction while driving. Light/dark material themes exist. Full localisation/accessibility review and field trials on inexpensive phones are pending.

## Safety and exclusions

No SOS dispatch, authority notification, payout, OTP SMS or digital-payment success is claimed. Those interfaces remain unimplemented/blocked. Commercial launch requires the release gates in the compliance register, including operator/driver verification, incident support and payment approval.

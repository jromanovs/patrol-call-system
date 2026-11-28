# Non-functional requirements

Each line gives a number, where it comes from, and the check that holds it. A number is either a rule of SPECIFICATION.md, named by its identifier, or a measurement on the server, named by its period and the number of requests; a measured number is the level the system holds now, and a change that makes it worse is a defect. The sections follow the quality characteristics of ISO/IEC 25010.

## Performance efficiency

- Position reports of Traccar Client (`POST /traccar`, API-11): 95 % answered within 13 ms, the slowest in 205 ms; the sign-in page (`GET /session/new`): 95 % within 85 ms, the slowest in 190 ms. Measured: 1148 reports and 26 pages in the production log, 24.11.2026 to 28.11.2026. Check: the measurement below.
- The crew screen sends the phone's position at once and then every 30 seconds while it is open (TRK-04). Check: `spec/requests/crew_position_spec.rb`.

## Reliability

- Answers with a server error (status 5xx): 0 of 1221 requests, 24.11.2026 to 28.11.2026. Check: the measurement below.
- A push service that does not connect or answer within 10 seconds does not stop the notices to the other phones (CRW-04). Check: `spec/services/crew_notice_spec.rb`.
- The schema and the demo data are restored into an empty database within 5 seconds on a developer machine (4.3 s on 28.11.2026). Check: the steps of `docs/operations.md`.

## Security

- The 11th sign-in attempt from one address within 3 minutes is refused (AUTH-03, BR-16). Check: `rate_limit` in `SessionsController`.
- No dependency with a published advisory and no Brakeman warning: `bin/ci` stops at the first (bundler-audit, importmap audit, Brakeman) and runs on every pull request.

## Functional suitability

- Car positions are kept 24 months unless the administrator sets another period, from 3 to 1200 months, and deleted once a night when older (BR-20, TRK-05). Check: `spec/models/setting_spec.rb`, `spec/models/car_position_spec.rb`.
- A finished call cannot be deleted for 24 months unless the administrator sets another period, from 3 to 1200 months; nothing deletes a call by itself (BR-23, DEL-09). Check: `spec/models/call_retention_spec.rb`.

## Usability

- Text has a contrast of at least 4.5:1 and borders of fields and buttons 3:1 against their background, in the light and the dark theme (SPECIFICATION.md 4.3; WCAG 2.2, 1.4.3 and 1.4.11). Check: `spec/tasks/css_build_spec.rb`, `spec/scripts/map_style_spec.rb`.

## The measurement on the server

The application logs a line `Started` and a line `Completed ... in N ms` for every request, both with the request's identifier. `bin/kamal app logs --grep 'Started\|Completed' --lines 200000` reads them from the running container, and `--container-id` from the previous one; the server keeps them until the container is removed or its log is rotated. A request is counted when both of its lines are there; the time is the `N ms` of its `Completed` line, and 95 % is the nearest-rank percentile.

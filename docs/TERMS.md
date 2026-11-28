# Terms

The words of the system. Code, screens, issues and commit messages use these words for these things; this file is the only place where they are explained.

Each entry says what the word means, what it does not mean, and its name in the code.

## Monitoring centre

Round-the-clock room of the security company where dispatchers receive calls.

Not a place a car is sent to: cars go to guarded sites.

In the code: no name of its own; the system serves one centre.

## Guarded site

Client premises covered by a monitoring contract.

Not the client: the client is a field of the site, `client_name`.

In the code: `GuardedSite`.

## Call

Any request for a patrol: an alarm signal, a client's phone call or a crew's SOS.

Not only a phone call: an alarm signal and a crew's SOS are calls too.

In the code: `Call`, with the subclasses `AlarmCall`, `ClientCall` and `SosCall`.

## Dispatch

Assigning a free patrol car to a call.

Not the arrival: after the dispatch the crew accepts the call and then arrives.

In the code: `CallStep#dispatch`; the status `dispatched`.

## Further car

A car sent to a call that already has its car; it has its own steps and does not close the call.

Not the call's own car: only the call's own car closes the call.

In the code: `Backup`, its steps in `BackupStep`.

## Crew's SOS

A call raised by a patrol crew that asks for help, at the place its signal came from.

Not an alarm signal of a site: it needs no guarded site, its place is where the crew's phone was.

In the code: `SosCall`; the car that raised it is `raised_by`.

## Response time

Time from receiving the call to the crew's arrival at the site. The first arrival counts, of the call's own car or of a further car.

Not the handling time, which runs until the call is closed or cancelled.

In the code: `Call#response_minutes`; the first arrival is `Call::FIRST_ARRIVAL`; the average is `CallStatistics#response`.

## Handling time

Time from receiving the call to its closing or cancellation. For an active call it runs until now.

Not the response time, which ends at the arrival.

In the code: `Call#handling_minutes`.

## False alarm

A call where the crew found no intrusion, fire or other threat.

Not a cancelled call: a false alarm is the outcome of a closed call.

In the code: the outcome `false_alarm`.

## State Address Register

The official register of addresses in Latvia, published as open data.

Not the addresses the system keeps: those are the ones loaded from a file of the register.

In the code: `Address`, loaded by `AddressRegisterLoad` (`bin/rails addresses:load`).

## PMTiles

A single-file archive of map tiles.

Not a tile server: the file is served as it is, with the application.

In the code: `MapBuild`; the files `*.pmtiles` in `storage/map`.

## ALTCHA

An open-source check against bots: the browser solves a small computing task, no external service is involved.

Not a check run by an outside service.

In the code: `CaptchaController` hands out the task, `CaptchaVerification` checks the answer.

## OAuth 2.0

The standard way to sign in with an account of another service, here Google.

Not a way to create an account: only a user the administrator created signs in with Google.

In the code: `GoogleSessionsController`, the route `auth/google_oauth2/callback`.

## API key

A secret string that a program sends with every API request in place of a password.

Not the user's password: the system keeps only its digest, and voids it when the password changes or the user is made inactive.

In the code: `User.find_by_api_key`, the column `api_key_digest`.

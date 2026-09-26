# Patrol Car Call Management System — Specification

## 1. Subject area

### 1.1 Overview

A private security company runs a monitoring centre that operates around the clock. Its clients include households, shops, offices and warehouses. Each client has an alarm system connected to the centre under a monitoring contract. Calls reach the centre in two ways:

- the **alarm system** at the site sends a signal: intrusion sensor, fire detector, panic button, tampering or power failure;
- a **client phones** the centre, for example to ask for a check of the premises.

The dispatcher registers the call and sends a free **patrol car** to the site. The crew reports its arrival, checks the premises and reports the result. The dispatcher then closes the call with an outcome, which ranges from a false alarm to a confirmed intrusion.

### 1.2 Problem

The dispatcher needs the following information on one screen:

- which calls are still waiting;
- which call has waited the longest;
- which cars are free.

Management needs to know how fast crews reach the sites and which sites keep producing false alarms. The system keeps the register of sites, cars and calls, supports the whole life of a call from registration to closing, and calculates these figures.

### 1.3 Users

- **Dispatcher (monitoring centre operator)** — Registers calls, dispatches cars, records arrival and outcome, maintains the lists of sites and cars
- **Shift supervisor** — Reviews statistics and deletes outdated call records

The first version has one shared interface without login or roles.

### 1.4 Out of scope

- Automatic reception of signals from alarm panels. The dispatcher enters every call manually.
- GPS tracking, maps and route planning.
- Billing and contract fees.
- SMS, e-mail or phone notifications.

### 1.5 Platform

Web application built with Ruby on Rails, Hotwire and PostgreSQL. All data in the repository and in the demo database is synthetic: fictitious names, addresses and phone numbers.

---

## 2. Objects and attributes

### 2.1 Classes

- `GuardedSite` — Premises under a monitoring contract. Own attributes: 10.
- `PatrolCar` — Patrol car with its crew. Own attributes: 6.
- `Call` — **Abstract** base for any call to the centre. Own attributes: 10.
  - `AlarmCall` — Call raised by the site's alarm system, **inherits** `Call`. Own attributes: 2.
  - `ClientCall` — Call made by the client by phone, **inherits** `Call`. Own attributes: 2.

Together: 3 object types stored in 3 database tables, 5 classes and 30 attributes, not counting `id`, `created_at` and `updated_at`. `AlarmCall` and `ClientCall` share the `calls` table: Rails single-table inheritance stores the class name in a `type` column.

### 2.2 `GuardedSite` — guarded premises

Examples are synthetic.

- `contract_number` — string, required. Unique regardless of letter case. Format `C-` followed by 5 digits. Example: `C-00042`.
- `name` — string, required. 2–100 characters. Example: `Warehouse No. 3`.
- `client_name` — string, required. 2–100 characters. Example: `Example Trade Ltd`.
- `address` — string, required. 5–200 characters. Example: `12 Linden Street, Riga`.
- `site_type` — enum `SiteType`, required. See 2.5. Example: `warehouse`.
- `district` — enum `District`, required. See 2.5. Example: `north`.
- `keyholder_phone` — string, required. `+` followed by 8–15 digits. Example: `+37100000001`.
- `contract_status` — enum `ContractStatus`, required. Default `active`. Example: `active`.
- `contract_start_date` — date, required. Must be a real calendar date. Example: `01.03.2026`.
- `access_notes` — text, optional. Up to 500 characters. Example: `Key box at the gate`.

### 2.3 `PatrolCar` — patrol car

Examples are synthetic.

- `call_sign` — string, required. Unique. 1–3 capital letters, a hyphen, then 1–3 digits. Example: `P-12`.
- `plate_number` — string, required. Unique. 2–10 characters: capital Latin letters, digits and hyphens. Stored in upper case. Example: `ZZ-0001`.
- `model` — string, required. 2–50 characters. Example: `Skoda Octavia`.
- `crew_size` — integer, required. 1–4. Example: `2`.
- `district` — enum `District`, required. Home district of the car. Example: `centre`.
- `status` — enum `CarStatus`, required. Default `available`. Only call operations set `dispatched` and `on_scene` (BR-5). Example: `available`.

### 2.4 `Call` (abstract) and its subclasses

Common attributes of `Call`:

- `guarded_site` — reference → `GuardedSite`, required. The site's contract must be `active` when the call is registered (BR-1).
- `patrol_car` — reference → `PatrolCar`, optional. Set when a car is dispatched.
- `priority` — enum `Priority`, required. The default depends on the subclass (BR-2). The dispatcher may change it.
- `status` — enum `CallStatus`, required. Default `pending`. Changes only through the operations in 2.8.
- `received_at` — datetime, required. Default is the current time. Cannot be in the future.
- `dispatched_at` — datetime, optional. Filled automatically. Not earlier than `received_at`.
- `arrived_at` — datetime, optional. Filled automatically. Not earlier than `dispatched_at`.
- `closed_at` — datetime, optional. Filled automatically when the call is closed or cancelled. Not earlier than `received_at`.
- `outcome` — enum `Outcome`. Required when the status becomes `closed`; empty otherwise.
- `description` — text, optional. Up to 1000 characters.

`AlarmCall` — call raised by the site's alarm system:

- `alarm_type` — enum `AlarmType`, required. See 2.5.
- `sensor_zone` — integer, required. 1–99. Zone number on the alarm panel.

`ClientCall` — call made by the client by phone:

- `caller_name` — string, required. 2–100 characters.
- `caller_phone` — string, required. Same format as `keyholder_phone`.

An object of the base class `Call` cannot be created. Every call is either an `AlarmCall` or a `ClientCall`.

### 2.5 Enumerations

- **`SiteType`** — apartment, house, office, shop, warehouse
- **`District`** — centre, north, south, east, west
- **`ContractStatus`** — active, suspended
- **`CarStatus`** — available, dispatched, on_scene, out_of_service
- **`Priority`** — low, normal, high, critical (the last value is the most urgent)
- **`CallStatus`** — pending, dispatched, on_scene, closed, cancelled
- **`AlarmType`** — intrusion, fire, panic, tamper, power_failure
- **`Outcome`** — false_alarm, intrusion_confirmed, fire_confirmed, technical_fault, other

### 2.6 Relationships

- `GuardedSite` — `Call` (`1 — 0..*`): Every call belongs to exactly one site. The site keeps its call history.
- `PatrolCar` — `Call` (`0..1 — 0..*`): A call is served by at most one car. A car serves many calls over time, but at most one active call at a time (BR-4).
- `GuardedSite` — `PatrolCar` (`* — *` through `Call`): Which cars have visited a site, and which sites a car has visited.
- `Call` ◁— `AlarmCall`, `ClientCall` (inheritance): The subclasses share the common attributes and add their own.
- `GuardedSite.district` ~ `PatrolCar.district` (logical, no foreign key): When dispatching, free cars from the site's district are listed first.

```mermaid
erDiagram
    GUARDED_SITE ||--o{ CALL : "has"
    PATROL_CAR |o--o{ CALL : "serves"
    GUARDED_SITE {
        string contract_number UK
        string name
        string client_name
        string address
        enum site_type
        enum district
        string keyholder_phone
        enum contract_status
        date contract_start_date
        text access_notes
    }
    PATROL_CAR {
        string call_sign UK
        string plate_number UK
        string model
        int crew_size
        enum district
        enum status
    }
    CALL {
        string type "AlarmCall | ClientCall"
        bigint guarded_site_id FK
        bigint patrol_car_id FK "nullable"
        enum priority
        enum status
        datetime received_at
        datetime dispatched_at
        datetime arrived_at
        datetime closed_at
        enum outcome
        text description
        enum alarm_type "AlarmCall"
        int sensor_zone "AlarmCall"
        string caller_name "ClientCall"
        string caller_phone "ClientCall"
    }
```

### 2.7 Business rules

- **BR-1** — A call can be registered only for a site whose contract is `active`
- **BR-2** — Default priority. For an `AlarmCall`: panic or fire → critical, intrusion → high, tamper → normal, power_failure → low. For a `ClientCall`: normal
- **BR-3** — Only a car with status `available` can be dispatched
- **BR-4** — A car has at most one active call at a time. A call is active while its status is `pending`, `dispatched` or `on_scene`
- **BR-5** — The car's status follows its call: dispatch → `dispatched`, arrival → `on_scene`, close or cancel → `available`
- **BR-6** — A car can be put `out_of_service` only when it has no active call
- **BR-7** — Closed and cancelled calls are read-only. They can be deleted but not edited
- **BR-8** — Active calls are never deleted. They must be closed or cancelled first
- **BR-9** — A site or car that has calls cannot be deleted. The contract can be suspended or the car put out of service instead
- **BR-10** — Times are stored in UTC and displayed in Riga local time as `DD.MM.YYYY HH:MM`

### 2.8 Life of a call

```mermaid
stateDiagram-v2
    [*] --> pending : register
    pending --> dispatched : dispatch car
    dispatched --> on_scene : record arrival
    on_scene --> closed : close with outcome
    pending --> cancelled : cancel
    dispatched --> cancelled : cancel
    closed --> [*]
    cancelled --> [*]
```

**Response time** is `arrived_at − received_at`: how long the client waited until the crew arrived.

---

## 3. Functional requirements: operation → input data → expected result

Rows marked _(neg)_ or _(boundary)_ describe invalid or boundary input.

### 3.1 Add

- **ADD-01** Add a guarded site
  - Input data: `contract_number`, `name`, `client_name`, `address`, `site_type`, `district`, `keyholder_phone`, `contract_start_date`, `access_notes` (optional). `contract_status` defaults to active
  - Expected result: The site is saved. Its page opens with the message "Site created", and the site appears in the site list
- **ADD-02** Add a site _(neg)_
  - Input data: The contract number already exists in any letter case, the name is empty, or the phone is `12345`
  - Expected result: Nothing is saved. The form is shown again with the entered values kept and an error message next to each wrong field
- **ADD-03** Add a patrol car
  - Input data: `call_sign`, `plate_number`, `model`, `crew_size`, `district`
  - Expected result: The car is saved with status `available` and appears in the car list and in the free-cars panel of the board
- **ADD-04** Add a car _(boundary)_
  - Input data: `crew_size` = 0 / 1 / 4 / 5
  - Expected result: 1 and 4 are accepted. 0 and 5 are rejected with the message "must be between 1 and 4"
- **ADD-05** Register an alarm call
  - Input data: Site (active contract), `alarm_type`, `sensor_zone`, `received_at` (default: now), `description` (optional)
  - Expected result: The call is saved with status `pending` and a priority set by BR-2 (e.g. panic → critical). It appears on the active-calls board of every open dispatcher screen without a page reload
- **ADD-06** Register an alarm call _(boundary)_
  - Input data: `sensor_zone` = 0 / 1 / 99 / 100; `received_at` = now + 1 minute
  - Expected result: Zones 1 and 99 are accepted. Zones 0 and 100 and a time in the future are rejected with a message
- **ADD-07** Register a client call
  - Input data: Site (active contract), `caller_name`, `caller_phone`, `priority` (default normal), `description`
  - Expected result: The call is saved with status `pending` and the chosen priority, and it appears on the board
- **ADD-08** Register a call for a suspended site _(neg)_
  - Input data: A site whose contract is `suspended`
  - Expected result: Rejected with the message "Contract C-00042 is suspended — call cannot be registered". Nothing is saved (BR-1)

### 3.2 Delete

- **DEL-01** Delete a site without calls
  - Input data: Site + confirmation
  - Expected result: The site is deleted, the message "Site deleted" is shown, and the site is gone from the list
- **DEL-02** Delete a site that has calls _(neg)_
  - Input data: Site with N calls
  - Expected result: Refused with the message "Site has N calls and cannot be deleted; suspend the contract instead". Nothing is deleted (BR-9)
- **DEL-03** Delete a car without calls
  - Input data: Car + confirmation
  - Expected result: The car is deleted and is gone from the list and the board
- **DEL-04** Delete a car that has calls _(neg)_
  - Input data: Car with calls
  - Expected result: Refused with a suggestion to put the car out of service. Nothing is deleted (BR-9)
- **DEL-05** Delete one finished call
  - Input data: Call in status `closed` or `cancelled` + confirmation
  - Expected result: The call is deleted. Its site and car remain
- **DEL-06** Delete an active call _(neg)_
  - Input data: Call in status `pending`, `dispatched` or `on_scene`
  - Expected result: Refused with the message "Active call cannot be deleted; cancel or close it first" (BR-8)
- **DEL-07** **Delete calls by criteria** (clean-up of old records)
  - Input data: "Received before" date D (required, today or earlier); statuses `closed` and/or `cancelled` (at least one); call type (optional); outcome (optional)
  - Expected result: Step 1: a preview shows "N calls match". Step 2: after confirmation exactly those N calls are deleted and the message "N calls deleted" is shown. Active calls are never deleted, even if they match the date
- **DEL-08** Delete by criteria _(neg / boundary)_
  - Input data: D is tomorrow; no status is chosen; nothing matches
  - Expected result: A future date or a missing status is rejected with a message. When nothing matches, the message "No calls match" is shown and nothing is deleted

### 3.3 Update

- **UPD-01** Edit a site
  - Input data: Changed attributes
  - Expected result: The changes are saved. The same checks apply as in ADD-01/02
- **UPD-02** Suspend a contract
  - Input data: `contract_status` = suspended
  - Expected result: The change is saved. New calls for the site are refused (ADD-08). Active calls already in progress continue
- **UPD-03** Edit a car
  - Input data: Changed attributes
  - Expected result: The changes are saved. The same checks apply as in ADD-03/04
- **UPD-04** Put a car out of service
  - Input data: `status` = out_of_service
  - Expected result: Allowed only if the car has no active call. Otherwise it is refused with a reference to that call (BR-6). The car leaves the free-cars panel
- **UPD-05** Edit call details
  - Input data: `priority`, `description`, and the subclass attributes (`alarm_type`, `sensor_zone` / `caller_name`, `caller_phone`)
  - Expected result: Allowed while the call is active. For a closed or cancelled call, editing is refused (BR-7)
- **UPD-06** **Dispatch a car**
  - Input data: Call in status `pending`, and a car chosen from the list of available cars (cars from the site's district come first)
  - Expected result: The call becomes `dispatched`, `dispatched_at` = now and the car is set. The car becomes `dispatched`. Both changes are saved together (STO-02), and the board updates without a reload
- **UPD-07** Dispatch a car that is not free _(neg)_
  - Input data: The car is `dispatched`, `on_scene` or `out_of_service`, or another dispatcher took it a moment earlier
  - Expected result: Refused with the message "Car P-12 is not available". The call stays `pending` and nothing changes (BR-3, BR-4)
- **UPD-08** Record arrival
  - Input data: Call in status `dispatched`
  - Expected result: The call becomes `on_scene` and `arrived_at` = now. The car becomes `on_scene`. The response time is shown
- **UPD-09** Close a call
  - Input data: Call in status `on_scene`, `outcome` (required), closing note (optional, added to `description`)
  - Expected result: The call becomes `closed` and `closed_at` = now. The car becomes `available`. Without an outcome, closing is refused
- **UPD-10** Cancel a call
  - Input data: Call in status `pending` or `dispatched`, reason (optional)
  - Expected result: The call becomes `cancelled` and `closed_at` = now. If a car was dispatched, it becomes `available`
- **UPD-11** Wrong order of steps _(neg)_
  - Input data: For example, closing a `pending` call or recording arrival for a `cancelled` call
  - Expected result: Refused with a message that lists the actions allowed in the current status. Nothing changes

### 3.4 Filter, search, sort

- **FLT-01** **Filter calls** (7 criteria)
  - Input data: Any combination of: status, priority, call type, district of the site, period (from–to, by `received_at`), site, car
  - Expected result: The table shows only the calls that match all the chosen criteria, together with the number found. The statistics (3.7) are calculated for the same calls. The filter is kept in the page address, so it survives a reload
- **FLT-02** Filter by period _(boundary)_
  - Input data: from = to (one day); from is later than to
  - Expected result: For one day, all calls of that day from 00:00 to 23:59 Riga time are included. If from is later than to, the message "Period start is after period end" is shown and the list is not filtered
- **FLT-03** Filter with no matches
  - Input data: Criteria that no call matches
  - Expected result: An empty table with the message "No calls match the filter" and a link that resets the filter
- **FLT-04** Search sites by text
  - Input data: Text of at least 2 characters
  - Expected result: Sites whose contract number, name, client or address contains the text, regardless of letter case. For a shorter text, the hint "Enter at least 2 characters" is shown
- **FLT-05** Filter sites
  - Input data: `site_type`, `district`, `contract_status`, combinable with FLT-04
  - Expected result: Only matching sites are listed, together with their count
- **FLT-06** Filter cars
  - Input data: `status`, `district`
  - Expected result: Only matching cars are listed
- **SRT-01** **Sort calls** (4 criteria)
  - Input data: Column: received time (default, newest first), priority (critical first), status, site name. Direction: ascending or descending
  - Expected result: The table is re-ordered. Equal values are ordered by received time, newest first. Sorting combines with the active filter
- **SRT-02** Sort sites
  - Input data: Name, contract number, contract start date
  - Expected result: The table is re-ordered, and the order combines with the search and filter
- **SRT-03** Sort cars
  - Input data: Call sign, status
  - Expected result: The table is re-ordered

### 3.5 Store

- **STO-01** Keep data
  - Input data: Any successful add, update or delete
  - Expected result: The change is written to PostgreSQL immediately. It is visible after a page reload and after the application restarts
- **STO-02** Change a call and its car together
  - Input data: Dispatch, arrival, close or cancel
  - Expected result: The call and the car change together or not at all. If saving fails, both stay as they were and an error message is shown
- **STO-03** Two dispatchers take the same car _(neg)_
  - Input data: Two dispatchers send the same car to two different calls at the same moment
  - Expected result: The first dispatch succeeds. The second is refused as in UPD-07. A car is never on two active calls
- **STO-04** Database refuses invalid records
  - Input data: A duplicate contract number, call sign or plate, or a call without a site, stored without going through the forms
  - Expected result: The database refuses the record (unique indexes, required columns, foreign keys). The application shows an error, and no partial record remains
- **STO-05** Load demo data
  - Input data: Seed command
  - Expected result: The database is filled with synthetic sites, cars and calls: fictitious names, addresses and phones, no real client data

### 3.6 Display

- **DSP-01** Several objects as a table
  - Input data: Menu: Sites / Patrol cars / Calls
  - Expected result: A table with the main attributes in each row. Enum values are shown in plain words, times in Riga local time
- **DSP-02** One object
  - Input data: Click on a table row
  - Expected result: **Site:** all attributes, its call history as a table, and the number of calls. **Car:** all attributes, its current call, and its recent calls. **Call:** all attributes; the timeline received → dispatched → arrived → closed with the time between steps; links to the site and the car
- **DSP-03** Active-calls board (home page)
  - Input data: Open the application
  - Expected result: Calls in status `pending`, `dispatched` or `on_scene`, ordered by priority (critical first) and then by waiting time (longest first), with the waiting time of each call. Next to them, a panel shows every car and its status. Every open screen updates without a reload when any dispatcher changes a call or a car
- **DSP-04** Hints and messages
  - Input data: Any form or action
  - Expected result: Every field has a label and a hint with an example of the format. Every action ends with a confirmation or an error message

### 3.7 Calculations

- **CALC-01** Calls by status and by outcome
  - Input data: Period (default: the current month) and optionally the FLT-01 filters
  - Expected result: The number of calls in each status and each outcome, plus the total
- **CALC-02** Average response time
  - Input data: Period and filters
  - Expected result: The average of `arrived_at − received_at` over calls with an arrival in the period, in minutes with one decimal. Shown overall, per priority and per car. With no arrivals in the period, "—" is shown, not an error
- **CALC-03** Share of false alarms
  - Input data: Period
  - Expected result: Closed calls with outcome `false_alarm` ÷ all closed calls × 100 %, with one decimal. With no closed calls, "—" is shown
- **CALC-04** Sites with the most false alarms
  - Input data: Period, N (default 5)
  - Expected result: The N sites with the most `false_alarm` outcomes in the period. Sites with equal counts are ordered by name

---

## 4. Web interface, API and data storage

### 4.1 Dynamic elements

A dynamic element is a part of the page that changes in the browser in response to a user action or to new data, without loading a new page.

- **DYN-01** Live active-calls board
  - Event → change on the page: Any dispatcher registers, dispatches, closes or cancels a call → the row appears, changes or disappears on every open screen
  - Related requirement: DSP-03, ADD-05
- **DYN-02** Live cars panel
  - Event → change on the page: A car changes status → its status label changes, and the car enters or leaves the list of free cars on every open screen
  - Related requirement: DSP-03, UPD-06
- **DYN-03** Waiting-time counters
  - Event → change on the page: Once a minute → the waiting time of every active call on the board is recalculated in the browser, without a request to the server
  - Related requirement: DSP-03
- **DYN-04** Call form that follows the call type
  - Event → change on the page: Choosing _alarm_ or _client_ → only the fields of that type are shown. Choosing an alarm type → the priority field takes the BR-2 default
  - Related requirement: ADD-05, ADD-07, BR-2
- **DYN-05** Site search while typing
  - Event → change on the page: Typing 2 or more characters → the site list is filtered without pressing a button. Fewer characters → the hint from FLT-04
  - Related requirement: FLT-04
- **DYN-06** Filtering and sorting of calls in place
  - Event → change on the page: Changing a filter or clicking a column header → only the table and the count are reloaded, and the page address is updated
  - Related requirement: FLT-01, SRT-01
- **DYN-07** Dispatch dialog
  - Event → change on the page: Clicking _Dispatch_ → a dialog lists the free cars, the site's district first. After the choice the dialog closes and the call row changes
  - Related requirement: UPD-06, UPD-07
- **DYN-08** Preview of deletion by criteria
  - Event → change on the page: Changing any criterion → the number "N calls match" is recalculated before the confirmation
  - Related requirement: DEL-07
- **DYN-09** Field checks while typing
  - Event → change on the page: Leaving a field with a wrong format → a message appears next to the field before the form is sent. The server still checks everything
  - Related requirement: DSP-04, ADD-02
- **DYN-10** Animation of a new critical call
  - Event → change on the page: A call with priority `critical` appears on the board → its row is highlighted by a short CSS animation
  - Related requirement: DSP-03, BR-2

Technique: Turbo Streams over a WebSocket for DYN-01, DYN-02 and DYN-10; Turbo Frames for DYN-05 … DYN-08; Stimulus controllers for DYN-03, DYN-04 and DYN-09.

### 4.2 REST API

Base path `/api/v1`, JSON in and out. The API applies the same checks and business rules as the pages (2.2–2.7).

- **API-01** `GET /api/v1/sites`, `/api/v1/patrol_cars`, `/api/v1/calls`
  - Input data: The filter and sort parameters of FLT-01, FLT-04 … FLT-06 and SRT-01 … SRT-03
  - Expected result: `200` and a JSON list together with the number of records found
- **API-02** `GET /api/v1/{resource}/{id}`
  - Input data: id
  - Expected result: `200` and the object. `404` when it does not exist
- **API-03** `POST /api/v1/sites`, `/api/v1/patrol_cars`, `/api/v1/calls`
  - Input data: The attributes of ADD-01, ADD-03, ADD-05 or ADD-07
  - Expected result: `201` and the created object. `422` with an error for each wrong field and the same messages as the forms (ADD-02, ADD-08)
- **API-04** `PATCH /api/v1/{resource}/{id}`
  - Input data: Changed attributes
  - Expected result: `200` and the changed object. `422` for wrong data or for a closed or cancelled call (BR-7)
- **API-05** `DELETE /api/v1/{resource}/{id}`
  - Input data: id
  - Expected result: `204`. `422` with the reason when BR-8 or BR-9 forbids the deletion
- **API-06** `POST /api/v1/calls/{id}/dispatch`, `/arrival`, `/close`, `/cancel`
  - Input data: `patrol_car_id` for dispatch, `outcome` for close, an optional reason for cancel
  - Expected result: `200` and the call in its new status. `409` when the car is not available (UPD-07, STO-03). `422` for a wrong order of steps (UPD-11)
- **API-07** `GET /api/v1/statistics`
  - Input data: Period and the FLT-01 filters
  - Expected result: `200` and the results of CALC-01 … CALC-04. A value shown as "—" on the page is `null`
- **API-08** A change made through the API
  - Input data: Any successful API-03 … API-06
  - Expected result: Every open board is updated exactly as after a change on the pages (DYN-01, DYN-02)

### 4.3 Stylesheets

- **Pre-processor: Sass, SCSS syntax.** Variables for the colours of priorities and statuses; mixins for the status labels; nesting; one partial file per page group (board, forms, tables) joined in one main file.
- **Post-processor: PostCSS** with Autoprefixer (browser prefixes) and minification of the result.
- The compiled CSS is a build result and is not stored in the repository.

### 4.4 Data storage

- **PostgreSQL** holds sites, cars and calls (2.6).
- **Call event log** in a NoSQL document database: one document for each change of a call (status before and after, time, car, note). The log is read-only and adds a change history to the call page (DSP-02).

---

## Glossary

- **Monitoring centre** — Round-the-clock room of the security company where dispatchers receive calls
- **Guarded site** — Client premises covered by a monitoring contract
- **Call** — Any request for a patrol: an alarm signal or a client's phone call
- **Dispatch** — Assigning a free patrol car to a call
- **Response time** — Time from receiving the call to the crew's arrival at the site
- **False alarm** — A call where the crew found no intrusion, fire or other threat

# Operations: data, copy and restore

## What the server holds

- The PostgreSQL accessory `db`, volume `patrol_call_system_postgres`: four databases. The primary one holds addresses, sites, cars, calls with their steps, users, car positions, the settings and the errors of production (decision 0010); the others hold the cache, the job queue and the messages of Action Cable (decision 0005).
- The volume `patrol_call_system_photos`: the crew's photos and the users' pictures (Active Storage).
- The volume `patrol_call_system_map`: the map file, built again from OpenStreetMap data by `bin/rails map:build` (decision 0008).

## Where the data comes from

- `db/seeds.rb` and `bin/rails demo:load`: addresses of public buildings from the State Address Register, sites with fictitious clients, cars, 150 finished calls of the last 60 days and three demo users, one for each role but the crew. The demo data is the same at every load.
- `bin/rails addresses:load FILE=aw_eka.csv`: the addresses of a city from the register's file.
- `bin/rails users:create`: users created by the administrator.

## Copy

No copy of the databases or of the volumes is made. The data is made again by the commands below. What was entered on the server after them is not restored: users created by hand, calls, car positions, photos and pictures.

## Restore into an empty database

On the server the container runs `bin/rails db:prepare` at every start: it creates the four databases when they are missing and loads their schemas. The data is then loaded by

```sh
bin/kamal app exec --reuse "bin/rails demo:load"
```

which prints the passwords of the three demo users once. The addresses of a city and the users created by hand are loaded with the commands above.

The same restore is tried on a developer machine in a database of its own, which is removed after the check:

```sh
export DATABASE_URL=postgres:///patrol_call_system_restore_check
bin/rails db:prepare
bin/rails demo:load
bin/rails db:migrate:status
psql patrol_call_system_restore_check -c "select (select count(*) from guarded_sites) sites, (select count(*) from patrol_cars) cars, (select count(*) from calls) calls, (select count(*) from users) users"
bin/rails db:drop
unset DATABASE_URL
```

## What to check after

- `bin/rails db:migrate:status`: every migration `up`, none `down`.
- The rows: 12 sites, 5 cars, 150 calls, 3 users.
- `/up` answers 200, and a demo user signs in.

## Log of restore checks

- 28.11.2026, developer machine, empty database, record `9feb36e`: 34 migrations `up`; 12 sites, 5 cars, 150 calls, 3 users; `db:prepare` 1.7 s and `demo:load` 2.6 s.

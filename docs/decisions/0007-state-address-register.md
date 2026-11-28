# 0007. Addresses from the State Address Register

- Status: accepted
- Date: 2026-10-01
- Pull requests: #3 (specification), #35

## Context

A car has to be sent to the right building, and the site has to be shown on the map. An address typed as free text can be misspelt and has no coordinates.

## Options

- Free text with geocoding by an outside service: each search sends the address out, and the service may change or charge.
- The open data of the State Address Register (data.gov.lv, dataset `varis-atvertie-dati`, CC BY 4.0): official codes and coordinates of every address in Latvia, in a file published daily.

## Decision

A guarded site refers to an `Address` loaded from the register's file `aw_eka.csv` with `bin/rails addresses:load FILE=aw_eka.csv [CITY=...]` (ADD-09, ADD-10). The search ignores case and Latvian diacritics (FLT-07). The file is downloaded when the system is set up and is never stored in the repository.

## Consequences

The register is named as the source on every page with an address search. A new address appears only after a new load of the file. The demo data uses real addresses of public buildings with fictitious client names and phone numbers.

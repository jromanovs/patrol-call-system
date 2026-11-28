# 0008. The map from an own PMTiles file of Latvia

- Status: accepted
- Date: 2026-10-02
- Issue: #16; pull requests: #3 (specification), #50

## Context

The board and the map page show sites, active calls and cars on a map of Latvia (DSP-05, DYN-12). The public tile servers of OpenStreetMap limit heavy use, and a map service of another party needs a key and may charge.

## Options

- Tiles of the public OpenStreetMap servers: no build, but under their usage policy and with every view seen by them.
- A hosted map service: a key, a price and the views seen by the service.
- An own vector tile file: built on the server from the OpenStreetMap extract of Latvia, served with the application and drawn by MapLibre GL in the browser.

## Decision

An own PMTiles file built by tilemaker from the Geofabrik extract `latvia-latest.osm.pbf` with the OSM water polygons for the sea (STO-06). A recurring job at 03:00 Riga time builds it when it is missing or 30 days old; `bin/rails map:build` builds at any age. `/tiles` serves it to signed-in users only (BR-13).

## Consequences

The image carries tilemaker, and the map file of about 145 MB lives in the volume `patrol_call_system_map`. A failed build keeps the previous map. Every map names OpenMapTiles and the OpenStreetMap contributors in its corner, as their licences ask (SPECIFICATION.md 1.6).

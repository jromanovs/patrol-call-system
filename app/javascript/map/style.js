// DSP-05: the look of the map, for the layers of the OpenMapTiles schema that
// config/map writes. Names are drawn in the browser's own font: the style
// names no glyphs file.
const font = [ "sans-serif" ]
const name = [ "get", "name:latin" ]
const colours = {
  ground: "#eef0ec",
  water: "#a8cbe0",
  green: "#d6e8cf",
  built: "#e6e2da",
  building: "#d9d3c7",
  road: "#ffffff",
  casing: "#d1d9e0",
  major: "#fbe3b4",
  rail: "#b8bec4",
  border: "#8c959f",
  label: "#59636e",
  halo: "#ffffff"
}

const width = (stops) => [ "interpolate", [ "exponential", 1.4 ], [ "zoom" ], ...stops.flat() ]

function roads(id, classes, colour, stops, minzoom) {
  const filter = [ "match", [ "get", "class" ], classes, true, false ]
  const line = { "line-cap": "round", "line-join": "round" }
  return [
    { id: `${id}-casing`, type: "line", source: "map", "source-layer": "transportation", minzoom, filter,
      layout: line, paint: { "line-color": colours.casing, "line-width": width(stops.map(([ z, w ]) => [ z, w + 2 ])) } },
    { id, type: "line", source: "map", "source-layer": "transportation", minzoom, filter,
      layout: line, paint: { "line-color": colour, "line-width": width(stops) } }
  ]
}

function label(id, layer, filter, size, minzoom = 0) {
  return {
    id, type: "symbol", source: "map", "source-layer": layer, minzoom, filter,
    layout: { "text-field": name, "text-font": font, "text-size": size, "text-max-width": 8 },
    paint: { "text-color": colours.label, "text-halo-color": colours.halo, "text-halo-width": 1.5 }
  }
}

export function style(url, attribution) {
  return {
    version: 8,
    sources: { map: { type: "vector", url, attribution } },
    layers: [
      { id: "ground", type: "background", paint: { "background-color": colours.ground } },
      { id: "landcover", type: "fill", source: "map", "source-layer": "landcover",
        filter: [ "match", [ "get", "class" ], [ "wood", "grass", "farmland" ], true, false ],
        paint: { "fill-color": colours.green, "fill-opacity": 0.7 } },
      { id: "park", type: "fill", source: "map", "source-layer": "park", paint: { "fill-color": colours.green } },
      { id: "landuse", type: "fill", source: "map", "source-layer": "landuse",
        filter: [ "match", [ "get", "class" ], [ "residential", "commercial", "industrial", "retail" ], true, false ],
        paint: { "fill-color": colours.built, "fill-opacity": 0.6 } },
      { id: "water", type: "fill", source: "map", "source-layer": "water", paint: { "fill-color": colours.water } },
      { id: "waterway", type: "line", source: "map", "source-layer": "waterway",
        paint: { "line-color": colours.water, "line-width": width([ [ 8, 0.5 ], [ 16, 4 ] ]) } },
      { id: "building", type: "fill", source: "map", "source-layer": "building", minzoom: 13,
        paint: { "fill-color": colours.building } },
      { id: "rail", type: "line", source: "map", "source-layer": "transportation", minzoom: 10,
        filter: [ "==", [ "get", "class" ], "rail" ], paint: { "line-color": colours.rail, "line-width": 1.5 } },
      ...roads("road-minor", [ "minor", "service" ], colours.road, [ [ 12, 0.5 ], [ 18, 14 ] ], 12),
      ...roads("road-mid", [ "secondary", "tertiary" ], colours.road, [ [ 8, 0.5 ], [ 18, 18 ] ], 8),
      ...roads("road-major", [ "motorway", "trunk", "primary" ], colours.major, [ [ 5, 0.5 ], [ 18, 22 ] ], 5),
      { id: "border", type: "line", source: "map", "source-layer": "boundary",
        filter: [ "<=", [ "get", "admin_level" ], 2 ],
        paint: { "line-color": colours.border, "line-width": 1.5, "line-dasharray": [ 3, 2 ] } },
      label("water-name", "water_name", true, 12),
      { ...label("street-name", "transportation_name", true, 11, 13),
        layout: { "text-field": name, "text-font": font, "text-size": 11, "symbol-placement": "line" } },
      label("place-minor", "place", [ "match", [ "get", "class" ], [ "suburb", "neighbourhood", "village", "hamlet" ], true, false ], 12, 10),
      label("place-major", "place", [ "match", [ "get", "class" ], [ "city", "town" ], true, false ], 15)
    ]
  }
}

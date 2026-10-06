// DSP-05: the look of the map, for the layers of the OpenMapTiles schema that
// config/map writes. Names are drawn in the browser's own font: the style
// names no glyphs file.
const font = [ "sans-serif" ]
const name = [ "get", "name:latin" ]
// The twelve colours of the map, for a light page and for a dark one (USR-09).
const palettes = {
  light: {
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
  },
  dark: {
    ground: "#1b1f24",
    water: "#0f2a3d",
    green: "#18261c",
    built: "#22262b",
    building: "#2b3036",
    road: "#3a4048",
    casing: "#16191d",
    major: "#5a4a2a",
    rail: "#4a5058",
    border: "#6e7681",
    label: "#9da7b1",
    halo: "#0d1117"
  }
}

const width = (stops) => [ "interpolate", [ "exponential", 1.4 ], [ "zoom" ], ...stops.flat() ]

function roads(colours, id, classes, colour, stops, minzoom) {
  const filter = [ "match", [ "get", "class" ], classes, true, false ]
  const line = { "line-cap": "round", "line-join": "round" }
  return [
    { id: `${id}-casing`, type: "line", source: "map", "source-layer": "transportation", minzoom, filter,
      layout: line, paint: { "line-color": colours.casing, "line-width": width(stops.map(([ z, w ]) => [ z, w + 2 ])) } },
    { id, type: "line", source: "map", "source-layer": "transportation", minzoom, filter,
      layout: line, paint: { "line-color": colour, "line-width": width(stops) } }
  ]
}

function label(colours, id, layer, filter, size, minzoom = 0) {
  return {
    id, type: "symbol", source: "map", "source-layer": layer, minzoom, filter,
    layout: { "text-field": name, "text-font": font, "text-size": size, "text-max-width": 8 },
    paint: { "text-color": colours.label, "text-halo-color": colours.halo, "text-halo-width": 1.5 }
  }
}

// USR-09: whether a page marked so, on a device that asks so, is dark. A
// page that follows the device is dark where the device asks for dark.
export function dark(mark, device) {
  return mark === "dark" || (mark === "system" && device)
}

// The theme is "dark" for a dark page; any other, or none, draws the light map.
export function style(url, attribution, theme) {
  const colours = Object.hasOwn(palettes, theme) ? palettes[theme] : palettes.light

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
      ...roads(colours, "road-minor", [ "minor", "service" ], colours.road, [ [ 12, 0.5 ], [ 18, 14 ] ], 12),
      ...roads(colours, "road-mid", [ "secondary", "tertiary" ], colours.road, [ [ 8, 0.5 ], [ 18, 18 ] ], 8),
      ...roads(colours, "road-major", [ "motorway", "trunk", "primary" ], colours.major, [ [ 5, 0.5 ], [ 18, 22 ] ], 5),
      { id: "border", type: "line", source: "map", "source-layer": "boundary",
        filter: [ "<=", [ "get", "admin_level" ], 2 ],
        paint: { "line-color": colours.border, "line-width": 1.5, "line-dasharray": [ 3, 2 ] } },
      label(colours, "water-name", "water_name", true, 12),
      { ...label(colours, "street-name", "transportation_name", true, 11, 13),
        layout: { "text-field": name, "text-font": font, "text-size": 11, "symbol-placement": "line" } },
      label(colours, "place-minor", "place", [ "match", [ "get", "class" ], [ "suburb", "neighbourhood", "village", "hamlet" ], true, false ], 12, 10),
      label(colours, "place-major", "place", [ "match", [ "get", "class" ], [ "city", "town" ], true, false ], 15)
    ]
  }
}

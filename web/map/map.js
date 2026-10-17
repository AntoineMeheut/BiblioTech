/* Carte OpenMapTiles autonome : aucune police, tuile ou bibliothèque distante. */
"use strict";
const statusElement = document.getElementById("status");
const font = ["Klokantech Noto Sans Regular"];
const named = ["coalesce", ["get", "name:fr"], ["get", "name:latin"], ["get", "name"], ""];
const layer = (id, type, sourceLayer, extra = {}) => ({id, type, source: "europe", "source-layer": sourceLayer, ...extra});
const layers = [
  {id: "background", type: "background", paint: {"background-color": "#f3efe3"}},
  layer("landcover", "fill", "landcover", {paint: {"fill-color": "#dbe5cb", "fill-opacity": 0.7}}),
  layer("parks", "fill", "landuse", {filter: ["in", "class", "park", "forest", "cemetery"], paint: {"fill-color": "#c9dbb8"}}),
  layer("water", "fill", "water", {paint: {"fill-color": "#a9cfdf"}}),
  layer("rivers", "line", "waterway", {paint: {"line-color": "#8ebfd5", "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.4, 14, 2]}}),
  layer("boundaries", "line", "boundary", {filter: ["<=", "admin_level", 4], paint: {"line-color": "#8f8c9d", "line-width": 1, "line-dasharray": [3, 2]}}),
  layer("buildings", "fill", "building", {minzoom: 13, paint: {"fill-color": "#d5c7b7", "fill-outline-color": "#c6b6a4"}}),
  layer("roads-casing", "line", "transportation", {filter: ["!in", "class", "rail", "ferry"], layout: {"line-cap": "round", "line-join": "round"}, paint: {"line-color": "#d2c5ad", "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.5, 12, 2.5, 16, 9]}}),
  layer("roads", "line", "transportation", {filter: ["!in", "class", "rail", "ferry"], layout: {"line-cap": "round", "line-join": "round"}, paint: {"line-color": ["match", ["get", "class"], ["motorway", "trunk"], "#ecc779", "#fffdf7"], "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.3, 12, 1.5, 16, 7]}}),
  layer("railways", "line", "transportation", {filter: ["==", "class", "rail"], minzoom: 9, paint: {"line-color": "#8c9290", "line-width": 1, "line-dasharray": [3, 3]}}),
  layer("road-names", "symbol", "transportation_name", {minzoom: 13, layout: {"symbol-placement": "line", "text-field": named, "text-font": font, "text-size": 11}, paint: {"text-color": "#5d584f", "text-halo-color": "#fffdf7", "text-halo-width": 1.5}}),
  layer("places", "symbol", "place", {layout: {"text-field": named, "text-font": font, "text-size": ["match", ["get", "class"], "country", 18, "city", 15, 12]}, paint: {"text-color": "#34453e", "text-halo-color": "#fffdf7", "text-halo-width": 1.5}})
];

(async () => {
  try {
    if (!maplibregl.supported()) throw new Error("Ce navigateur ne prend pas en charge WebGL. Essayez un navigateur récent.");
    const protocol = new pmtiles.Protocol();
    maplibregl.addProtocol("pmtiles", protocol.tile);
    const archiveUrl = new URL("/maps/europe.pmtiles", location.href).href;
    const archive = new pmtiles.PMTiles(archiveUrl);
    protocol.add(archive);
    const header = await archive.getHeader();
    const map = new maplibregl.Map({
      container: "map", center: [10, 50], zoom: 3.4, maxZoom: 17,
      style: {version: 8, glyphs: new URL("/vendor/fonts/{fontstack}/{range}.pbf", location.href).href.replace(/%7B/g, "{").replace(/%7D/g, "}"),
        sources: {europe: {type: "vector", url: "pmtiles://" + archiveUrl,
          attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> · <a href="https://openmaptiles.org/">OpenMapTiles</a> · Geofabrik'}}, layers}
    });
    map.addControl(new maplibregl.NavigationControl(), "top-right");
    map.addControl(new maplibregl.ScaleControl({unit: "metric"}), "bottom-left");
    map.on("load", () => { statusElement.hidden = true; });
    map.on("error", (event) => {
      statusElement.hidden = false;
      statusElement.textContent = "Une partie de la carte ne se charge pas. Vérifiez la connexion au Wi-Fi local puis rechargez la page.";
      console.error(event.error);
    });
    document.getElementById("overview").addEventListener("click", () => {
      map.fitBounds([[header.minLon, header.minLat], [header.maxLon, header.maxLat]], {padding: 35, maxZoom: 7});
    });
  } catch (error) {
    statusElement.hidden = false;
    statusElement.textContent = "Carte indisponible. " + error.message;
  }
})();

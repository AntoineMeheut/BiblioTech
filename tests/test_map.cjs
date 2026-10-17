/* Validation du lecteur PMTiles réel et du style, sans serveur ni navigateur. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const root = path.resolve(__dirname, "..");

(async () => {
  let options;
  const elements = {};
  const sandbox = {
    console, URL, location: {href: "http://offline.local/map/"},
    document: {getElementById: (id) => elements[id] ||= {addEventListener() {}}},
    maplibregl: {
      supported: () => true, addProtocol() {},
      Map: class {constructor(o) {options = o;} addControl() {} on() {}},
      NavigationControl: class {}, ScaleControl: class {}
    },
    pmtiles: {Protocol: class {add() {}}, PMTiles: class {async getHeader() {return {};}}}
  };
  vm.runInNewContext(fs.readFileSync(path.join(root, "web/map/map.js"), "utf8"), sandbox);
  await new Promise(setImmediate);
  assert(options, "La carte doit être initialisée");
  assert.equal(new URL(options.style.glyphs).hostname, "offline.local");
  assert.equal(options.style.sources.europe.url, "pmtiles://http://offline.local/maps/europe.pmtiles");
  assert(options.style.layers.some(l => l.id === "places"));
  const specPath = process.argv[2];
  if (specPath) {
    const {validateStyleMin} = require(path.resolve(specPath));
    const errors = validateStyleMin(JSON.parse(JSON.stringify(options.style)));
    assert.equal(errors.length, 0, JSON.stringify(errors));
    console.log("Style conforme à la spécification MapLibre.");
  }
  const mapPath = process.argv[3];
  if (mapPath) {
    const ctx = {console, TextDecoder, TextEncoder, Response, Request, Headers,
                 AbortController, DecompressionStream, setTimeout, clearTimeout};
    vm.createContext(ctx);
    vm.runInContext(fs.readFileSync(path.join(root, "web/vendor/pmtiles.js"), "utf8"), ctx);
    const bytes = fs.readFileSync(mapPath);
    const archive = new ctx.pmtiles.PMTiles({
      getKey: () => "monaco-test",
      getBytes: async (offset, length) => {
        const slice = bytes.subarray(offset, offset + length);
        return {data: slice.buffer.slice(slice.byteOffset, slice.byteOffset + slice.byteLength)};
      }
    });
    const header = await archive.getHeader();
    assert.equal(header.tileType, 1);
    const metadata = await archive.getMetadata();
    assert(metadata.vector_layers.some(l => l.id === "transportation"));
    const z = 14, lon = 7.425, lat = 43.735;
    const x = Math.floor((lon + 180) / 360 * 2 ** z);
    const y = Math.floor((1 - Math.asinh(Math.tan(lat * Math.PI / 180)) / Math.PI) / 2 * 2 ** z);
    const tile = await archive.getZxy(z, x, y);
    assert(tile && tile.data.byteLength > 0, "Tuile Monaco absente");
    console.log(`PMTiles JS lit les métadonnées et une tuile réelle de Monaco (${tile.data.byteLength} octets).`);
  }
  console.log("La configuration de la carte utilise uniquement des ressources locales.");
})().catch(error => {console.error(error); process.exitCode = 1;});

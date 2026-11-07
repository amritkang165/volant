// The "Try Volant" calculator worker: VolantCore's CalculationAnswer.answers built for WASI. It
// downloads the gzipped module once, decompresses it with the browser's DecompressionStream,
// compiles it once, and answers each request with a fresh instance. The page ends a request that
// runs too long by terminating this worker.
import { answer } from './calculator.js';

let compiled = null;

/** Downloads, decompresses and compiles the calculator module, once. */
async function load() {
  if (!compiled) {
    const started = performance.now();
    const response = await fetch('/try/calculator/VolantAnswers.wasm.gz');
    if (!response.ok || !response.body) throw new Error('Calculator unavailable');
    const bytes = await new Response(response.body.pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
    const fetchedMs = performance.now() - started;
    compiled = await WebAssembly.compile(bytes);
    self.postMessage({ loaded: true, fetchedMs, compiledMs: performance.now() - started - fetchedMs, bytes: bytes.byteLength });
  }
  return compiled;
}

/** Answers one request (`{id, request}`) with the module's JSON reply text or an error. */
self.onmessage = async (event) => {
  const { id, request } = event.data;
  try {
    const calculator = await load();
    const started = performance.now();
    const output = answer(calculator, request);
    self.postMessage({ id, output, ms: performance.now() - started });
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};

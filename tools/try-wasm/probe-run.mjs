// Runs the Probe WASI program through the browser calculator shim and prints its output, even
// when it traps. Usage: node tools/try-wasm/probe-run.mjs <Probe.wasm>
import fs from 'node:fs';
import { answer } from '../../website/public/try/calculator.js';

const compiled = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
const diagnostics = [];
const realWrite = process.stdout.write.bind(process.stdout);
try {
  realWrite(answer(compiled, '{}', diagnostics));
} catch (error) {
  realWrite(`${error.partialOutput ?? ''}TRAP ${error.message}\n${diagnostics.join('')}\n${error.stack}\n`);
}

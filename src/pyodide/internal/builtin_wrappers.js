import { default as Eval } from "internal:unsafe-eval";

let evalableFuncs = undefined;
export function setEvalableFunctions(funcs) {
  if (evalableFuncs) {
    return;
  }
  console.log("setEvalableFunctions", { funcs });
  evalableFuncs = funcs;
}

function prepareStackTrace(error, stack) {
  if (stack.length < 3) {
    return false;
  }
  Error.prepareStackTrace = undefined;
  try {
    const funcName = stack[2].getFunctionName();
    const fileName = stack[2].getFileName();
    return (
      funcName === "convertJsFunctionToWasm" &&
      fileName === "pyodide-internal:pyodide-bundle/pyodide.asm"
    );
  } catch (e) {
    console.warn(e);
    return false;
  }
}

function checkCallee() {
  const origPrepareStackTrace = Error.prepareStackTrace;
  let isOkay;
  try {
    Error.prepareStackTrace = prepareStackTrace;
    isOkay = new Error().stack;
  } finally {
    Error.prepareStackTrace = origPrepareStackTrace;
  }
  if (!isOkay) {
    console.warn("Invalid call to `WebAssembly.Module`");
    throw new Error();
  }
}

// Wrapper for WebAssembly that makes WebAssembly.Module work by temporarily
// turning on eval
export function newWasmModule(buffer) {
  checkCallee();
  return Eval.newWasmModule(buffer);
}

// Wrapper for Date.now that always advances by at least a millisecond.
let lastTime;
let lastDelta = 0;
export function monotonicDateNow() {
  const now = Date.now();
  if (now === lastTime) {
    lastDelta++;
  } else {
    lastTime = now;
    lastDelta = 0;
  }
  return now + lastDelta;
}
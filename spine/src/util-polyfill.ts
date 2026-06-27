/**
 * Node 23+ removed the long-deprecated `util.is*` type-check helpers
 * (isNullOrUndefined, isNull, isArray, …). `@vladmandic/face-api` and the
 * tfjs-node code it bundles still call `util.isNullOrUndefined(...)` at runtime,
 * so on Node 23+ (we run Node 26) every face detection throws:
 *
 *   TypeError: (0 , util_1.isNullOrUndefined) is not a function
 *
 * That breaks /enroll, /check-face, and the autonomous recognizer. We restore the
 * removed helpers on the shared `util` singleton. Import this module FIRST —
 * before anything that pulls in face-api — so the helpers exist before any call.
 *
 * These are exact re-implementations of Node's historical definitions.
 */
import util from 'util';

const u = util as unknown as Record<string, unknown>;

function def(name: string, fn: (v: any) => boolean): void {
  if (typeof u[name] !== 'function') u[name] = fn;
}

def('isNullOrUndefined', (v) => v === null || v === undefined);
def('isNull', (v) => v === null);
def('isUndefined', (v) => v === undefined);
def('isArray', (v) => Array.isArray(v));
def('isBoolean', (v) => typeof v === 'boolean');
def('isNumber', (v) => typeof v === 'number');
def('isString', (v) => typeof v === 'string');
def('isSymbol', (v) => typeof v === 'symbol');
def('isFunction', (v) => typeof v === 'function');
def('isObject', (v) => v !== null && typeof v === 'object');
def('isPrimitive', (v) => v === null || (typeof v !== 'object' && typeof v !== 'function'));
def('isBuffer', (v) => Buffer.isBuffer(v));
def('isRegExp', (v) => Object.prototype.toString.call(v) === '[object RegExp]');
def('isDate', (v) => Object.prototype.toString.call(v) === '[object Date]');
def('isError', (v) => Object.prototype.toString.call(v) === '[object Error]' || v instanceof Error);

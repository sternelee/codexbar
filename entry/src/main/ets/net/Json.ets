/**
 * CodexBar Mobile — JSON 访问辅助
 * ArkTS 严格模式下安全遍历 JSON.parse 结果的工具集。
 */

export type Json = Object | null;

export function parseJson(text: string): Json {
  try {
    return JSON.parse(text) as Json;
  } catch (e) {
    return null;
  }
}

export function isObj(v: Json): boolean {
  return v !== null && v instanceof Object && !(v instanceof Array);
}

export function asObj(v: Json): Record<string, Json> | null {
  if (isObj(v)) {
    return v as Record<string, Json>;
  }
  return null;
}

export function asArray(v: Json): Json[] | null {
  if (v !== null && v instanceof Array) {
    return v as Json[];
  }
  return null;
}

export function str(o: Record<string, Json> | null, key: string, dflt: string = ''): string {
  if (o == null) {
    return dflt;
  }
  const v = o[key];
  if (typeof v === 'string') {
    return v as string;
  }
  if (typeof v === 'number') {
    return `${v}`;
  }
  return dflt;
}

export function optStr(o: Record<string, Json> | null, key: string): string | null {
  if (o == null) {
    return null;
  }
  const v = o[key];
  if (typeof v === 'string') {
    return v as string;
  }
  return null;
}

export function num(o: Record<string, Json> | null, key: string, dflt: number = 0): number {
  if (o == null) {
    return dflt;
  }
  const v = o[key];
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const parsed = parseFloat(v as string);
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return dflt;
}

export function optNum(o: Record<string, Json> | null, key: string): number | null {
  if (o == null) {
    return null;
  }
  const v = o[key];
  if (typeof v === 'number') {
    return v as number;
  }
  if (typeof v === 'string') {
    const parsed = parseFloat(v as string);
    if (!isNaN(parsed)) {
      return parsed;
    }
  }
  return null;
}

export function bool(o: Record<string, Json> | null, key: string, dflt: boolean = false): boolean {
  if (o == null) {
    return dflt;
  }
  const v = o[key];
  if (typeof v === 'boolean') {
    return v as boolean;
  }
  return dflt;
}

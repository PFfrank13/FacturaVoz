'use strict';
/**
 * Fechas y zonas horarias.
 *
 * Regla del Hub: en la base todo se guarda como instante UTC (ISO 8601). Las fechas "de calendario"
 * (hasta qué día está pagado) se interpretan en la zona horaria de cada licencia (por defecto
 * America/Lima). Así una licencia pagada "hasta el 18 de noviembre" funciona hasta las 23:59:59
 * de ese día en Lima, y no se corta a las 19:00 por usar la medianoche UTC (error del sistema anterior).
 */
const DEFAULT_TZ = 'America/Lima';
const DAY = 864e5;

const nowIso = (ms = Date.now()) => new Date(ms).toISOString();

const fmtCache = new Map();
function dtf(tz) {
  if (!fmtCache.has(tz)) {
    fmtCache.set(tz, new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    }));
  }
  return fmtCache.get(tz);
}

function parts(ms, tz) {
  const o = {};
  for (const p of dtf(tz).formatToParts(new Date(ms))) if (p.type !== 'literal') o[p.type] = +p.value;
  return o;
}

/** Diferencia (ms) entre la hora local de tz y UTC en ese instante. */
function tzOffsetMs(ms, tz) {
  const p = parts(ms, tz);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - Math.floor(ms / 1000) * 1000;
}

function isValidTz(tz) {
  try { dtf(tz); return true; } catch (_) { return false; }
}

const isDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s + 'T00:00:00Z'));

/** Fecha de calendario (YYYY-MM-DD) de un instante, en la zona tz. */
function localDate(instant, tz = DEFAULT_TZ) {
  const ms = typeof instant === 'number' ? instant : Date.parse(instant);
  const p = parts(ms, tz);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

/** Instante UTC (ISO) en que termina el día `date` en la zona tz (23:59:59.999 local). */
function endOfLocalDay(date, tz = DEFAULT_TZ) {
  const [y, m, d] = date.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d, 23, 59, 59, 999);
  let res = guess - tzOffsetMs(guess, tz);
  res = guess - tzOffsetMs(res, tz); // segunda pasada por si hay cambio de horario
  return nowIso(res);
}

/** Instante UTC (ISO) en que empieza el día `date` en la zona tz. */
function startOfLocalDay(date, tz = DEFAULT_TZ) {
  const [y, m, d] = date.split('-').map(Number);
  const guess = Date.UTC(y, m - 1, d, 0, 0, 0, 0);
  let res = guess - tzOffsetMs(guess, tz);
  res = guess - tzOffsetMs(res, tz);
  return nowIso(res);
}

function addDays(date, n) {
  return new Date(Date.parse(date + 'T00:00:00Z') + n * DAY).toISOString().slice(0, 10);
}

function daysInMonth(y, m /* 1-12 */) { return new Date(Date.UTC(y, m, 0)).getUTCDate(); }

/**
 * Siguiente "fecha de corte de ciclo" a partir del inicio de un periodo.
 * Respeta el día ancla: una licencia que empezó un 31 se renueva el 30 en abril y el 28 en febrero,
 * pero vuelve al 31 en marzo (no se va corriendo mes a mes).
 * unit: 'day' | 'month' | 'year'.
 */
function nextBoundary(startDate, unit, count, anchorDay) {
  if (unit === 'day') return addDays(startDate, count);
  const months = unit === 'year' ? 12 * count : count;
  const [y, m] = startDate.split('-').map(Number);
  const idx = (m - 1) + months;
  const ny = y + Math.floor(idx / 12), nm = (idx % 12) + 1;
  const day = Math.min(anchorDay || +startDate.slice(8, 10), daysInMonth(ny, nm));
  return `${ny}-${String(nm).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/** Último día cubierto por `periods` ciclos que empiezan en startDate. */
function lastCoveredDay(startDate, unit, count, periods, anchorDay) {
  let s = startDate;
  for (let i = 0; i < periods; i++) s = nextBoundary(s, unit, count, anchorDay);
  return addDays(s, -1);
}

/** Días enteros de calendario entre dos fechas (b - a). */
const diffDays = (a, b) => Math.round((Date.parse(b + 'T00:00:00Z') - Date.parse(a + 'T00:00:00Z')) / DAY);

module.exports = {
  DEFAULT_TZ, DAY, nowIso, isDate, isValidTz, localDate, endOfLocalDay, startOfLocalDay,
  addDays, nextBoundary, lastCoveredDay, diffDays, tzOffsetMs, daysInMonth,
};

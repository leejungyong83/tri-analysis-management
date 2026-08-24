/**
 * TRI 통합 앱 — Google Apps Script 백엔드 (v4: 생산 이력 통합)
 *
 * 배포: 이 스크립트를 대상 스프레드시트에 바인딩(확장 프로그램 > Apps Script)하고
 *       웹 앱으로 배포(실행: 나, 액세스: 모든 사용자)한다.
 *
 * Script Properties: APP_TOKEN(필수), APP_TOKEN_OLD(로테이션), PHOTO_FOLDER_ID(필수)
 *
 * 데이터 모델 (이원화):
 *   "Production" 시트  : 생산 이력(요약·원천). LOT은 생산 투입 시 서버 채번.
 *                        컬럼: LOT번호·MODEL·수량·투입시간·검사결과·Rework·Rework투입시간·Rework수량·상태
 *   월별 탭 "YYYY-MM"  : 검사 상세(Rack1~5·사진5·CA·검사자·Bar). LOT번호로 Production과 연결.
 *   "Masters" 탭       : A열 type(inspector|model|ca|config), B열 value, C열 extra
 *
 * 생산LOT 상태 머신(Production.상태):
 *   PRODUCED(생산·미검사) → 검사 → DONE_OK | NG_REWORK_WAIT(NG,재작업대기)
 *   NG_REWORK_WAIT → Rework재투입 → REWORK_READY(재검사대기) → 재검사 → DONE_OK|NG_REWORK_WAIT
 *   미검사 목록 = 상태 in [PRODUCED, REWORK_READY]
 *
 * date 필드는 클라이언트가 계산한 "업무일"(하루 시작 08:00, 00~08시는 전날)이다.
 */

// ---- 검사 상세(월별 탭) 스키마 (기존 유지) ----
var INSP_HEADERS = [
  'UUID', '날짜', 'CA', '검사자', 'LOT번호', '시간', 'Bar번호', 'Model',
  'Rack1', 'Rack2', 'Rack3', 'Rack4', 'Rack5', '종합판정',
  'Rack1사진', 'Rack2사진', 'Rack3사진', 'Rack4사진', 'Rack5사진',
  'Rework등록', 'Void', '서버기록시각', '시계편차'
];
var INSP = {
  UUID: 1, DATE: 2, CA: 3, INSPECTOR: 4, LOT: 5, TIME: 6, BAR: 7, MODEL: 8,
  RACK1: 9, VERDICT: 14, PHOTO1: 15, REWORK: 20, VOID: 21, SERVER_TS: 22, SKEW: 23
};

// ---- 생산 이력 시트 스키마 (신규, 사용자 지정 컬럼 순서 + 상태) ----
var PROD_SHEET = 'Production';
var PROD_HEADERS = [
  'LOT번호', 'MODEL', '수량', '투입시간', '검사결과',
  'Rework', 'Rework투입시간', 'Rework수량', '상태'
];
var PROD = { LOT: 1, MODEL: 2, QTY: 3, INTIME: 4, RESULT: 5,
             REWORK: 6, RW_TIME: 7, RW_QTY: 8, STATUS: 9 };
var ST = { PRODUCED: 'PRODUCED', DONE_OK: 'DONE_OK',
          NG_WAIT: 'NG_REWORK_WAIT', REWORK_READY: 'REWORK_READY' };

var MAX_MONTH_TABS = 12;
var SKEW_LIMIT_MS = 10 * 60 * 1000;

// ---------------------------------------------------------------- entrypoints

function doPost(e) { return handle_(e); }
function doGet(e) { return handle_(e); }

function handle_(e) {
  try {
    var req = parseRequest_(e);
    if (!checkToken_(req.token)) return json_({ ok: false, error: 'UNAUTHORIZED' });
    switch (req.action) {
      // 생산
      case 'produce':         return json_(produce_(req));
      case 'listUninspected': return json_(listUninspected_(req));
      case 'reworkInput':     return json_(reworkInput_(req));
      case 'productionList':  return json_(productionList_(req));
      case 'productionStats': return json_(productionStats_(req));
      // 검사
      case 'submit':          return json_(submit_(req));
      case 'attachPhoto':     return json_(attachPhoto_(req));
      case 'list':            return json_(list_(req));
      case 'stats':           return json_(stats_(req));
      case 'void':            return json_(voidRecord_(req));
      // 공통
      case 'masters':         return json_(masters_());
      default:                return json_({ ok: false, error: 'UNKNOWN_ACTION' });
    }
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

function parseRequest_(e) {
  var body = {};
  if (e && e.postData && e.postData.contents) {
    if (e.postData.contents.length > 2 * 1024 * 1024 + 64 * 1024) throw new Error('PAYLOAD_TOO_LARGE');
    body = JSON.parse(e.postData.contents);
  }
  var params = (e && e.parameter) || {};
  var merged = {};
  Object.keys(params).forEach(function (k) { merged[k] = params[k]; });
  Object.keys(body).forEach(function (k) { merged[k] = body[k]; });
  return merged;
}

function checkToken_(token) {
  if (!token) return false;
  var props = PropertiesService.getScriptProperties();
  return token === props.getProperty('APP_TOKEN') ||
    (props.getProperty('APP_TOKEN_OLD') && token === props.getProperty('APP_TOKEN_OLD'));
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

// ---------------------------------------------------------------- 생산: produce

/**
 * 생산 투입 등록 + LOT 서버 채번(YYMMDD+일련번호, 업무일 date 기준 — 채번 권위가 여기로 이동).
 * 멱등: reqId(클라이언트 생성)로 중복 방지. 중복 시 기존 lot 반환.
 * req: { reqId, date(업무일 yyyy-MM-dd), time(HH:mm), model, qty }
 */
function produce_(req) {
  requireFields_(req, ['reqId', 'date', 'time', 'model', 'qty']);
  var cache = CacheService.getScriptCache();
  var cached = cache.get('prod:' + req.reqId);
  if (cached) return { ok: true, duplicate: true, lot: cached };

  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  var lot;
  try {
    var sheet = ensureProdSheet_();
    // 멱등 2차: reqId 흔적을 상태열 뒤 메모로 남기지 않으므로 캐시가 1차. 여기선 채번.
    lot = generateLot_(req.date, sheet);
    sheet.appendRow([
      lot, req.model, req.qty, req.date + ' ' + req.time,
      '', '', '', '', ST.PRODUCED
    ]);
  } finally {
    lock.releaseLock();
  }
  cache.put('prod:' + req.reqId, lot, 21600);
  return { ok: true, lot: lot };
}

/** LOT 채번: Production 시트의 그날(YYMMDD) 최대 일련번호 + 1. lock 안에서만 호출. */
function generateLot_(dateStr, sheet) {
  var ymd = dateStr.substring(2, 4) + dateStr.substring(5, 7) + dateStr.substring(8, 10);
  var last = sheet.getLastRow();
  var maxSeq = 0;
  if (last >= 2) {
    var lots = sheet.getRange(2, PROD.LOT, last - 1, 1).getValues();
    for (var i = 0; i < lots.length; i++) {
      var v = String(lots[i][0]);
      if (v.length === 9 && v.substring(0, 6) === ymd) {
        var seq = parseInt(v.substring(6), 10);
        if (!isNaN(seq) && seq > maxSeq) maxSeq = seq;
      }
    }
  }
  return ymd + ('00' + (maxSeq + 1)).slice(-3);
}

// ---------------------------------------------------------------- 생산: 미검사 목록

/** 미검사 생산LOT 목록 (상태 PRODUCED 또는 REWORK_READY). 최신순. */
function listUninspected_(req) {
  var rows = allProdRows_();
  var out = [];
  rows.forEach(function (r) {
    var st = String(r[PROD.STATUS - 1]);
    if (st === ST.PRODUCED || st === ST.REWORK_READY) {
      out.push({
        lot: String(r[PROD.LOT - 1]), model: String(r[PROD.MODEL - 1]),
        qty: r[PROD.QTY - 1], intime: normIntime_(r[PROD.INTIME - 1]),
        status: st, reworkLot: st === ST.REWORK_READY ? 'R' + String(r[PROD.LOT - 1]) : null
      });
    }
  });
  out.reverse(); // 최신순
  return { ok: true, records: out };
}

/** 전체 생산이력 (기간 필터). req: { dateFrom?, dateTo? } — 투입시간 날짜 기준 */
function productionList_(req) {
  var rows = filterProdByDate_(req);
  return { ok: true, records: rows.map(prodRowToObj_) };
}

function prodRowToObj_(r) {
  return {
    lot: String(r[PROD.LOT - 1]), model: String(r[PROD.MODEL - 1]), qty: r[PROD.QTY - 1],
    intime: normIntime_(r[PROD.INTIME - 1]), result: String(r[PROD.RESULT - 1]),
    rework: String(r[PROD.REWORK - 1]), reworkTime: normIntime_(r[PROD.RW_TIME - 1]),
    reworkQty: r[PROD.RW_QTY - 1], status: String(r[PROD.STATUS - 1])
  };
}

// ---------------------------------------------------------------- 생산: Rework 재투입

/**
 * Rework 재투입 등록. NG인 생산LOT의 Rework투입시간·수량 기록 → 상태 REWORK_READY(재검사대기).
 * req: { lot, date(업무일), time, qty }. 경고: qty > 생산수량.
 */
function reworkInput_(req) {
  requireFields_(req, ['lot', 'date', 'time', 'qty']);
  var found = findProdRow_(req.lot);
  if (!found) return { ok: false, error: 'LOT_NOT_FOUND' };
  var sheet = found.sheet, row = found.row;
  var prodQty = Number(sheet.getRange(row, PROD.QTY).getValue());
  sheet.getRange(row, PROD.RW_TIME).setValue(req.date + ' ' + req.time);
  sheet.getRange(row, PROD.RW_QTY).setValue(req.qty);
  sheet.getRange(row, PROD.STATUS).setValue(ST.REWORK_READY);
  var warn = Number(req.qty) > prodQty ? 'REWORK_QTY_EXCEEDS_PRODUCTION' : null;
  return { ok: true, warn: warn };
}

// ---------------------------------------------------------------- 생산: 통계

/** 생산 지표: 생산량·미검사·검사율·NG율·Rework율 + Model별 + 일별 추이. req: { dateFrom?, dateTo? } */
function productionStats_(req) {
  var rows = filterProdByDate_(req);
  var produced = 0, inspected = 0, uninspected = 0, ng = 0, rework = 0, qtySum = 0;
  var byModel = {}, byDay = {};
  rows.forEach(function (r) {
    produced++;
    var st = String(r[PROD.STATUS - 1]);
    var result = String(r[PROD.RESULT - 1]);
    var model = String(r[PROD.MODEL - 1]);
    var day = normIntime_(r[PROD.INTIME - 1]).substring(0, 10);
    var q = Number(r[PROD.QTY - 1]) || 0;
    qtySum += q;
    if (st === ST.PRODUCED || st === ST.REWORK_READY) uninspected++; else inspected++;
    if (result === 'NG') ng++;
    if (String(r[PROD.REWORK - 1]) !== '') rework++;
    if (!byModel[model]) byModel[model] = { produced: 0, ng: 0, qty: 0 };
    byModel[model].produced++; byModel[model].ng += (result === 'NG' ? 1 : 0); byModel[model].qty += q;
    if (!byDay[day]) byDay[day] = { produced: 0, ng: 0 };
    byDay[day].produced++; byDay[day].ng += (result === 'NG' ? 1 : 0);
  });
  return {
    ok: true, produced: produced, inspected: inspected, uninspected: uninspected,
    ng: ng, rework: rework, qtySum: qtySum,
    inspectRate: produced ? inspected / produced : 0,
    ngRate: inspected ? ng / inspected : 0,
    reworkRate: produced ? rework / produced : 0,
    byModel: byModel, byDay: byDay
  };
}

// ---------------------------------------------------------------- 검사: submit

/**
 * 검사 기록 (사진 제외). LOT은 클라이언트가 선택한 생산LOT(채번 안 함).
 * 월별 탭에 검사 상세 append + Production 행 검사결과/Rework/상태 갱신.
 * req: { uuid, date(검사 업무일), ca, inspector, lot, time, bar, model, racks[5], deviceNow }
 */
function submit_(req) {
  requireFields_(req, ['uuid', 'date', 'ca', 'inspector', 'lot', 'time', 'bar', 'model', 'racks']);
  if (!Array.isArray(req.racks) || req.racks.length !== 5) throw new Error('RACKS_MUST_BE_5');
  req.racks.forEach(function (r) { if (r !== 'OK' && r !== 'NG') throw new Error('RACK_VALUE_INVALID'); });

  var tabName = req.date.substring(0, 7);
  var cache = CacheService.getScriptCache();
  if (cache.get('uuid:' + req.uuid)) return { ok: true, duplicate: true };
  if (findRowByUuid_(tabName, req.uuid)) { cache.put('uuid:' + req.uuid, '1', 21600); return { ok: true, duplicate: true }; }

  var verdict = req.racks.indexOf('NG') >= 0 ? 'NG' : 'OK';
  var skew = '';
  if (req.deviceNow) {
    var diff = Math.abs(new Date(req.deviceNow).getTime() - Date.now());
    if (diff > SKEW_LIMIT_MS) skew = 'SKEW:' + Math.round(diff / 60000) + 'min';
  }

  var prodUpdated = false;
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    // 1) 검사 상세(월별 탭)
    var sheet = ensureMonthSheet_(tabName);
    sheet.appendRow([
      req.uuid, req.date, req.ca, req.inspector, req.lot, req.time, req.bar, req.model,
      req.racks[0], req.racks[1], req.racks[2], req.racks[3], req.racks[4], verdict,
      'pending', 'pending', 'pending', 'pending', 'pending',
      verdict === 'NG' ? 'Y' : '', '',
      Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd HH:mm:ss'), skew
    ]);
    // 2) Production 행 갱신 (검사결과 자동 반영)
    var found = findProdRow_(req.lot);
    if (found) {
      prodUpdated = true;
      found.sheet.getRange(found.row, PROD.RESULT).setValue(verdict);
      if (verdict === 'NG') {
        found.sheet.getRange(found.row, PROD.REWORK).setValue('R' + req.lot);
        found.sheet.getRange(found.row, PROD.STATUS).setValue(ST.NG_WAIT);
      } else {
        found.sheet.getRange(found.row, PROD.STATUS).setValue(ST.DONE_OK);
      }
    }
  } finally {
    lock.releaseLock();
  }
  cache.put('uuid:' + req.uuid, '1', 21600);
  return { ok: true, verdict: verdict, skew: skew || null, prodUpdated: prodUpdated };
}

// ---------------------------------------------------------------- 검사: attachPhoto (기존)

function attachPhoto_(req) {
  requireFields_(req, ['uuid', 'rackIndex', 'photoUuid', 'date', 'base64']);
  var rackIndex = parseInt(req.rackIndex, 10);
  if (!(rackIndex >= 1 && rackIndex <= 5)) throw new Error('RACK_INDEX_INVALID');
  var tabName = req.date.substring(0, 7);
  var found = findRowByUuid_(tabName, req.uuid);
  if (!found) return { ok: false, error: 'RECORD_NOT_FOUND' };
  var lot = String(found.sheet.getRange(found.row, INSP.LOT).getValue());
  var fileName = sanitize_(lot) + '_rack' + rackIndex + '_' + sanitize_(req.photoUuid) + '.jpg';
  var folder = ensureMonthFolder_(tabName);
  var url, it = folder.getFilesByName(fileName);
  if (it.hasNext()) url = it.next().getUrl();
  else url = folder.createFile(Utilities.newBlob(Utilities.base64Decode(req.base64), req.mimeType || 'image/jpeg', fileName)).getUrl();
  found.sheet.getRange(found.row, INSP.PHOTO1 + (rackIndex - 1)).setValue(url);
  return { ok: true, url: url, rackIndex: rackIndex };
}

// ---------------------------------------------------------------- 검사: list / stats (기존, 월별 탭)

function list_(req) { return { ok: true, records: collectInspRows_(req).map(inspRowToObj_) }; }

function stats_(req) {
  var rows = collectInspRows_(req);
  var total = 0, ng = 0, pendingPhotos = 0, byModel = {};
  rows.forEach(function (r) {
    total++;
    var isNg = r[INSP.VERDICT - 1] === 'NG';
    if (isNg) ng++;
    for (var p = 0; p < 5; p++) if (String(r[INSP.PHOTO1 - 1 + p]) === 'pending') pendingPhotos++;
    var m = String(r[INSP.MODEL - 1]);
    if (!byModel[m]) byModel[m] = { total: 0, ng: 0 };
    byModel[m].total++; if (isNg) byModel[m].ng++;
  });
  return { ok: true, total: total, ng: ng, ngRate: total ? ng / total : 0, pendingPhotos: pendingPhotos, byModel: byModel };
}

function collectInspRows_(req) {
  var from = req.dateFrom || Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-01');
  var to = req.dateTo || Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd');
  var tabs = monthTabsBetween_(from.substring(0, 7), to.substring(0, 7));
  if (tabs.length > MAX_MONTH_TABS) throw new Error('RANGE_TOO_WIDE_MAX_12_MONTHS');
  var ss = SpreadsheetApp.getActiveSpreadsheet(), out = [];
  tabs.forEach(function (tabName) {
    var sheet = ss.getSheetByName(tabName);
    if (!sheet || sheet.getLastRow() < 2) return;
    var values = sheet.getRange(2, 1, sheet.getLastRow() - 1, INSP_HEADERS.length).getValues();
    values.forEach(function (r) {
      var d = normDate_(r[INSP.DATE - 1]);
      if (d < from || d > to) return;
      if (req.lot && String(r[INSP.LOT - 1]) !== String(req.lot)) return;
      if (req.model && String(r[INSP.MODEL - 1]) !== String(req.model)) return;
      if (req.ngOnly === '1' && r[INSP.VERDICT - 1] !== 'NG') return;
      if (req.includeVoid !== '1' && String(r[INSP.VOID - 1]) === 'Y') return;
      out.push(r);
    });
  });
  return out;
}

function inspRowToObj_(r) {
  var photos = [];
  for (var p = 0; p < 5; p++) photos.push(String(r[INSP.PHOTO1 - 1 + p]));
  return {
    uuid: r[INSP.UUID - 1], date: normDate_(r[INSP.DATE - 1]), ca: r[INSP.CA - 1],
    inspector: r[INSP.INSPECTOR - 1], lot: String(r[INSP.LOT - 1]), time: normTime_(r[INSP.TIME - 1]),
    bar: String(r[INSP.BAR - 1]), model: r[INSP.MODEL - 1],
    racks: [r[INSP.RACK1 - 1], r[INSP.RACK1], r[INSP.RACK1 + 1], r[INSP.RACK1 + 2], r[INSP.RACK1 + 3]],
    verdict: r[INSP.VERDICT - 1], photos: photos,
    rework: r[INSP.REWORK - 1] === 'Y', voided: String(r[INSP.VOID - 1]) === 'Y', skew: r[INSP.SKEW - 1] || null
  };
}

/** 검사 무효화: 월별 탭 Void='Y' + Production 검사결과·상태 되돌림(PRODUCED). req: { uuid, date } */
function voidRecord_(req) {
  requireFields_(req, ['uuid', 'date']);
  var found = findRowByUuid_(req.date.substring(0, 7), req.uuid);
  if (!found) return { ok: false, error: 'RECORD_NOT_FOUND' };
  found.sheet.getRange(found.row, INSP.VOID).setValue('Y');
  var lot = String(found.sheet.getRange(found.row, INSP.LOT).getValue());
  var prod = findProdRow_(lot);
  if (prod) {
    prod.sheet.getRange(prod.row, PROD.RESULT).setValue('');
    prod.sheet.getRange(prod.row, PROD.STATUS).setValue(ST.PRODUCED);
  }
  return { ok: true };
}

// ---------------------------------------------------------------- masters

function masters_() {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Masters');
  var result = { inspectors: [], models: [], cas: [], config: {} };
  if (sheet && sheet.getLastRow() >= 1) {
    sheet.getRange(1, 1, sheet.getLastRow(), 3).getValues().forEach(function (r) {
      var type = String(r[0]).toLowerCase();
      if (type === 'inspector') result.inspectors.push(String(r[1]));
      else if (type === 'model') result.models.push(String(r[1]));
      else if (type === 'ca') result.cas.push(String(r[1]));
      else if (type === 'config') result.config[String(r[1])] = String(r[2]);
    });
  }
  return { ok: true, masters: result };
}

// ---------------------------------------------------------------- helpers

function requireFields_(req, fields) {
  fields.forEach(function (f) {
    if (req[f] === undefined || req[f] === null || req[f] === '') throw new Error('MISSING_FIELD:' + f);
  });
}

function allProdRows_() {
  var sheet = ensureProdSheet_();
  if (sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, PROD_HEADERS.length).getValues();
}

function filterProdByDate_(req) {
  var from = req.dateFrom, to = req.dateTo;
  return allProdRows_().filter(function (r) {
    if (!from && !to) return true;
    var d = normIntime_(r[PROD.INTIME - 1]).substring(0, 10);
    if (from && d < from) return false;
    if (to && d > to) return false;
    return true;
  });
}

/** Production 시트에서 LOT으로 행 조회 (TextFinder, LOT 열만) */
function findProdRow_(lot) {
  var sheet = ensureProdSheet_();
  if (sheet.getLastRow() < 2) return null;
  var cell = sheet.getRange(2, PROD.LOT, sheet.getLastRow() - 1, 1)
    .createTextFinder(String(lot)).matchEntireCell(true).findNext();
  return cell ? { sheet: sheet, row: cell.getRow() } : null;
}

function findRowByUuid_(tabName, uuid) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(tabName);
  if (!sheet || sheet.getLastRow() < 2) return null;
  var cell = sheet.getRange(2, INSP.UUID, sheet.getLastRow() - 1, 1)
    .createTextFinder(uuid).matchEntireCell(true).findNext();
  return cell ? { sheet: sheet, row: cell.getRow() } : null;
}

function ensureProdSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(PROD_SHEET);
  if (!sheet) {
    sheet = ss.insertSheet(PROD_SHEET);
    sheet.appendRow(PROD_HEADERS);
    sheet.setFrozenRows(1);
    sheet.getRange(1, PROD.LOT, sheet.getMaxRows(), 1).setNumberFormat('@');
    sheet.getRange(1, PROD.INTIME, sheet.getMaxRows(), 1).setNumberFormat('@');
    sheet.getRange(1, PROD.RW_TIME, sheet.getMaxRows(), 1).setNumberFormat('@');
  }
  return sheet;
}

function ensureMonthSheet_(tabName) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(tabName);
  if (!sheet) {
    sheet = ss.insertSheet(tabName);
    sheet.appendRow(INSP_HEADERS);
    sheet.setFrozenRows(1);
    sheet.getRange(1, INSP.DATE, sheet.getMaxRows(), 1).setNumberFormat('@');
    sheet.getRange(1, INSP.TIME, sheet.getMaxRows(), 1).setNumberFormat('@');
    sheet.getRange(1, INSP.LOT, sheet.getMaxRows(), 1).setNumberFormat('@');
    sheet.getRange(1, INSP.BAR, sheet.getMaxRows(), 1).setNumberFormat('@');
  }
  return sheet;
}

function ensureMonthFolder_(tabName) {
  var rootId = PropertiesService.getScriptProperties().getProperty('PHOTO_FOLDER_ID');
  if (!rootId) throw new Error('PHOTO_FOLDER_ID_NOT_SET');
  var root = DriveApp.getFolderById(rootId);
  var it = root.getFoldersByName(tabName);
  return it.hasNext() ? it.next() : root.createFolder(tabName);
}

function monthTabsBetween_(fromYm, toYm) {
  var tabs = [], y = parseInt(fromYm.substring(0, 4), 10), m = parseInt(fromYm.substring(5, 7), 10);
  var endY = parseInt(toYm.substring(0, 4), 10), endM = parseInt(toYm.substring(5, 7), 10);
  while (y < endY || (y === endY && m <= endM)) {
    tabs.push(y + '-' + (m < 10 ? '0' + m : String(m)));
    m++; if (m > 12) { m = 1; y++; }
    if (tabs.length > 24) break;
  }
  return tabs;
}

function normDate_(v) {
  return (v instanceof Date) ? Utilities.formatDate(v, Session.getScriptTimeZone(), 'yyyy-MM-dd') : String(v);
}
function normTime_(v) {
  return (v instanceof Date) ? Utilities.formatDate(v, Session.getScriptTimeZone(), 'HH:mm') : String(v);
}
/** 투입시간·Rework투입시간 정규화 (Sheets가 Date로 저장한 경우 'yyyy-MM-dd HH:mm'로) */
function normIntime_(v) {
  if (v === '' || v === null || v === undefined) return '';
  return (v instanceof Date)
    ? Utilities.formatDate(v, Session.getScriptTimeZone(), 'yyyy-MM-dd HH:mm')
    : String(v);
}
function sanitize_(s) { return String(s).replace(/[^\w\-가-힣]/g, '_'); }

// ---------------------------------------------------------------- setup / migrate (관리용)

function setup() {
  var INITIAL_TOKEN = 'PUT_INITIAL_TOKEN_HERE';
  var props = PropertiesService.getScriptProperties();
  if (!props.getProperty('PHOTO_FOLDER_ID')) {
    var it = DriveApp.getFoldersByName('TRI검사사진');
    props.setProperty('PHOTO_FOLDER_ID', (it.hasNext() ? it.next() : DriveApp.createFolder('TRI검사사진')).getId());
  }
  if (!props.getProperty('APP_TOKEN') && INITIAL_TOKEN.indexOf('PUT_INITIAL') !== 0) {
    props.setProperty('APP_TOKEN', INITIAL_TOKEN);
  }
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  if (!ss.getSheetByName('Masters')) {
    ss.insertSheet('Masters').getRange(1, 1, 7, 2).setValues([
      ['ca', 'CA1'], ['ca', 'CA2'], ['ca', 'CA3'],
      ['inspector', '검사자1'], ['inspector', '검사자2'],
      ['model', 'MODEL-A'], ['model', 'MODEL-B']
    ]);
  }
  ensureProdSheet_();
  Logger.log('SETUP OK folder=' + props.getProperty('PHOTO_FOLDER_ID') + ' tokenSet=' + !!props.getProperty('APP_TOKEN'));
}

/**
 * 스키마 마이그레이션 (관리용): 헤더 불일치 월별 탭 삭제 + Production 시트 보장 +
 * 구 Rework 탭 제거(Production 컬럼으로 흡수). 반복 실행 안전.
 */
function migrateSchema() {
  var ss = SpreadsheetApp.getActiveSpreadsheet(), deleted = [];
  ss.getSheets().forEach(function (sh) {
    var name = sh.getName();
    if (/^\d{4}-\d{2}$/.test(name)) {
      var hdr = sh.getRange(1, 1, 1, INSP_HEADERS.length).getValues()[0];
      if (hdr.join('|') !== INSP_HEADERS.join('|')) { ss.deleteSheet(sh); deleted.push(name); }
    }
  });
  var rw = ss.getSheetByName('Rework');
  if (rw) { ss.deleteSheet(rw); deleted.push('Rework(구)'); }
  ensureProdSheet_();
  Logger.log('MIGRATE deleted: ' + (deleted.join(',') || '(none)') + ' | Production ready');
}

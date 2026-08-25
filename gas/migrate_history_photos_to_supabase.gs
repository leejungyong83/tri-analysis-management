/**
 * 실제 이력 사진 일괄 이전: Google Drive("TRI_사진" 폴더, dlwjddyd83@gmail.com 소유)
 *                        → Supabase Storage(tri-photos 버킷)
 *
 * 폴더 구조 확인됨 (2026-08-25):
 *   TRI_사진/
 *     {LOT}_{yyyymmdd}_{hhmmss}/     예: 20260825001_20260825_081544
 *       photo_1.jpg ~ photo_5.jpg    (Rack1~5)
 *   총 하위폴더 약 5,588개 × 5장 = 약 27,940장
 *
 * ⚠️ 이 스크립트는 "TRI_사진" 폴더를 소유한 Google 계정(dlwjddyd83@gmail.com)으로
 *    로그인한 상태에서 script.google.com 에 새 프로젝트를 만들어 실행해야 합니다.
 *    (기존 저장소용 GAS 프로젝트(zetooo1972@gmail.com)와는 다른 계정입니다.)
 *
 * 업로드 경로 규칙: tri-photos/history/{LOT}/{원본파일명}
 *   예: history/20260825001/photo_1.jpg
 *   → 이 규칙대로 DB 임포트 시 photo1~5 URL을 결정적으로 만들 수 있음.
 *
 * 사용법: migrate_photos_to_supabase.gs 와 동일한 패턴
 *  1) script.google.com → 새 프로젝트 → 이 내용 붙여넣기
 *  2) migrateHistoryPhotos 한 번 수동 실행 (Drive/외부요청 권한 승인)
 *  3) setupHistoryMigrationTrigger 한 번 실행 → 5분마다 자동 이어감
 *  4) checkHistoryMigrationStatus 로 진행 확인
 */

var SUPA_URL_ = 'https://cwzyekmbjcepcpmojwhd.supabase.co';
var SUPA_ANON_KEY_ = 'sb_publishable_iXUe_5PBxxJSq2OVDXhljA_UMTSpApU';
var SUPA_BUCKET_ = 'tri-photos';
var HISTORY_ROOT_FOLDER_ID_ = '1jlF6T82FRmnGegtP0DqK_gZ5jZF4-xXV'; // "TRI_사진"
var TIME_LIMIT_MS_ = 5 * 60 * 1000;

function migrateHistoryPhotos() {
  var props = PropertiesService.getScriptProperties();
  if (props.getProperty('hist_migration_done') === 'true') {
    Logger.log('이미 완료됨. 누적 ' + props.getProperty('hist_migrated_count') + '장');
    deleteHistoryMigrationTrigger_();
    return;
  }

  var start = Date.now();
  var root = DriveApp.getFolderById(HISTORY_ROOT_FOLDER_ID_);

  var token = props.getProperty('hist_cursor');
  var subfolders = token ? DriveApp.continueFolderIterator(token) : root.getFolders();

  var processedCount = Number(props.getProperty('hist_migrated_count') || 0);
  var failCount = Number(props.getProperty('hist_failed_count') || 0);
  var folderCount = Number(props.getProperty('hist_folder_count') || 0);

  while (subfolders.hasNext()) {
    if (Date.now() - start > TIME_LIMIT_MS_) {
      props.setProperty('hist_cursor', subfolders.getContinuationToken());
      props.setProperty('hist_migrated_count', String(processedCount));
      props.setProperty('hist_failed_count', String(failCount));
      props.setProperty('hist_folder_count', String(folderCount));
      Logger.log('시간 상한 — 저장 후 종료. 폴더 ' + folderCount + '개, 사진 성공 ' +
        processedCount + ', 실패 ' + failCount);
      return;
    }

    var subfolder = subfolders.next();
    var folderName = subfolder.getName(); // 예: 20260825001_20260825_081544
    var lot = folderName.split('_')[0];
    folderCount++;

    var files = subfolder.getFiles();
    while (files.hasNext()) {
      var file = files.next();
      var path = 'history/' + lot + '/' + file.getName();
      try {
        var blob = file.getBlob();
        var resp = UrlFetchApp.fetch(
          SUPA_URL_ + '/storage/v1/object/' + SUPA_BUCKET_ + '/' +
            path.split('/').map(encodeURIComponent).join('/'),
          {
            method: 'post',
            contentType: blob.getContentType() || 'image/jpeg',
            payload: blob.getBytes(),
            headers: {
              apikey: SUPA_ANON_KEY_,
              Authorization: 'Bearer ' + SUPA_ANON_KEY_,
              'x-upsert': 'true'
            },
            muteHttpExceptions: true
          }
        );
        if (resp.getResponseCode() < 300) {
          processedCount++;
        } else {
          failCount++;
          Logger.log('업로드 실패(' + resp.getResponseCode() + '): ' + path + ' — ' + resp.getContentText());
        }
      } catch (e) {
        props.setProperty('hist_cursor', subfolders.getContinuationToken());
        props.setProperty('hist_migrated_count', String(processedCount));
        props.setProperty('hist_failed_count', String(failCount));
        props.setProperty('hist_folder_count', String(folderCount));
        Logger.log('예외 발생, 중단 후 저장: ' + e);
        return;
      }
    }
  }

  props.setProperty('hist_migrated_count', String(processedCount));
  props.setProperty('hist_failed_count', String(failCount));
  props.setProperty('hist_folder_count', String(folderCount));
  props.setProperty('hist_migration_done', 'true');
  Logger.log('전체 완료! 폴더 ' + folderCount + '개, 사진 성공 ' + processedCount + '장, 실패 ' + failCount + '장');
  deleteHistoryMigrationTrigger_();
}

function setupHistoryMigrationTrigger() {
  deleteHistoryMigrationTrigger_();
  ScriptApp.newTrigger('migrateHistoryPhotos').timeBased().everyMinutes(5).create();
  Logger.log('트리거 등록 완료 — 5분마다 자동 진행됩니다.');
}

function deleteHistoryMigrationTrigger_() {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'migrateHistoryPhotos') {
      ScriptApp.deleteTrigger(triggers[i]);
    }
  }
}

function checkHistoryMigrationStatus() {
  var props = PropertiesService.getScriptProperties();
  Logger.log(
    '완료여부: ' + (props.getProperty('hist_migration_done') || 'false') +
    ' | 처리한 폴더(LOT) 수: ' + (props.getProperty('hist_folder_count') || 0) +
    ' | 사진 성공: ' + (props.getProperty('hist_migrated_count') || 0) +
    ' | 사진 실패: ' + (props.getProperty('hist_failed_count') || 0)
  );
}

/**
 * 과거 검사 사진 일괄 이전: Google Drive("TRI검사사진" 폴더) → Supabase Storage(tri-photos 버킷)
 *
 * 배경: TRI_이력DB 시트에 사진 27,940장이 Drive 링크로 남아있음. 앱을 여러 번 호출해
 * 한 장씩 내려받는 방식은 비현실적(수일 소요)이라, Apps Script가 같은 Drive 폴더
 * 소유 계정 권한으로 서버 쪽에서 직접 Supabase Storage REST API로 업로드한다.
 *
 * 사용법:
 *  1) 기존 GAS 프로젝트(스프레드시트 바인딩)에 이 파일을 새 스크립트 파일로 추가
 *  2) migratePhotosToSupabase 를 한 번 수동 실행(Drive/외부요청 권한 승인)
 *  3) setupMigrationTrigger 를 한 번 실행 — 5분마다 자동 재실행되어 이어서 진행
 *  4) checkMigrationStatus 로 진행 상황 확인 (실행 로그 또는 Script Properties)
 *
 * 특징:
 *  - 실행시간 상한(6분) 대응: 폴더별 FileIterator continuation token을 Script
 *    Properties에 저장해 다음 실행에서 이어감 (전체 목록을 메모리에 들고 있지 않음)
 *  - 멱등: Supabase 업로드에 x-upsert:true 사용 — 같은 경로 재업로드해도 안전
 *  - 완료 시 migration_done=true 기록 + 자신을 호출하는 트리거 자동 삭제
 */

var SUPA_URL_ = 'https://cwzyekmbjcepcpmojwhd.supabase.co';
var SUPA_ANON_KEY_ = 'sb_publishable_iXUe_5PBxxJSq2OVDXhljA_UMTSpApU';
var SUPA_BUCKET_ = 'tri-photos';
var PHOTO_ROOT_FOLDER_ID_ = '1EkAvJiVO4o70fzKK0TZQoMZzWXqF-z84'; // Drive "TRI검사사진"
var TIME_LIMIT_MS_ = 5 * 60 * 1000; // 6분 실행 상한 대비 5분에서 스스로 중단·저장

function migratePhotosToSupabase() {
  var props = PropertiesService.getScriptProperties();

  if (props.getProperty('migration_done') === 'true') {
    Logger.log('이미 완료됨. 누적 ' + props.getProperty('migrated_count') + '장');
    deleteMigrationTrigger_();
    return;
  }

  var start = Date.now();
  var root = DriveApp.getFolderById(PHOTO_ROOT_FOLDER_ID_);

  var monthNames = JSON.parse(props.getProperty('month_list') || 'null');
  if (!monthNames) {
    monthNames = [];
    var mf = root.getFolders();
    while (mf.hasNext()) monthNames.push(mf.next().getName());
    props.setProperty('month_list', JSON.stringify(monthNames));
    props.setProperty('month_idx', '0');
    Logger.log('대상 월 폴더: ' + monthNames.join(', '));
  }

  var monthIdx = Number(props.getProperty('month_idx') || 0);
  var processedCount = Number(props.getProperty('migrated_count') || 0);
  var failCount = Number(props.getProperty('failed_count') || 0);

  while (monthIdx < monthNames.length) {
    var monthName = monthNames[monthIdx];
    var monthFolders = root.getFoldersByName(monthName);
    if (!monthFolders.hasNext()) { monthIdx++; props.setProperty('month_idx', String(monthIdx)); continue; }
    var monthFolder = monthFolders.next();

    var token = props.getProperty('cursor:' + monthName);
    var files = token ? DriveApp.continueFileIterator(token) : monthFolder.getFiles();

    while (files.hasNext()) {
      if (Date.now() - start > TIME_LIMIT_MS_) {
        props.setProperty('cursor:' + monthName, files.getContinuationToken());
        props.setProperty('migrated_count', String(processedCount));
        props.setProperty('failed_count', String(failCount));
        Logger.log('시간 상한 도달 — 다음 실행에서 이어감. 누적 성공 ' + processedCount + ', 실패 ' + failCount);
        return;
      }

      var file = files.next();
      var path = 'history/' + monthName + '/' + file.getName();
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
        // 할당량 초과 등 예외 — 상태 저장 후 안전 종료 (다음 트리거 실행에서 재시도)
        props.setProperty('cursor:' + monthName, files.getContinuationToken());
        props.setProperty('migrated_count', String(processedCount));
        props.setProperty('failed_count', String(failCount));
        Logger.log('예외 발생, 중단 후 저장: ' + e);
        return;
      }
    }

    // 이 달 폴더 완료 — 다음 달로
    props.deleteProperty('cursor:' + monthName);
    monthIdx++;
    props.setProperty('month_idx', String(monthIdx));
  }

  props.setProperty('migrated_count', String(processedCount));
  props.setProperty('failed_count', String(failCount));
  props.setProperty('migration_done', 'true');
  Logger.log('전체 완료! 성공 ' + processedCount + '장, 실패 ' + failCount + '장');
  deleteMigrationTrigger_();
}

/** 5분마다 자동 재실행 트리거 등록 — 한 번만 실행하면 됨 */
function setupMigrationTrigger() {
  deleteMigrationTrigger_(); // 중복 방지
  ScriptApp.newTrigger('migratePhotosToSupabase').timeBased().everyMinutes(5).create();
  Logger.log('트리거 등록 완료 — 5분마다 자동 진행됩니다.');
}

function deleteMigrationTrigger_() {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    if (triggers[i].getHandlerFunction() === 'migratePhotosToSupabase') {
      ScriptApp.deleteTrigger(triggers[i]);
    }
  }
}

/** 진행 상황 확인 (실행 로그에서 확인) */
function checkMigrationStatus() {
  var props = PropertiesService.getScriptProperties();
  Logger.log(
    '완료여부: ' + (props.getProperty('migration_done') || 'false') +
    ' | 성공: ' + (props.getProperty('migrated_count') || 0) +
    ' | 실패: ' + (props.getProperty('failed_count') || 0) +
    ' | 진행중 월: ' + (JSON.parse(props.getProperty('month_list') || '[]')[Number(props.getProperty('month_idx') || 0)] || '(대기중)')
  );
}

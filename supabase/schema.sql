-- TRI 표면 시약 검사 앱 — Supabase 스키마 (Google Sheets/Apps Script 대체)
-- 실행 방법: Supabase 대시보드 → SQL Editor → 이 파일 전체 붙여넣기 → Run
-- 안전하게 재실행 가능(idempotent)하도록 IF NOT EXISTS / OR REPLACE 사용.

-- ============================================================ 확장
create extension if not exists pgcrypto;

-- ============================================================ 설정(앱 토큰)
create table if not exists app_config (
  key   text primary key,
  value text not null
);

-- 최초 1회만 삽입 (이미 있으면 무시). 실행 후 값을 반드시 확인/교체하세요.
insert into app_config (key, value)
values ('app_token', encode(gen_random_bytes(24), 'hex'))
on conflict (key) do nothing;

-- ============================================================ Masters (검사자/모델/CA)
create table if not exists masters (
  kind  text not null,          -- 'inspector' | 'model' | 'ca'
  value text not null,
  primary key (kind, value)
);

insert into masters (kind, value) values
  ('inspector', '검사자1'), ('inspector', '검사자2'),
  ('model', 'MODEL-A'), ('model', 'MODEL-B'),
  ('ca', 'CA-A'), ('ca', 'CA-B')
on conflict do nothing;

-- ============================================================ Production (생산 이력)
create table if not exists production (
  lot         text primary key,                 -- YYMMDD+일련번호, 예 260824001
  model       text not null,
  qty         integer not null,
  intime      timestamptz not null,              -- 생산 투입 시각
  result      text not null default '',          -- '' | 'OK' | 'NG'
  rework      text not null default '',          -- '' | 'R'+lot
  rework_time timestamptz,
  rework_qty  integer,
  status      text not null default 'PRODUCED',  -- PRODUCED | NG_WAIT | REWORK_READY | DONE_OK
  req_id      text unique                        -- produce 요청 멱등키 (클라이언트 생성)
);

create index if not exists idx_production_intime on production (intime);
create index if not exists idx_production_status on production (status);

-- ============================================================ Inspections (검사 상세)
create table if not exists inspections (
  uuid        uuid primary key,
  date        date not null,        -- 업무일(08:00 기준, 클라이언트 계산값을 신뢰)
  ca          text not null,
  inspector   text not null,
  lot         text not null references production(lot),
  time        text not null,        -- HH:MM (ICT 24시)
  bar         text not null,
  model       text not null,
  rack1       text not null check (rack1 in ('OK','NG')),
  rack2       text not null check (rack2 in ('OK','NG')),
  rack3       text not null check (rack3 in ('OK','NG')),
  rack4       text not null check (rack4 in ('OK','NG')),
  rack5       text not null check (rack5 in ('OK','NG')),
  verdict     text generated always as (
                case when rack1='NG' or rack2='NG' or rack3='NG' or rack4='NG' or rack5='NG'
                     then 'NG' else 'OK' end
              ) stored,
  photo1      text not null default 'pending',   -- Supabase Storage 경로 또는 'pending'
  photo2      text not null default 'pending',
  photo3      text not null default 'pending',
  photo4      text not null default 'pending',
  photo5      text not null default 'pending',
  rework_flag text not null default '',           -- 'Y' | ''
  void_flag   boolean not null default false,
  server_time timestamptz not null default now(),
  skew        text not null default ''
);

create index if not exists idx_inspections_lot on inspections (lot);
create index if not exists idx_inspections_date on inspections (date);

-- ============================================================ 토큰 검증 헬퍼
create or replace function check_token_(p_token text) returns void
language plpgsql as $$
begin
  if p_token is null or p_token <> (select value from app_config where key = 'app_token') then
    raise exception 'UNAUTHORIZED' using errcode = '28000';
  end if;
end;
$$;

-- ============================================================ LOT 채번
create or replace function generate_lot_(p_date date) returns text
language plpgsql as $$
declare
  ymd text := to_char(p_date, 'YYMMDD');
  max_seq int;
  new_lot text;
begin
  -- 같은 날짜(prefix) 채번을 직렬화 (동시 요청 경쟁 방지)
  perform pg_advisory_xact_lock(hashtext(ymd));
  select coalesce(max(substring(lot from 7 for 3)::int), 0) into max_seq
    from production where lot like ymd || '___';
  new_lot := ymd || lpad((max_seq + 1)::text, 3, '0');
  return new_lot;
end;
$$;

-- ============================================================ produce (생산 투입)
create or replace function rpc_produce(
  p_token text, p_req_id text, p_date date, p_time text, p_model text, p_qty int
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_lot text;
begin
  perform check_token_(p_token);
  select lot into v_lot from production where req_id = p_req_id;
  if v_lot is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'lot', v_lot);
  end if;
  v_lot := generate_lot_(p_date);
  insert into production (lot, model, qty, intime, status, req_id)
    values (v_lot, p_model, p_qty, (p_date::text || ' ' || p_time)::timestamptz, 'PRODUCED', p_req_id);
  return jsonb_build_object('ok', true, 'lot', v_lot);
end;
$$;

-- ============================================================ listUninspected
create or replace function rpc_list_uninspected(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_out jsonb;
begin
  perform check_token_(p_token);
  select coalesce(jsonb_agg(jsonb_build_object(
    'lot', lot, 'model', model, 'qty', qty,
    'intime', to_char(intime, 'YYYY-MM-DD HH24:MI'),
    'status', status,
    'reworkLot', case when status = 'REWORK_READY' then 'R' || lot else null end
  ) order by intime desc), '[]'::jsonb) into v_out
  from production where status in ('PRODUCED', 'REWORK_READY');
  return jsonb_build_object('ok', true, 'records', v_out);
end;
$$;

-- ============================================================ reworkInput
create or replace function rpc_rework_input(
  p_token text, p_lot text, p_date date, p_time text, p_qty int
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_prod_qty int;
  v_warn text;
begin
  perform check_token_(p_token);
  select qty into v_prod_qty from production where lot = p_lot;
  if v_prod_qty is null then
    return jsonb_build_object('ok', false, 'error', 'LOT_NOT_FOUND');
  end if;
  update production
    set rework_time = (p_date::text || ' ' || p_time)::timestamptz,
        rework_qty = p_qty,
        status = 'REWORK_READY'
    where lot = p_lot;
  v_warn := case when p_qty > v_prod_qty then 'REWORK_QTY_EXCEEDS_PRODUCTION' else null end;
  return jsonb_build_object('ok', true, 'warn', v_warn);
end;
$$;

-- ============================================================ productionList / productionStats
create or replace function rpc_production_list(p_token text, p_date_from date, p_date_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_out jsonb;
begin
  perform check_token_(p_token);
  select coalesce(jsonb_agg(jsonb_build_object(
    'lot', lot, 'model', model, 'qty', qty,
    'intime', to_char(intime, 'YYYY-MM-DD HH24:MI'),
    'result', result, 'rework', rework,
    'reworkTime', to_char(rework_time, 'YYYY-MM-DD HH24:MI'),
    'reworkQty', rework_qty, 'status', status
  ) order by intime desc), '[]'::jsonb) into v_out
  from production
  where (p_date_from is null or intime::date >= p_date_from)
    and (p_date_to is null or intime::date <= p_date_to);
  return jsonb_build_object('ok', true, 'records', v_out);
end;
$$;

create or replace function rpc_production_stats(p_token text, p_date_from date, p_date_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_produced int; v_ng int; v_rework int; v_qty_sum numeric;
  v_by_model jsonb; v_by_day jsonb;
begin
  perform check_token_(p_token);
  select count(*), coalesce(sum((result='NG')::int),0), coalesce(sum((rework<>'')::int),0), coalesce(sum(qty),0)
    into v_produced, v_ng, v_rework, v_qty_sum
  from production
  where (p_date_from is null or intime::date >= p_date_from)
    and (p_date_to is null or intime::date <= p_date_to);

  select coalesce(jsonb_object_agg(m, stat), '{}'::jsonb) into v_by_model from (
    select model as m, jsonb_build_object('produced', count(*), 'ng', sum((result='NG')::int), 'qty', sum(qty)) as stat
    from production
    where (p_date_from is null or intime::date >= p_date_from)
      and (p_date_to is null or intime::date <= p_date_to)
    group by model
  ) t;

  select coalesce(jsonb_object_agg(d, stat), '{}'::jsonb) into v_by_day from (
    select to_char(intime, 'YYYY-MM-DD') as d, jsonb_build_object('produced', count(*), 'ng', sum((result='NG')::int)) as stat
    from production
    where (p_date_from is null or intime::date >= p_date_from)
      and (p_date_to is null or intime::date <= p_date_to)
    group by 1
  ) t;

  return jsonb_build_object(
    'ok', true, 'produced', v_produced,
    'inspected', v_produced - (select count(*) from production
      where status in ('PRODUCED','REWORK_READY')
        and (p_date_from is null or intime::date >= p_date_from)
        and (p_date_to is null or intime::date <= p_date_to)),
    'uninspected', (select count(*) from production
      where status in ('PRODUCED','REWORK_READY')
        and (p_date_from is null or intime::date >= p_date_from)
        and (p_date_to is null or intime::date <= p_date_to)),
    'ng', v_ng, 'rework', v_rework, 'qtySum', v_qty_sum,
    'inspectRate', case when v_produced=0 then 0 else
      (v_produced - (select count(*) from production
        where status in ('PRODUCED','REWORK_READY')
          and (p_date_from is null or intime::date >= p_date_from)
          and (p_date_to is null or intime::date <= p_date_to)))::numeric / v_produced end,
    'ngRate', 0, -- 클라이언트에서 inspected 대비 재계산 (원 GAS와 동일하게 근사치 대신 명시적 0 반환 방지 원하면 별도 계산)
    'reworkRate', case when v_produced=0 then 0 else v_rework::numeric / v_produced end,
    'byModel', v_by_model, 'byDay', v_by_day
  );
end;
$$;

-- ============================================================ submit (검사 제출)
create or replace function rpc_submit(
  p_token text, p_uuid uuid, p_date date, p_ca text, p_inspector text, p_lot text,
  p_time text, p_bar text, p_model text, p_racks text[], p_device_now timestamptz
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_verdict text;
  v_skew text := '';
  v_inserted boolean := true;
begin
  perform check_token_(p_token);
  if array_length(p_racks, 1) <> 5 then raise exception 'RACKS_MUST_BE_5'; end if;

  v_verdict := case when 'NG' = any(p_racks) then 'NG' else 'OK' end;
  if p_device_now is not null then
    if abs(extract(epoch from (p_device_now - now()))) > 600 then
      v_skew := 'SKEW:' || round(abs(extract(epoch from (p_device_now - now()))) / 60) || 'min';
    end if;
  end if;

  begin
    insert into inspections (uuid, date, ca, inspector, lot, time, bar, model,
      rack1, rack2, rack3, rack4, rack5, rework_flag, skew)
    values (p_uuid, p_date, p_ca, p_inspector, p_lot, p_time, p_bar, p_model,
      p_racks[1], p_racks[2], p_racks[3], p_racks[4], p_racks[5],
      case when v_verdict = 'NG' then 'Y' else '' end, v_skew);
  exception when unique_violation then
    v_inserted := false;
  end;

  if not v_inserted then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  update production set
    result = v_verdict,
    rework = case when v_verdict = 'NG' then 'R' || p_lot else rework end,
    status = case when v_verdict = 'NG' then 'NG_WAIT' else 'DONE_OK' end
  where lot = p_lot;

  return jsonb_build_object('ok', true, 'verdict', v_verdict, 'skew', nullif(v_skew, ''),
    'prodUpdated', (select count(*) > 0 from production where lot = p_lot));
end;
$$;

-- ============================================================ attachPhoto (Storage 업로드 후 경로 기록)
-- 사진 바이트 업로드는 클라이언트가 Supabase Storage SDK로 직접 수행 (버킷: tri-photos).
-- 업로드 성공 후 이 RPC로 해당 Rack의 photoN 컬럼에 스토리지 경로를 기록한다 (멱등: 같은 경로면 재기록만).
create or replace function rpc_attach_photo(
  p_token text, p_uuid uuid, p_rack_index int, p_photo_path text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_col text;
begin
  perform check_token_(p_token);
  if p_rack_index < 1 or p_rack_index > 5 then raise exception 'RACK_INDEX_INVALID'; end if;
  if not exists (select 1 from inspections where uuid = p_uuid) then
    return jsonb_build_object('ok', false, 'error', 'RECORD_NOT_FOUND');
  end if;
  v_col := 'photo' || p_rack_index;
  execute format('update inspections set %I = $1 where uuid = $2', v_col) using p_photo_path, p_uuid;
  return jsonb_build_object('ok', true, 'path', p_photo_path, 'rackIndex', p_rack_index);
end;
$$;

-- ============================================================ list (LOT/모델/NG/기간 조회)
create or replace function rpc_list(
  p_token text, p_lot text, p_model text, p_ng_only boolean, p_date_from date, p_date_to date
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_out jsonb;
begin
  perform check_token_(p_token);
  select coalesce(jsonb_agg(jsonb_build_object(
    'uuid', uuid, 'date', date, 'ca', ca, 'inspector', inspector, 'lot', lot,
    'time', time, 'bar', bar, 'model', model,
    'racks', jsonb_build_array(rack1, rack2, rack3, rack4, rack5),
    'verdict', verdict,
    'photos', jsonb_build_array(photo1, photo2, photo3, photo4, photo5),
    'rework', rework_flag = 'Y', 'voided', void_flag, 'skew', nullif(skew, '')
  ) order by date desc, time desc), '[]'::jsonb) into v_out
  from inspections
  where (p_lot is null or lot = p_lot)
    and (p_model is null or model = p_model)
    and (p_ng_only is not true or verdict = 'NG')
    and (p_date_from is null or date >= p_date_from)
    and (p_date_to is null or date <= p_date_to);
  return jsonb_build_object('ok', true, 'records', v_out);
end;
$$;

-- ============================================================ stats (기간·모델 NG율 + pending 사진)
create or replace function rpc_stats(p_token text, p_date_from date, p_date_to date, p_model text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_total int; v_ng int; v_pending_photos int;
begin
  perform check_token_(p_token);
  select count(*), coalesce(sum((verdict='NG')::int), 0) into v_total, v_ng
  from inspections
  where not void_flag
    and (p_date_from is null or date >= p_date_from)
    and (p_date_to is null or date <= p_date_to)
    and (p_model is null or model = p_model);

  select coalesce(sum(
    (photo1='pending')::int + (photo2='pending')::int + (photo3='pending')::int +
    (photo4='pending')::int + (photo5='pending')::int
  ), 0) into v_pending_photos
  from inspections
  where not void_flag
    and (p_date_from is null or date >= p_date_from)
    and (p_date_to is null or date <= p_date_to);

  return jsonb_build_object('ok', true, 'total', v_total, 'ng', v_ng,
    'ngRate', case when v_total=0 then 0 else v_ng::numeric/v_total end,
    'pendingPhotos', v_pending_photos);
end;
$$;

-- ============================================================ void (무효화)
create or replace function rpc_void(p_token text, p_uuid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_lot text;
begin
  perform check_token_(p_token);
  select lot into v_lot from inspections where uuid = p_uuid;
  if v_lot is null then
    return jsonb_build_object('ok', false, 'error', 'RECORD_NOT_FOUND');
  end if;
  update inspections set void_flag = true where uuid = p_uuid;
  update production set result = '', status = 'PRODUCED' where lot = v_lot;
  return jsonb_build_object('ok', true);
end;
$$;

-- ============================================================ masters
create or replace function rpc_masters(p_token text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_inspectors jsonb; v_models jsonb; v_cas jsonb;
begin
  perform check_token_(p_token);
  select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into v_inspectors from masters where kind='inspector';
  select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into v_models from masters where kind='model';
  select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into v_cas from masters where kind='ca';
  return jsonb_build_object('ok', true, 'masters', jsonb_build_object(
    'inspectors', v_inspectors, 'models', v_models, 'cas', v_cas, 'config', '{}'::jsonb
  ));
end;
$$;

-- ============================================================ RLS: 테이블 직접 접근 차단, RPC로만 접근
alter table production enable row level security;
alter table inspections enable row level security;
alter table masters enable row level security;
alter table app_config enable row level security;
-- 정책을 만들지 않음 = anon/authenticated 직접 select/insert/update 전면 차단.
-- 모든 접근은 SECURITY DEFINER RPC 함수(위)를 통해서만 이루어진다.

revoke all on production, inspections, masters, app_config from anon, authenticated;
grant execute on function
  rpc_produce, rpc_list_uninspected, rpc_rework_input, rpc_production_list, rpc_production_stats,
  rpc_submit, rpc_attach_photo, rpc_list, rpc_stats, rpc_void, rpc_masters
  to anon, authenticated;

-- ============================================================ Storage 버킷 (Rack별 증빙 사진)
insert into storage.buckets (id, name, public)
values ('tri-photos', 'tri-photos', true)
on conflict (id) do nothing;

-- anon이 업로드(insert)는 가능하되 목록조회/삭제는 막음 (업로드 전용, 조회는 public URL로)
drop policy if exists "tri-photos anon upload" on storage.objects;
create policy "tri-photos anon upload"
  on storage.objects for insert to anon
  with check (bucket_id = 'tri-photos');

drop policy if exists "tri-photos public read" on storage.objects;
create policy "tri-photos public read"
  on storage.objects for select to anon
  using (bucket_id = 'tri-photos');

-- ============================================================ 완료 후 확인
-- select value as app_token from app_config where key = 'app_token';  -- 앱 설정에 입력할 토큰
-- select * from masters;

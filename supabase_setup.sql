-- ============================================
-- RED SOLIDARIA VE - SETUP SUPABASE (HARDENED)
-- ============================================

-- 1. Tabla 'reports'
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  lat double precision not null,
  lng double precision not null,
  category text not null check (category in ('energia','senal','suministros','asistencia','peligro','movilidad')),
  report_type text not null default 'offer' check (report_type in ('offer','request')),
  note text,
  client_fp text,                       -- huella anónima (no IP real, solo para rate limit)
  created_at timestamptz not null default now()
);

-- Si ya existía la tabla, agregar columnas nuevas:
alter table public.reports add column if not exists report_type text
  not null default 'offer' check (report_type in ('offer','request'));
alter table public.reports add column if not exists note text;
alter table public.reports add column if not exists client_fp text;
alter table public.reports add column if not exists is_active boolean
  not null default true;

-- Si la tabla ya existía, actualizar el CHECK para aceptar 'movilidad' y 'centro_acopio'
do $$ begin
  alter table public.reports drop constraint if exists reports_category_check;
  alter table public.reports add constraint reports_category_check
    check (category in ('energia','senal','suministros','asistencia','peligro','movilidad','centro_acopio'));
end $$;

-- Columnas para verificación más estricta (centros de acopio + contacto obligatorio)
alter table public.reports add column if not exists phone text;
alter table public.reports add column if not exists reporter_name text;
alter table public.reports add column if not exists exact_address text;

do $$ begin
  -- Teléfono: si está, debe verse como teléfono (cualquier formato razonable; validamos +58 en el cliente)
  if not exists (select 1 from pg_constraint where conname = 'reports_phone_len') then
    alter table public.reports add constraint reports_phone_len
      check (phone is null or length(phone) between 7 and 20);
  end if;
  -- Nombre del reportador: max 80 chars
  if not exists (select 1 from pg_constraint where conname = 'reports_reporter_name_len') then
    alter table public.reports add constraint reports_reporter_name_len
      check (reporter_name is null or length(reporter_name) between 2 and 80);
  end if;
  -- Dirección exacta: max 280 chars
  if not exists (select 1 from pg_constraint where conname = 'reports_exact_address_len') then
    alter table public.reports add constraint reports_exact_address_len
      check (exact_address is null or length(exact_address) between 5 and 280);
  end if;
  -- Si es centro_acopio: requiere contact_phone, reporter_name y exact_address
  alter table public.reports drop constraint if exists reports_centro_acopio_required;
  alter table public.reports add constraint reports_centro_acopio_required
    check (
      category <> 'centro_acopio'
      or (contact_phone is not null and reporter_name is not null and exact_address is not null)
    );
  -- Peligro solo puede ser request (alerta de zona peligrosa, nadie "ofrece" peligro)
  if not exists (select 1 from pg_constraint where conname = 'reports_peligro_only_request') then
    alter table public.reports add constraint reports_peligro_only_request
      check (category <> 'peligro' or report_type = 'request');
  end if;
end $$;

-- 2. CHECK CONSTRAINTS — validan en la base de datos (defensa en profundidad)
--    Cualquiera que intente meter basura por encima del cliente, se rebota acá.
do $$ begin
  -- Coordenadas válidas (Venezuela aprox + margen)
  if not exists (select 1 from pg_constraint where conname = 'reports_lat_range') then
    alter table public.reports add constraint reports_lat_range
      check (lat between -1 and 17);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'reports_lng_range') then
    alter table public.reports add constraint reports_lng_range
      check (lng between -75 and -58);
  end if;
  -- Nota no puede tener más de 280 chars
  if not exists (select 1 from pg_constraint where conname = 'reports_note_len') then
    alter table public.reports add constraint reports_note_len
      check (note is null or length(note) <= 280);
  end if;
  -- client_fp solo formato simple (alfanumérico, hasta 64 chars)
  if not exists (select 1 from pg_constraint where conname = 'reports_fp_fmt') then
    alter table public.reports add constraint reports_fp_fmt
      check (client_fp is null or client_fp ~ '^[a-zA-Z0-9_-]{1,64}$');
  end if;
end $$;

-- 3. Índices — optimizados para la consulta del mapa (is_active + created_at)
create index if not exists reports_created_at_idx on public.reports (created_at desc);
create index if not exists reports_fp_recent_idx  on public.reports (client_fp, created_at desc);
-- Índice parcial: el mapa SOLO trae activos. Reduce escaneo masivo.
create index if not exists reports_active_recent_idx
  on public.reports (created_at desc)
  where is_active = true;

-- 4. RATE LIMIT — máximo 5 reportes por minuto por huella, 30 por hora.
--    Bloquea spam sin afectar usuarios legítimos.
create or replace function public.reports_rate_limit() returns trigger
language plpgsql security definer as $$
declare
  cnt_min int;
  cnt_hr  int;
begin
  if new.client_fp is null then return new; end if;

  select count(*) into cnt_min
  from public.reports
  where client_fp = new.client_fp
    and created_at > now() - interval '1 minute';

  if cnt_min >= 5 then
    raise exception 'rate_limit: máximo 5 reportes por minuto'
      using errcode = 'P0001';
  end if;

  select count(*) into cnt_hr
  from public.reports
  where client_fp = new.client_fp
    and created_at > now() - interval '1 hour';

  if cnt_hr >= 30 then
    raise exception 'rate_limit: máximo 30 reportes por hora'
      using errcode = 'P0001';
  end if;

  return new;
end $$;

drop trigger if exists trg_reports_rate_limit on public.reports;
create trigger trg_reports_rate_limit
  before insert on public.reports
  for each row execute function public.reports_rate_limit();

-- 5. RLS — Row Level Security
alter table public.reports enable row level security;

-- Limpiar políticas anteriores
drop policy if exists "anon_read_reports"   on public.reports;
drop policy if exists "anon_insert_reports" on public.reports;
drop policy if exists "anon_read_recent"    on public.reports;
drop policy if exists "anon_read_active"    on public.reports;
drop policy if exists "anon_insert_valid"   on public.reports;

-- LECTURA: solo activos + últimos 2 días (alineado con el query del cliente)
-- Esto BLOQUEA por completo descargar la tabla entera, incluso si el cliente
-- intenta hacer un select sin filtros desde DevTools.
create policy "anon_read_active"
  on public.reports
  for select
  to anon
  using (
    is_active = true
    and created_at > now() - interval '2 days'
  );

-- INSERT: validaciones extra en la policy (defensa en profundidad sobre los CHECK)
create policy "anon_insert_valid"
  on public.reports
  for insert
  to anon
  with check (
    category in ('energia','senal','suministros','asistencia','peligro','movilidad','centro_acopio')
    and report_type in ('offer','request')
    and (category <> 'peligro' or report_type = 'request')          -- peligro solo es request
    and (category <> 'centro_acopio' or report_type = 'offer')      -- centros solo es offer
    and lat between -1 and 17
    and lng between -75 and -58
    and (note is null or length(note) <= 280)
    and (contact_phone is null or length(contact_phone) between 7 and 25)
    and (reporter_name is null or length(reporter_name) between 2 and 80)
    and (exact_address is null or length(exact_address) between 5 and 280)
  );

-- NUNCA crear políticas de UPDATE ni DELETE para 'anon'.
-- Sin política = bloqueado por defecto bajo RLS.

-- 6. CONFIRMACIONES / VALIDACIÓN POR COMUNIDAD
--    Cada huella anónima puede confirmar un reporte UNA sola vez.
alter table public.reports add column if not exists confirmations integer not null default 0;

create table if not exists public.report_confirmations (
  report_id uuid not null references public.reports(id) on delete cascade,
  client_fp text not null,
  created_at timestamptz not null default now(),
  primary key (report_id, client_fp)
);

alter table public.report_confirmations enable row level security;

drop policy if exists "anon_confirm_insert" on public.report_confirmations;
create policy "anon_confirm_insert"
  on public.report_confirmations
  for insert
  to anon
  with check (
    client_fp ~ '^[a-zA-Z0-9_-]{1,64}$'
  );

-- RPC: confirmar reporte (incrementa contador SOLO la primera vez por huella)
create or replace function public.confirm_report(p_report uuid, p_fp text)
returns integer
language plpgsql security definer as $$
declare
  inserted boolean;
  new_count int;
begin
  if p_fp !~ '^[a-zA-Z0-9_-]{1,64}$' then
    raise exception 'fp inválido';
  end if;

  insert into public.report_confirmations (report_id, client_fp)
  values (p_report, p_fp)
  on conflict do nothing;

  get diagnostics inserted = row_count;

  if inserted then
    update public.reports
       set confirmations = confirmations + 1
     where id = p_report
       and is_active = true
       and created_at > now() - interval '7 days'
    returning confirmations into new_count;
  else
    select confirmations into new_count from public.reports where id = p_report;
  end if;

  return coalesce(new_count, 0);
end $$;

grant execute on function public.confirm_report(uuid, text) to anon;

-- ============================================
-- 6b. ATENDIDA / FULFILLED — requiere 2 confirmaciones distintas
-- ============================================
alter table public.reports add column if not exists fulfilled_at timestamptz;
alter table public.reports add column if not exists fulfilled_note text;
alter table public.reports add column if not exists fulfill_count integer not null default 0;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'reports_fulfilled_note_len') then
    alter table public.reports add constraint reports_fulfilled_note_len
      check (fulfilled_note is null or length(fulfilled_note) <= 1000);
  end if;
end $$;

-- Tabla de votos individuales (1 por huella por reporte)
create table if not exists public.report_fulfillments (
  report_id uuid not null references public.reports(id) on delete cascade,
  client_fp text not null,
  note text,
  created_at timestamptz not null default now(),
  primary key (report_id, client_fp)
);

alter table public.report_fulfillments enable row level security;
drop policy if exists "anon_fulfill_insert" on public.report_fulfillments;
create policy "anon_fulfill_insert"
  on public.report_fulfillments
  for insert
  to anon
  with check (
    client_fp ~ '^[a-zA-Z0-9_-]{1,64}$'
    and (note is null or length(note) <= 280)
  );

create index if not exists report_fulfillments_report_idx
  on public.report_fulfillments (report_id);

-- Limpia versión anterior si existía con otra firma
drop function if exists public.fulfill_report(uuid, text, text);

-- RPC nueva — requiere 2 votos distintos para marcar como atendida
create or replace function public.fulfill_report(p_report uuid, p_fp text, p_note text default null)
returns jsonb
language plpgsql security definer as $$
declare
  threshold int := 2;
  inserted boolean;
  new_count int;
  finalized timestamptz;
  is_request boolean;
begin
  if p_fp !~ '^[a-zA-Z0-9_-]{1,64}$' then
    raise exception 'fp inválido';
  end if;
  if p_note is not null and length(p_note) > 280 then
    raise exception 'nota muy larga';
  end if;

  -- Validar que sea una solicitud y que no esté ya marcada como atendida
  select (report_type = 'request' and fulfilled_at is null)
    into is_request
    from public.reports
   where id = p_report;
  if is_request is null then
    raise exception 'reporte no existe';
  end if;
  if not is_request then
    raise exception 'ya atendida o no es solicitud';
  end if;

  -- Registrar voto (UNIQUE bloquea doble voto del mismo fp)
  insert into public.report_fulfillments (report_id, client_fp, note)
  values (p_report, p_fp, nullif(trim(p_note), ''))
  on conflict do nothing;

  get diagnostics inserted = row_count;

  if inserted then
    update public.reports
       set fulfill_count = fulfill_count + 1
     where id = p_report
    returning fulfill_count into new_count;
  else
    select fulfill_count into new_count from public.reports where id = p_report;
  end if;

  -- Si alcanzó el threshold y no está marcada aún, finalizar
  if new_count >= threshold then
    update public.reports
       set fulfilled_at  = now(),
           is_active     = false,
           fulfilled_note = (
             select string_agg(note, ' · ' order by created_at)
             from public.report_fulfillments
             where report_id = p_report and note is not null
           )
     where id = p_report
       and fulfilled_at is null
    returning fulfilled_at into finalized;
  end if;

  return jsonb_build_object(
    'count', coalesce(new_count, 0),
    'threshold', threshold,
    'already_voted', not inserted,
    'fulfilled', finalized is not null
  );
end $$;

grant execute on function public.fulfill_report(uuid, text, text) to anon;

-- ============================================
-- 7. EXTERNAL DATA SYNC — columns for CaracasAyuda integration
-- ============================================

-- contact_phone: required for all citizen reports (+58 format, validated client-side)
alter table public.reports add column if not exists contact_phone text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'reports_phone_len') then
    alter table public.reports add constraint reports_contact_phone_len
      check (contact_phone is null or length(contact_phone) between 7 and 25);
  end if;
end $$;

-- source: 'user' for citizen reports, 'ca' for CaracasAyuda-synced points
alter table public.reports add column if not exists source text default 'user';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'reports_source_check') then
    alter table public.reports add constraint reports_source_check
      check (source in ('user', 'ca'));
  end if;
end $$;

-- external_id + external_source: used to deduplicate synced points on upsert
alter table public.reports add column if not exists external_id text;
alter table public.reports add column if not exists external_source text;

-- REQUIRED: unique index to enable ON CONFLICT upserts from external sync
-- IMPORTANT: must NOT have a WHERE clause — PostgREST requires a non-partial index
-- NULL values are always distinct in PostgreSQL unique indexes, so user rows (both NULL) never conflict
drop index if exists public.reports_external_idx;
create unique index if not exists reports_external_idx
  on public.reports(external_source, external_id);

-- UPDATE policy for external sync rows (needed for upsert ON CONFLICT updates)
drop policy if exists "anon_update_external" on public.reports;
create policy "anon_update_external"
  on public.reports
  for update
  to anon
  using (source = 'ca' and external_source is not null)
  with check (source = 'ca' and external_source is not null);

-- SELECT policy: TTL diferenciado por tipo
--   solicitudes (request): 24h
--   ofrecimientos (offer): 72h
--   puntos externos CA: sin límite de tiempo
drop policy if exists "anon_read_active" on public.reports;
create policy "anon_read_active"
  on public.reports
  for select
  to anon
  using (
    is_active = true
    and (
      source = 'ca'
      or (report_type = 'offer'   and created_at > now() - interval '72 hours')
      or (report_type = 'request' and created_at > now() - interval '24 hours')
    )
  );

-- ============================================
-- 8. TABLA centros — centros de acopio de Google Sheets + CaracasAyuda
-- ============================================

create table if not exists public.centros (
  id           uuid primary key default gen_random_uuid(),
  org          text,
  addr         text,
  lat          double precision not null,
  lng          double precision not null,
  ciudad       text,
  acepta       text,
  contacto     text,
  source       text not null default 'sheets',   -- 'sheets' | 'ca'
  external_key text,
  updated_at   timestamptz not null default now()
);

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'centros_lat_range') then
    alter table public.centros add constraint centros_lat_range check (lat between -1 and 17);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'centros_lng_range') then
    alter table public.centros add constraint centros_lng_range check (lng between -75 and -58);
  end if;
end $$;

create unique index if not exists centros_external_key_idx
  on public.centros(source, external_key)
  where external_key is not null;

create index if not exists centros_latlng_idx on public.centros (lat, lng);

alter table public.centros enable row level security;

drop policy if exists "anon_read_centros"   on public.centros;
drop policy if exists "anon_insert_centros" on public.centros;
drop policy if exists "anon_update_centros" on public.centros;

create policy "anon_read_centros"
  on public.centros for select to anon using (true);

create policy "anon_insert_centros"
  on public.centros for insert to anon
  with check (source in ('sheets', 'ca') and lat between -1 and 17 and lng between -75 and -58);

create policy "anon_update_centros"
  on public.centros for update to anon
  using (source in ('sheets', 'ca'))
  with check (source in ('sheets', 'ca'));

-- Fix: habilitar RLS en la tabla centros (si se creó sin él)
alter table public.centros enable row level security;

-- 9. Limpieza automática con TTLs diferenciados:
--    - Solicitudes (request): se borran a las 24h
--    - Ofrecimientos (offer): se borran a las 72h
--    Requiere extensión pg_cron (Database -> Extensions -> activar pg_cron).
--    Descomenta si la tienes activa:
-- select cron.schedule('purge-requests', '0 * * * *',
--   $$ delete from public.reports
--      where report_type = 'request'
--        and source = 'user'
--        and created_at < now() - interval '24 hours' $$);
-- select cron.schedule('purge-offers', '0 */6 * * *',
--   $$ delete from public.reports
--      where report_type = 'offer'
--        and source = 'user'
--        and created_at < now() - interval '72 hours' $$);

-- ============================================
-- CHECKLIST DE SEGURIDAD POST-INSTALACIÓN:
-- 1. Settings -> API: verifica que SOLO uses la 'anon' key en el HTML.
--    La 'service_role' NUNCA debe ir al cliente.
-- 2. Settings -> API -> "JWT Settings": NO cambies el secret.
-- 3. Settings -> Authentication -> URL Config: agrega solo tu dominio real
--    (ej: https://red-solidaria-ve.netlify.app) en "Site URL".
-- 4. Database -> Extensions: si no usas pg_cron, déjalo apagado.
-- 5. Si el tráfico crece, considera mover INSERT a una Edge Function
--    para usar service_role del lado servidor y agregar CAPTCHA.
-- ============================================

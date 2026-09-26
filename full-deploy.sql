-- =========================================================
-- FULL DEPLOY — Emergency Room Parking (SecurityFixV2 consolidated)
-- Run ONCE in Supabase SQL Editor (single paste). Idempotent: safe to re-run.
-- Order baked in: schema > auto_verify > permanent_specialty > security_fixes_v2
-- NOTE: setup_sub_admins.sql is NOT included (needs your real Auth UIDs).
-- Run it separately AFTER creating Auth users (fill placeholders locally only).
-- Scale indexed for 300-400 employees (see SCALE section at end).
-- =========================================================


-- #########################################################
-- SOURCE FILE: schema.sql
-- #########################################################
-- =========================================================
-- Employee Private Parking Access System
-- Supabase schema.sql
-- Version: 1.0
--
-- هدف الملف:
-- يجهّز قاعدة البيانات كاملة لتطبيق كراج الموظفين:
-- - تسجيل الموظفين
-- - دخول أول مرة بعد التسجيل بشرط QR صالح
-- - شاشة الحارس realtime
-- - مسموح / مرفوض / مسموح جزئيًا
-- - حدود يومية حسب الاختصاص
-- - بلاغات الحارس بالصور
-- - أدمن / سوبر أدمن / مشرفين
-- - سجلات تدقيق Audit
--
-- مهم:
-- 1) شغّلي هذا الملف في Supabase SQL Editor.
-- 2) بعدها أنشئي مستخدمك من Authentication → Users.
-- 3) ثم شغّلي كود SUPER ADMIN الموجود في آخر الملف بعد تبديل القيم.
-- =========================================================

create extension if not exists "pgcrypto";

-- =========================================================
-- ADMIN PROFILES
-- =========================================================

create table if not exists public.admin_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique not null,
  email text unique not null,
  full_name text,
  role text not null check (role in ('SUPER_ADMIN', 'SUB_ADMIN')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.admin_profiles enable row level security;

-- =========================================================
-- EMPLOYEE REGISTRATIONS
-- =========================================================

create table if not exists public.employee_registrations (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  employee_id text not null unique,
  mobile_number text not null,
  specialty text not null,
  status text not null default 'PENDING' check (status in ('PENDING', 'APPROVED', 'REJECTED')),
  first_entry_used boolean not null default false,
  first_entry_at timestamptz,
  approved_at timestamptz,
  approved_by uuid,
  rejected_at timestamptz,
  rejected_by uuid,
  created_at timestamptz not null default now()
);

alter table public.employee_registrations enable row level security;

create index if not exists idx_employee_registrations_status
on public.employee_registrations(status);

create index if not exists idx_employee_registrations_employee_id
on public.employee_registrations(employee_id);

create index if not exists idx_employee_registrations_specialty
on public.employee_registrations(specialty);

-- =========================================================
-- SPECIALTY DAILY LIMITS
-- =========================================================

create table if not exists public.specialty_daily_limits (
  id uuid primary key default gen_random_uuid(),
  specialty_name text not null unique,
  daily_limit integer not null default 0 check (daily_limit >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.specialty_daily_limits enable row level security;

-- =========================================================
-- GATE ACCESS LOGS
-- =========================================================

create table if not exists public.gate_access_logs (
  id uuid primary key default gen_random_uuid(),
  employee_registration_id uuid references public.employee_registrations(id) on delete set null,
  employee_id text,
  mobile_number text,
  full_name text,
  specialty text,
  result text not null check (result in ('ALLOWED', 'DENIED', 'LIMITED', 'PENDING_FIRST_ENTRY')),
  reason text,
  qr_token uuid,
  created_at timestamptz not null default now()
);

alter table public.gate_access_logs enable row level security;

create index if not exists idx_gate_access_logs_created_at
on public.gate_access_logs(created_at);

create index if not exists idx_gate_access_logs_result
on public.gate_access_logs(result);

create index if not exists idx_gate_access_logs_specialty
on public.gate_access_logs(specialty);

-- =========================================================
-- GUARD SCREEN STATUS
-- one row only: id = 1
-- =========================================================

create table if not exists public.guard_screen_status (
  id integer primary key default 1 check (id = 1),
  current_status text not null default 'READY' check (current_status in ('READY', 'ALLOWED', 'DENIED', 'LIMITED')),
  employee_name text,
  employee_id text,
  message text,
  updated_at timestamptz not null default now()
);

alter table public.guard_screen_status enable row level security;

insert into public.guard_screen_status (id, current_status, message)
values (1, 'READY', 'QR جاهز للمسح')
on conflict (id) do nothing;

-- =========================================================
-- QR SESSIONS
-- كل QR له token ينتهي خلال 30 ثانية أو بعد أول استخدام.
-- =========================================================

create table if not exists public.qr_sessions (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.qr_sessions enable row level security;

create index if not exists idx_qr_sessions_token
on public.qr_sessions(token);

create index if not exists idx_qr_sessions_expires_at
on public.qr_sessions(expires_at);

-- =========================================================
-- VIOLATION REPORTS
-- صور مخالفات الحارس تحفظ في Supabase Storage.
-- الجدول يحفظ رابط الصورة.
-- =========================================================

create table if not exists public.violation_reports (
  id uuid primary key default gen_random_uuid(),
  employee_id text,
  note text,
  photo_url text not null,
  status text not null default 'NEW' check (status in ('NEW', 'REVIEWED', 'RESOLVED')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid
);

alter table public.violation_reports enable row level security;

create index if not exists idx_violation_reports_status
on public.violation_reports(status);

create index if not exists idx_violation_reports_created_at
on public.violation_reports(created_at);

-- =========================================================
-- ADMIN AUDIT LOGS
-- =========================================================

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_auth_user_id uuid,
  action text not null,
  target_table text,
  target_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_audit_logs enable row level security;

create index if not exists idx_admin_audit_logs_created_at
on public.admin_audit_logs(created_at);

-- =========================================================
-- STORAGE BUCKET
-- =========================================================

insert into storage.buckets (id, name, public)
values ('violation-photos', 'violation-photos', true)
on conflict (id) do nothing;

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

create or replace function public.current_admin_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_admin_role() in ('SUPER_ADMIN', 'SUB_ADMIN'), false);
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_admin_role() = 'SUPER_ADMIN', false);
$$;

-- =========================================================
-- RLS POLICIES
-- =========================================================

-- admin_profiles
drop policy if exists "Admins can read admin profiles" on public.admin_profiles;
create policy "Admins can read admin profiles"
on public.admin_profiles
for select
to authenticated
using (public.is_admin());

drop policy if exists "Super admin can manage admin profiles" on public.admin_profiles;
create policy "Super admin can manage admin profiles"
on public.admin_profiles
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

-- employee_registrations
drop policy if exists "Admins can read registrations" on public.employee_registrations;
create policy "Admins can read registrations"
on public.employee_registrations
for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can update registrations" on public.employee_registrations;
create policy "Admins can update registrations"
on public.employee_registrations
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- specialty_daily_limits
drop policy if exists "Admins can read specialty limits" on public.specialty_daily_limits;
create policy "Admins can read specialty limits"
on public.specialty_daily_limits
for select
to authenticated
using (public.is_admin());

drop policy if exists "Super admin can manage specialty limits" on public.specialty_daily_limits;
create policy "Super admin can manage specialty limits"
on public.specialty_daily_limits
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

-- gate_access_logs
drop policy if exists "Admins can read access logs" on public.gate_access_logs;
create policy "Admins can read access logs"
on public.gate_access_logs
for select
to authenticated
using (public.is_admin());

-- guard_screen_status
drop policy if exists "Anyone can read guard screen status" on public.guard_screen_status;
create policy "Anyone can read guard screen status"
on public.guard_screen_status
for select
to anon, authenticated
using (true);

-- violation_reports
drop policy if exists "Admins can read violation reports" on public.violation_reports;
create policy "Admins can read violation reports"
on public.violation_reports
for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can update violation reports" on public.violation_reports;
create policy "Admins can update violation reports"
on public.violation_reports
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- admin_audit_logs
drop policy if exists "Admins can read audit logs" on public.admin_audit_logs;
create policy "Admins can read audit logs"
on public.admin_audit_logs
for select
to authenticated
using (public.is_admin());

-- Storage policies
drop policy if exists "Anyone can upload violation photos" on storage.objects;
create policy "Anyone can upload violation photos"
on storage.objects
for insert
to anon, authenticated
with check (bucket_id = 'violation-photos');

drop policy if exists "Anyone can read violation photos" on storage.objects;
create policy "Anyone can read violation photos"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'violation-photos');

-- =========================================================
-- RPC: get_my_admin_profile
-- =========================================================

create or replace function public.get_my_admin_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select *
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.id is null then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالدخول');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', prof.id,
    'email', prof.email,
    'full_name', prof.full_name,
    'role', prof.role
  );
end;
$$;

-- =========================================================
-- RPC: create_qr_session
-- =========================================================

create or replace function public.create_qr_session()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_token uuid;
begin
  delete from public.qr_sessions
  where expires_at < now() - interval '5 minutes';

  insert into public.qr_sessions (expires_at)
  values (now() + interval '30 seconds')
  returning token into new_token;

  return jsonb_build_object(
    'ok', true,
    'token', new_token::text,
    'expires_in_seconds', 30
  );
end;
$$;

-- =========================================================
-- RPC HELPER: validate_and_use_qr_token
-- =========================================================

create or replace function public.validate_and_use_qr_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  token_uuid uuid;
  found_id uuid;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return false;
  end if;

  begin
    token_uuid := p_token::uuid;
  exception when others then
    return false;
  end;

  select id
  into found_id
  from public.qr_sessions
  where token = token_uuid
    and used_at is null
    and expires_at > now()
  limit 1;

  if found_id is null then
    return false;
  end if;

  update public.qr_sessions
  set used_at = now()
  where id = found_id;

  return true;
end;
$$;

-- =========================================================
-- RPC HELPER: set_guard_status
-- =========================================================

create or replace function public.set_guard_status(
  p_status text,
  p_employee_name text,
  p_employee_id text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.guard_screen_status
  set current_status = p_status,
      employee_name = p_employee_name,
      employee_id = p_employee_id,
      message = p_message,
      updated_at = now()
  where id = 1;
end;
$$;

-- =========================================================
-- RPC: reset_guard_screen
-- =========================================================

create or replace function public.reset_guard_screen()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.guard_screen_status
  set current_status = 'READY',
      employee_name = null,
      employee_id = null,
      message = 'QR جاهز للمسح',
      updated_at = now()
  where id = 1;

  return jsonb_build_object('ok', true);
end;
$$;

-- =========================================================
-- RPC: register_employee_request
-- الموظف الجديد يحصل على دخول أول مرة فقط إذا:
-- - أدخل الاسم + رقم الموظف + الهاتف + الاختصاص
-- - فتح من QR صالح وغير مستخدم
-- =========================================================

create or replace function public.register_employee_request(
  p_full_name text,
  p_employee_id text,
  p_mobile_number text,
  p_specialty text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  qr_ok boolean := false;
  clean_name text := trim(p_full_name);
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
  clean_specialty text := trim(p_specialty);
begin
  if clean_name = '' or clean_emp = '' or clean_mobile = '' or clean_specialty = '' then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'message', 'الرجاء تعبئة الاسم ورقم الموظف ورقم الهاتف والقسم'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
  limit 1;

  if reg.id is null then
    insert into public.employee_registrations (
      full_name,
      employee_id,
      mobile_number,
      specialty,
      status,
      first_entry_used,
      first_entry_at
    )
    values (
      clean_name,
      clean_emp,
      clean_mobile,
      clean_specialty,
      'PENDING',
      false,
      null
    )
    returning * into reg;
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'REJECTED_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب مسبقًا');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة'
    );
  end if;

  if reg.status = 'APPROVED' then
    return public.manual_employee_check(reg.employee_id, reg.mobile_number, p_qr_token);
  end if;

  if reg.first_entry_used = true then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'PENDING_FIRST_ENTRY_ALREADY_USED'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة — تم استخدام الدخول الأول سابقًا');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'طلبك قيد المراجعة، وتم استخدام الدخول الأول سابقًا'
    );
  end if;

  -- التحقق من QR هنا فقط بعد التأكد أن الطلب PENDING ولم يستخدم الدخول الأول.
  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok then
    update public.employee_registrations
    set first_entry_used = true,
        first_entry_at = now()
    where id = reg.id
    returning * into reg;

    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'PENDING_FIRST_ENTRY',
      'FIRST_ENTRY_AFTER_REGISTRATION',
      p_qr_token::uuid
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'دخول أول مرة — بانتظار موافقة الإدارة');

    return jsonb_build_object(
      'ok', true,
      'result', 'LIMITED',
      'message', 'تم إرسال طلبك. تم السماح بدخول أول مرة فقط، والطلب بانتظار موافقة الإدارة'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'result', 'PENDING',
    'message', 'تم إرسال طلبك، الرجاء انتظار موافقة الإدارة'
  );
end;
$$;

-- =========================================================
-- HELPER: permanently allowed specialties
-- خيار الإسعاف والطوارئ DRS/NRS/EMT/MLT مسموح دائمًا ولا يُحسب ضمن الحدود اليومية
-- =========================================================

create or replace function public.normalize_specialty_name(p_specialty text)
returns text
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := upper(trim(coalesce(p_specialty, '')));

  v := replace(v, 'أ', 'ا');
  v := replace(v, 'إ', 'ا');
  v := replace(v, 'آ', 'ا');
  v := replace(v, 'ٱ', 'ا');
  v := replace(v, 'ة', 'ه');

  v := regexp_replace(v, '\s+', '', 'g');
  v := replace(v, '،', ',');
  v := replace(v, '／', '/');
  v := replace(v, '(', '');
  v := replace(v, ')', '');
  v := replace(v, '-', '');

  return v;
end;
$$;

create or replace function public.is_permanently_allowed_specialty(p_specialty text)
returns boolean
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := public.normalize_specialty_name(p_specialty);

  return v in (
    public.normalize_specialty_name('الإسعاف والطوارئ (DRS/NRS/EMT/MLT)'),
    public.normalize_specialty_name('الإسعاف والطوارئ - DRS/NRS/EMT/MLT'),
    public.normalize_specialty_name('الإسعاف والطوارئ DRS,NRS,EMT/MLT'),
    public.normalize_specialty_name('DRS,NRS,EMT/MLT'),
    public.normalize_specialty_name('DRS/NRS/EMT/MLT'),
    public.normalize_specialty_name('الإسعاف والطوارئ')
  );
end;
$$;

-- =========================================================
-- RPC: manual_employee_check
-- الفحص اليدوي عند تعطل QR.
-- يتحقق من employee_id + mobile_number معًا.
-- =========================================================

create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  lim record;
  used_count integer := 0;
  qr_required boolean := false;
  qr_ok boolean := true;
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل رقم الموظف ورقم الهاتف');
  end if;

  if p_qr_token is not null and length(trim(p_qr_token)) > 0 then
    qr_required := true;
    qr_ok := public.validate_and_use_qr_token(p_qr_token);
  end if;

  if qr_required and qr_ok = false then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object(
      'ok', true,
      'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا'
    );
  end if;

  if reg.status = 'PENDING' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'PENDING_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة');

    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة');
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'REJECTED_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة'
    );
  end if;

  -- Permanently allowed specialty group:
  -- الإسعاف والطوارئ (DRS/NRS/EMT/MLT)
  -- هذا الاختصاص لا يدخل في specialty_daily_limits ولا يتحول إلى LIMITED.
  if public.is_permanently_allowed_specialty(reg.specialty) then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'ALLOWED',
      'PERMANENTLY_ALLOWED_SPECIALTY',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
    );

    perform public.set_guard_status(
      'ALLOWED',
      reg.full_name,
      reg.employee_id,
      'مسموح بالدخول — اختصاص مسموح دائمًا'
    );

    return jsonb_build_object(
      'ok', true,
      'result', 'ALLOWED',
      'message', 'مسموح بالدخول — اختصاص مسموح دائمًا'
    );
  end if;

  -- APPROVED employee: check specialty limit.
  select *
  into lim
  from public.specialty_daily_limits
  where specialty_name = reg.specialty
    and is_active = true
  limit 1;

  if lim.id is not null then
    select count(*)
    into used_count
    from public.gate_access_logs
    where specialty = reg.specialty
      and result = 'LIMITED'
      and created_at >= date_trunc('day', now())
      and created_at < date_trunc('day', now()) + interval '1 day';

    if used_count >= lim.daily_limit then
      insert into public.gate_access_logs (
        employee_registration_id,
        employee_id,
        mobile_number,
        full_name,
        specialty,
        result,
        reason
      )
      values (
        reg.id,
        reg.employee_id,
        reg.mobile_number,
        reg.full_name,
        reg.specialty,
        'DENIED',
        'SPECIALTY_DAILY_LIMIT_REACHED'
      );

      perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم الوصول للحد اليومي لهذا الاختصاص');

      return jsonb_build_object(
        'ok', true,
        'result', 'DENIED',
        'message', 'غير مسموح — تم الوصول للحد اليومي لهذا الاختصاص'
      );
    end if;

    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'LIMITED',
      'SPECIALTY_LIMITED_ACCESS',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'مسموح جزئيًا حسب الاختصاص');

    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'مسموح جزئيًا حسب الاختصاص');
  end if;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  )
  values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    'ALLOWED',
    'APPROVED_EMPLOYEE',
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول');

  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول');
end;
$$;

-- =========================================================
-- RPC: submit_violation_report
-- =========================================================

create or replace function public.submit_violation_report(
  p_employee_id text,
  p_note text,
  p_photo_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if p_photo_url is null or trim(p_photo_url) = '' then
    return jsonb_build_object('ok', false, 'message', 'الصورة مطلوبة');
  end if;

  insert into public.violation_reports (employee_id, note, photo_url)
  values (nullif(trim(p_employee_id), ''), nullif(trim(p_note), ''), trim(p_photo_url))
  returning id into new_id;

  return jsonb_build_object('ok', true, 'id', new_id, 'message', 'تم إرسال المخالفة إلى الإدارة');
end;
$$;

-- =========================================================
-- ADMIN RPC: update registration status
-- =========================================================

create or replace function public.admin_update_registration_status(
  p_registration_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;

  if p_status not in ('APPROVED', 'REJECTED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.employee_registrations
  set status = p_status,
      approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
      approved_by = case when p_status = 'APPROVED' then auth.uid() else approved_by end,
      rejected_at = case when p_status = 'REJECTED' then now() else rejected_at end,
      rejected_by = case when p_status = 'REJECTED' then auth.uid() else rejected_by end
  where id = p_registration_id
  returning * into reg;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_REGISTRATION_STATUS',
    'employee_registrations',
    p_registration_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث الطلب');
end;
$$;

-- =========================================================
-- ADMIN RPC: save specialty limit
-- =========================================================

create or replace function public.admin_upsert_specialty_limit(
  p_specialty_name text,
  p_daily_limit integer,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if trim(p_specialty_name) = '' then
    return jsonb_build_object('ok', false, 'message', 'اسم الاختصاص مطلوب');
  end if;

  insert into public.specialty_daily_limits (
    specialty_name,
    daily_limit,
    is_active,
    updated_at
  )
  values (
    trim(p_specialty_name),
    greatest(p_daily_limit, 0),
    p_is_active,
    now()
  )
  on conflict (specialty_name)
  do update set daily_limit = excluded.daily_limit,
                is_active = excluded.is_active,
                updated_at = now();

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_SPECIALTY_LIMIT',
    'specialty_daily_limits',
    jsonb_build_object(
      'specialty',
      p_specialty_name,
      'daily_limit',
      p_daily_limit,
      'is_active',
      p_is_active
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ حد الاختصاص');
end;
$$;

-- =========================================================
-- ADMIN RPC: update violation status
-- =========================================================

create or replace function public.admin_update_violation_status(
  p_violation_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;

  if p_status not in ('NEW', 'REVIEWED', 'RESOLVED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.violation_reports
  set status = p_status,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_violation_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_VIOLATION_STATUS',
    'violation_reports',
    p_violation_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث البلاغ');
end;
$$;

-- =========================================================
-- SUPER ADMIN RPC: add / update admin profile
-- =========================================================

create or replace function public.super_admin_upsert_admin_profile(
  p_email text,
  p_full_name text,
  p_role text,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user record;
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if p_role not in ('SUPER_ADMIN', 'SUB_ADMIN') then
    return jsonb_build_object('ok', false, 'message', 'دور غير صحيح');
  end if;

  select id, email
  into target_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user.id is null then
    return jsonb_build_object('ok', false, 'message', 'يجب إنشاء المستخدم أولًا من Supabase Auth');
  end if;

  insert into public.admin_profiles (
    auth_user_id,
    email,
    full_name,
    role,
    is_active
  )
  values (
    target_user.id,
    target_user.email,
    p_full_name,
    p_role,
    p_is_active
  )
  on conflict (auth_user_id)
  do update set full_name = excluded.full_name,
                role = excluded.role,
                is_active = excluded.is_active;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_ADMIN_PROFILE',
    'admin_profiles',
    jsonb_build_object(
      'email',
      p_email,
      'role',
      p_role,
      'is_active',
      p_is_active
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المشرف');
end;
$$;

-- =========================================================
-- DEFAULT SPECIALTY LIMITS
-- تستطيعين تعديلها لاحقًا من لوحة الأدمن.
-- =========================================================

insert into public.specialty_daily_limits (specialty_name, daily_limit, is_active)
values
('أطباء الاختصاصات الأخرى', 10, true),
('الأشعة', 5, true),
('المختبر', 5, true),
('التمريض', 20, false),
('التخدير', 5, false),
('الإدارة', 0, false),
('غير ذلك', 0, false)
on conflict (specialty_name) do nothing;

-- =========================================================
-- REALTIME
-- يجعل Realtime أكثر موثوقية.
-- إذا ظهر خطأ أن الجدول already member of publication، تجاهليه.
-- =========================================================

alter table public.guard_screen_status replica identity full;
alter table public.employee_registrations replica identity full;
alter table public.violation_reports replica identity full;
alter table public.gate_access_logs replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'guard_screen_status'
  ) then
    alter publication supabase_realtime add table public.guard_screen_status;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'employee_registrations'
  ) then
    alter publication supabase_realtime add table public.employee_registrations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'violation_reports'
  ) then
    alter publication supabase_realtime add table public.violation_reports;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'gate_access_logs'
  ) then
    alter publication supabase_realtime add table public.gate_access_logs;
  end if;
end $$;

-- =========================================================
-- SUPER ADMIN SETUP
-- بعد إنشاء مستخدمك في Supabase Authentication → Users:
--
-- 1) انسخي User UID.
-- 2) بدلي القيم في الكود التالي.
-- 3) شغليه لوحده.
-- =========================================================

-- insert into public.admin_profiles (
--   auth_user_id,
--   email,
--   full_name,
--   role,
--   is_active
-- )
-- values (
--   'PASTE_YOUR_AUTH_USER_UID_HERE',
--   'PASTE_YOUR_AUTH_EMAIL_HERE',
--   'PASTE_YOUR_NAME_HERE',
--   'SUPER_ADMIN',
--   true
-- )
-- on conflict (auth_user_id)
-- do update set
--   email = excluded.email,
--   full_name = excluded.full_name,
--   role = 'SUPER_ADMIN',
--   is_active = true;


-- =========================================================
-- V1.1 PATCH — Hospital identity, final specialties, admin phone + permissions
-- يمكن تشغيل هذا الجزء بأمان حتى لو كان schema.sql شُغّل سابقًا.
-- =========================================================

alter table public.admin_profiles
add column if not exists phone_number text;

alter table public.admin_profiles
add column if not exists permissions jsonb not null default '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb;

create or replace function public.default_admin_permissions(p_role text)
returns jsonb
language sql
stable
as $$
  select case
    when p_role = 'SUPER_ADMIN' then '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": true, "can_manage_limits": true, "can_view_audit": true}'::jsonb
    else '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
  end;
$$;

create or replace function public.has_admin_permission(p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select role, permissions, is_active
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.role = 'SUPER_ADMIN' then
    return true;
  end if;

  if prof.role is null then
    return false;
  end if;

  return coalesce((prof.permissions ->> p_permission)::boolean, false);
exception when others then
  return false;
end;
$$;

-- تحديث الاختصاصات النهائية والحد = 7
update public.specialty_daily_limits
set is_active = false
where specialty_name not in (
  'جراحة عامة',
  'باطني',
  'ENT',
  'نسائية',
  'مسالك بولية',
  'عيون',
  'جراحة دماغ وأعصاب',
  'تخدير',
  'طب عام',
  'جراحة أوعية دموية',
  'أخرى'
);

insert into public.specialty_daily_limits (specialty_name, daily_limit, is_active)
values
('جراحة عامة', 7, true),
('باطني', 7, true),
('ENT', 7, true),
('نسائية', 7, true),
('مسالك بولية', 7, true),
('عيون', 7, true),
('جراحة دماغ وأعصاب', 7, true),
('تخدير', 7, true),
('طب عام', 7, true),
('جراحة أوعية دموية', 7, true),
('أخرى', 7, true)
on conflict (specialty_name)
do update set
  daily_limit = 7,
  is_active = true,
  updated_at = now();

-- RLS policies updated for permissions
drop policy if exists "Admins can read admin profiles" on public.admin_profiles;
create policy "Admins can read admin profiles"
on public.admin_profiles
for select
to authenticated
using (
  auth_user_id = auth.uid()
  or public.is_super_admin()
);

drop policy if exists "Super admin can manage admin profiles" on public.admin_profiles;
create policy "Super admin can manage admin profiles"
on public.admin_profiles
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

drop policy if exists "Admins can read registrations" on public.employee_registrations;
create policy "Admins can read registrations"
on public.employee_registrations
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_approve_requests'));

drop policy if exists "Admins can update registrations" on public.employee_registrations;
create policy "Admins can update registrations"
on public.employee_registrations
for update
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_approve_requests'))
with check (public.is_super_admin() or public.has_admin_permission('can_approve_requests'));

drop policy if exists "Admins can read access logs" on public.gate_access_logs;
create policy "Admins can read access logs"
on public.gate_access_logs
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_logs'));

drop policy if exists "Admins can read violation reports" on public.violation_reports;
create policy "Admins can read violation reports"
on public.violation_reports
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_review_violations'));

drop policy if exists "Admins can update violation reports" on public.violation_reports;
create policy "Admins can update violation reports"
on public.violation_reports
for update
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_review_violations'))
with check (public.is_super_admin() or public.has_admin_permission('can_review_violations'));

drop policy if exists "Super admin can manage specialty limits" on public.specialty_daily_limits;
create policy "Super admin can manage specialty limits"
on public.specialty_daily_limits
for all
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_manage_limits'))
with check (public.is_super_admin() or public.has_admin_permission('can_manage_limits'));

drop policy if exists "Admins can read audit logs" on public.admin_audit_logs;
create policy "Admins can read audit logs"
on public.admin_audit_logs
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_audit'));

-- Updated profile function
create or replace function public.get_my_admin_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select *
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.id is null then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالدخول');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', prof.id,
    'email', prof.email,
    'full_name', prof.full_name,
    'phone_number', prof.phone_number,
    'role', prof.role,
    'permissions', coalesce(prof.permissions, public.default_admin_permissions(prof.role))
  );
end;
$$;

-- Updated admin registration action with permission check
create or replace function public.admin_update_registration_status(
  p_registration_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_approve_requests')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالموافقة أو الرفض');
  end if;

  if p_status not in ('APPROVED', 'REJECTED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.employee_registrations
  set status = p_status,
      approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
      approved_by = case when p_status = 'APPROVED' then auth.uid() else approved_by end,
      rejected_at = case when p_status = 'REJECTED' then now() else rejected_at end,
      rejected_by = case when p_status = 'REJECTED' then auth.uid() else rejected_by end
  where id = p_registration_id
  returning * into reg;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_REGISTRATION_STATUS',
    'employee_registrations',
    p_registration_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث الطلب');
end;
$$;

-- Updated specialty limits function with permissions
create or replace function public.admin_upsert_specialty_limit(
  p_specialty_name text,
  p_daily_limit integer,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_manage_limits')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بتعديل حدود الاختصاصات');
  end if;

  if trim(p_specialty_name) = '' then
    return jsonb_build_object('ok', false, 'message', 'اسم الاختصاص مطلوب');
  end if;

  insert into public.specialty_daily_limits (
    specialty_name,
    daily_limit,
    is_active,
    updated_at
  )
  values (
    trim(p_specialty_name),
    greatest(p_daily_limit, 0),
    p_is_active,
    now()
  )
  on conflict (specialty_name)
  do update set daily_limit = excluded.daily_limit,
                is_active = excluded.is_active,
                updated_at = now();

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_SPECIALTY_LIMIT',
    'specialty_daily_limits',
    jsonb_build_object(
      'specialty',
      p_specialty_name,
      'daily_limit',
      p_daily_limit,
      'is_active',
      p_is_active
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ حد الاختصاص');
end;
$$;

-- Updated violation status function with permissions
create or replace function public.admin_update_violation_status(
  p_violation_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_review_violations')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بمراجعة البلاغات');
  end if;

  if p_status not in ('NEW', 'REVIEWED', 'RESOLVED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.violation_reports
  set status = p_status,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_violation_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_VIOLATION_STATUS',
    'violation_reports',
    p_violation_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث البلاغ');
end;
$$;

-- Updated super admin function: add/update admins with phone and permissions
create or replace function public.super_admin_upsert_admin_profile(
  p_email text,
  p_full_name text,
  p_phone_number text,
  p_role text,
  p_is_active boolean,
  p_permissions jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user record;
  final_permissions jsonb;
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if p_role not in ('SUPER_ADMIN', 'SUB_ADMIN') then
    return jsonb_build_object('ok', false, 'message', 'دور غير صحيح');
  end if;

  select id, email
  into target_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user.id is null then
    return jsonb_build_object('ok', false, 'message', 'يجب إنشاء المستخدم أولًا من Supabase Auth بنفس الإيميل');
  end if;

  final_permissions := coalesce(p_permissions, public.default_admin_permissions(p_role));

  insert into public.admin_profiles (
    auth_user_id,
    email,
    full_name,
    phone_number,
    role,
    is_active,
    permissions
  )
  values (
    target_user.id,
    target_user.email,
    p_full_name,
    p_phone_number,
    p_role,
    p_is_active,
    final_permissions
  )
  on conflict (auth_user_id)
  do update set full_name = excluded.full_name,
                phone_number = excluded.phone_number,
                role = excluded.role,
                is_active = excluded.is_active,
                permissions = excluded.permissions;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_ADMIN_PROFILE',
    'admin_profiles',
    jsonb_build_object(
      'email',
      p_email,
      'full_name',
      p_full_name,
      'phone_number',
      p_phone_number,
      'role',
      p_role,
      'is_active',
      p_is_active,
      'permissions',
      final_permissions
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المشرف');
end;
$$;

create or replace function public.super_admin_disable_admin_profile(
  p_admin_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if exists (
    select 1 from public.admin_profiles
    where id = p_admin_profile_id
      and auth_user_id = auth.uid()
  ) then
    return jsonb_build_object('ok', false, 'message', 'لا يمكنك تعطيل حسابك الحالي');
  end if;

  update public.admin_profiles
  set is_active = false
  where id = p_admin_profile_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id
  )
  values (
    auth.uid(),
    'DISABLE_ADMIN_PROFILE',
    'admin_profiles',
    p_admin_profile_id::text
  );

  return jsonb_build_object('ok', true, 'message', 'تم تعطيل المشرف');
end;
$$;

create or replace function public.super_admin_delete_admin_profile(
  p_admin_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if exists (
    select 1 from public.admin_profiles
    where id = p_admin_profile_id
      and auth_user_id = auth.uid()
  ) then
    return jsonb_build_object('ok', false, 'message', 'لا يمكنك حذف حسابك الحالي');
  end if;

  delete from public.admin_profiles
  where id = p_admin_profile_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id
  )
  values (
    auth.uid(),
    'DELETE_ADMIN_PROFILE',
    'admin_profiles',
    p_admin_profile_id::text
  );

  return jsonb_build_object('ok', true, 'message', 'تم حذف المشرف من لوحة الإدارة');
end;
$$;

-- Update existing super admin record with phone field and full permissions if already exists
-- ⚠️ بدّلي البريد أدناه ببريد حساب السوبر أدمن الحقيقي لديك محليًا
-- فقط قبل التشغيل. لا تكتبي بريدًا حقيقيًا في نسخة تُرفع لمستودع عام.
update public.admin_profiles
set full_name = 'اسم المدير',
    permissions = public.default_admin_permissions('SUPER_ADMIN')
where lower(email) = lower('your-admin-email@example.com')
  and role = 'SUPER_ADMIN';


-- =========================================================
-- schema_patch_qr_claim.sql
-- Emergency Room Parking V1.6
--
-- السبب:
-- QR token صالح 30 ثانية فقط. إذا الموظف مسح QR ثم أخذ وقتًا بإدخال بياناته،
-- كان النظام يرفضه لأن token انتهى قبل الضغط على إرسال.
--
-- الحل:
-- عند فتح verify.html من QR، يتم Claim للـ QR فورًا خلال أول 30 ثانية.
-- بعدها يحصل المستخدم على claim_token صالح لمدة 5 دقائق لإكمال النموذج.
--
-- الأمان:
-- - QR الأصلي يبقى صالح 30 ثانية فقط.
-- - بمجرد أن يفتحه أول شخص، يتم استعماله ولا يعود صالحًا لشخص آخر.
-- - claim_token يستخدم مرة واحدة فقط.
-- =========================================================

alter table public.qr_sessions
add column if not exists claim_token uuid unique;

alter table public.qr_sessions
add column if not exists claimed_at timestamptz;

alter table public.qr_sessions
add column if not exists claim_expires_at timestamptz;

alter table public.qr_sessions
add column if not exists claim_used_at timestamptz;

create index if not exists idx_qr_sessions_claim_token
on public.qr_sessions(claim_token);

create index if not exists idx_qr_sessions_claim_expires_at
on public.qr_sessions(claim_expires_at);

create or replace function public.claim_qr_session(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  token_uuid uuid;
  found_id uuid;
  new_claim uuid := gen_random_uuid();
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'QR غير موجود'
    );
  end if;

  begin
    token_uuid := p_token::uuid;
  exception when others then
    return jsonb_build_object(
      'ok', false,
      'message', 'QR غير صحيح'
    );
  end;

  select id
  into found_id
  from public.qr_sessions
  where token = token_uuid
    and used_at is null
    and expires_at > now()
  limit 1;

  if found_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد من شاشة الحارس'
    );
  end if;

  update public.qr_sessions
  set used_at = now(),
      claimed_at = now(),
      claim_token = new_claim,
      claim_expires_at = now() + interval '5 minutes',
      claim_used_at = null
  where id = found_id;

  return jsonb_build_object(
    'ok', true,
    'claim_token', new_claim::text,
    'expires_in_seconds', 300,
    'message', 'تم تفعيل جلسة QR، أكمل البيانات خلال 5 دقائق'
  );
end;
$$;

create or replace function public.validate_and_use_qr_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  input_uuid uuid;
  found_id uuid;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return false;
  end if;

  begin
    input_uuid := p_token::uuid;
  exception when others then
    return false;
  end;

  -- Backward compatibility: direct QR token use within original 30 seconds.
  select id
  into found_id
  from public.qr_sessions
  where token = input_uuid
    and used_at is null
    and expires_at > now()
  limit 1;

  if found_id is not null then
    update public.qr_sessions
    set used_at = now()
    where id = found_id;

    return true;
  end if;

  -- V1.6: claimed QR token. User opened QR on time, then has 5 minutes to submit form.
  select id
  into found_id
  from public.qr_sessions
  where claim_token = input_uuid
    and claim_used_at is null
    and claim_expires_at > now()
  limit 1;

  if found_id is not null then
    update public.qr_sessions
    set claim_used_at = now()
    where id = found_id;

    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.claim_qr_session(text) to anon, authenticated;
grant execute on function public.validate_and_use_qr_token(text) to anon, authenticated;

notify pgrst, 'reload schema';

-- اختبار سريع بعد التشغيل:
-- افتحي QR جديد من شاشة الحارس، امسحيه، يجب أن يظهر في صفحة verify أن جلسة QR فعالة.


-- #########################################################
-- SOURCE FILE: schema_patch_auto_verify.sql
-- #########################################################
-- =========================================================
-- schema_patch_auto_verify.sql
-- Emergency Room Parking - Auto trusted-device verification
--
-- الهدف:
-- 5) الموظف يسجل مرة واحدة فقط، وبعد الموافقة يستخدم التحقق.
-- 6) موظف الدخول الدائم يمكنه مسح QR فقط، فيتعرف النظام على جهازه الموثوق
--    بدون إدخال رقم الموظف كل مرة.
--
-- مهم:
-- شغلي هذا الملف مرة واحدة فقط من Supabase SQL Editor بعد التأكد أن النسخة الحالية تعمل.
-- لا تشغلي schema.sql الكامل من جديد فوق قاعدة شغالة.
-- =========================================================

create extension if not exists "pgcrypto";

-- 1) أعمدة الجهاز الموثوق داخل جدول الموظفين
alter table public.employee_registrations
add column if not exists trusted_device_enabled boolean not null default false;

alter table public.employee_registrations
add column if not exists trusted_device_token_hash text;

alter table public.employee_registrations
add column if not exists trusted_device_registered_at timestamptz;

alter table public.employee_registrations
add column if not exists trusted_device_last_used_at timestamptz;

alter table public.employee_registrations
add column if not exists trusted_device_revoked_at timestamptz;

create index if not exists idx_employee_registrations_trusted_device_token_hash
on public.employee_registrations(trusted_device_token_hash)
where trusted_device_token_hash is not null;

create index if not exists idx_employee_registrations_trusted_device_enabled
on public.employee_registrations(trusted_device_enabled);

-- 2) Hash helper: لا نخزن رمز الجهاز الخام في قاعدة البيانات
create or replace function public.hash_trusted_device_token(p_token text)
returns text
language sql
immutable
as $$
  select encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
$$;

-- 3) فحص أهلية الموظف لتفعيل التحقق السريع من جهازه
create or replace function public.can_register_trusted_device(
  p_employee_id text,
  p_mobile_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'eligible', false, 'message', 'رقم الموظف ورقم الهاتف مطلوبان');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'الموظف غير موجود');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'التفعيل متاح بعد موافقة الإدارة فقط');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'الإدارة لم تفعل التحقق السريع لهذا الموظف بعد');
  end if;

  return jsonb_build_object(
    'ok', true,
    'eligible', true,
    'already_linked', reg.trusted_device_token_hash is not null,
    'message', 'يمكن تفعيل التحقق السريع على هذا الجهاز'
  );
end;
$$;

-- 4) ربط هذا الجهاز بموظف بعد التحقق اليدوي الصحيح
create or replace function public.register_trusted_device(
  p_employee_id text,
  p_mobile_number text,
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
begin
  if clean_emp = '' or clean_mobile = '' or length(clean_token) < 40 then
    return jsonb_build_object('ok', false, 'message', 'بيانات تفعيل الجهاز غير مكتملة');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن ربط الجهاز قبل موافقة الإدارة');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', false, 'message', 'الإدارة لم تفعل التحقق السريع لهذا الموظف بعد');
  end if;

  update public.employee_registrations
  set trusted_device_token_hash = public.hash_trusted_device_token(clean_token),
      trusted_device_registered_at = now(),
      trusted_device_last_used_at = null,
      trusted_device_revoked_at = null
  where id = reg.id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  ) values (
    null,
    'TRUSTED_DEVICE_LINKED_BY_EMPLOYEE',
    'employee_registrations',
    reg.id::text,
    jsonb_build_object('employee_id', reg.employee_id)
  );

  return jsonb_build_object('ok', true, 'message', 'تم ربط هذا الجهاز بنجاح. في المرات القادمة امسح QR فقط.');
end;
$$;

-- 5) تحقق تلقائي من رمز الجهاز الموثوق + QR
-- ملاحظة أمان وتجربة استخدام:
-- لا يتم استهلاك QR إلا بعد التأكد أن رمز الجهاز مربوط بموظف مؤهل.
-- إذا كان الرمز المحلي قديمًا أو ملغيًا، يبقى QR صالحًا للتعبئة اليدوية خلال مهلة الـ 5 دقائق.
create or replace function public.auto_employee_check(
  p_device_token text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_token text := trim(coalesce(p_device_token, ''));
  qr_ok boolean := false;
begin
  if length(clean_token) < 40 then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'رمز الجهاز غير صالح. أعد التفعيل من التحقق اليدوي.'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where trusted_device_enabled = true
    and trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
  limit 1;

  if reg.id is null then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'هذا الجهاز غير مربوط أو تم إلغاء ربطه. استخدم التحقق اليدوي ثم أعد التفعيل.'
    );
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'الموظف غير معتمد حاليًا'
    );
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط'
    );
  end if;

  if p_qr_token is null or length(trim(p_qr_token)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'message', 'يجب مسح QR مباشر من شاشة الحارس'
    );
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok = false then
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد'
    );
  end if;

  update public.employee_registrations
  set trusted_device_last_used_at = now()
  where id = reg.id;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  ) values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    'ALLOWED',
    'AUTO_TRUSTED_DEVICE',
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status(
    'ALLOWED',
    reg.full_name,
    reg.employee_id,
    'مسموح بالدخول — تحقق تلقائي من جهاز موثوق'
  );

  return jsonb_build_object(
    'ok', true,
    'result', 'ALLOWED',
    'message', 'مسموح بالدخول — تم التحقق تلقائيًا من الجهاز الموثوق',
    'employee_id', reg.employee_id,
    'full_name', reg.full_name
  );
end;
$$;

-- 6) تحكم الأدمن: تفعيل/تعطيل/إلغاء ربط الجهاز
create or replace function public.admin_set_trusted_device(
  p_registration_id uuid,
  p_enabled boolean,
  p_revoke boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;

  select *
  into reg
  from public.employee_registrations
  where id = p_registration_id
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود');
  end if;

  if p_enabled = true then
    if reg.status <> 'APPROVED' then
      return jsonb_build_object('ok', false, 'message', 'يجب اعتماد الموظف أولًا');
    end if;

    if not public.is_permanently_allowed_specialty(reg.specialty) then
      return jsonb_build_object('ok', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
    end if;
  end if;

  update public.employee_registrations
  set trusted_device_enabled = p_enabled,
      trusted_device_token_hash = case when p_revoke or p_enabled = false then null else trusted_device_token_hash end,
      trusted_device_registered_at = case when p_revoke or p_enabled = false then null else trusted_device_registered_at end,
      trusted_device_last_used_at = case when p_revoke or p_enabled = false then null else trusted_device_last_used_at end,
      trusted_device_revoked_at = case when p_revoke or p_enabled = false then now() else trusted_device_revoked_at end
  where id = p_registration_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  ) values (
    auth.uid(),
    'ADMIN_SET_TRUSTED_DEVICE',
    'employee_registrations',
    p_registration_id::text,
    jsonb_build_object(
      'enabled', p_enabled,
      'revoked', p_revoke,
      'employee_id', reg.employee_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'message', case
      when p_enabled = false then 'تم تعطيل التحقق السريع وإلغاء ربط الجهاز'
      when p_revoke = true then 'تم إلغاء ربط الجهاز. يستطيع الموظف ربط جهاز جديد من التحقق اليدوي.'
      else 'تم تفعيل التحقق السريع. على الموظف إجراء تحقق يدوي مرة واحدة لربط جهازه.'
    end
  );
end;
$$;

grant execute on function public.can_register_trusted_device(text, text) to anon, authenticated;
grant execute on function public.register_trusted_device(text, text, text) to anon, authenticated;
grant execute on function public.auto_employee_check(text, text) to anon, authenticated;
grant execute on function public.admin_set_trusted_device(uuid, boolean, boolean) to authenticated;

notify pgrst, 'reload schema';


-- #########################################################
-- SOURCE FILE: schema_patch_permanent_specialty.sql
-- #########################################################
-- =========================================================
-- PATCH: Permanently allowed specialty option
-- الإسعاف والطوارئ (DRS/NRS/EMT/MLT)
-- شغّلي هذا الملف في Supabase SQL Editor إذا كانت قاعدة البيانات موجودة مسبقًا.
-- =========================================================

create or replace function public.normalize_specialty_name(p_specialty text)
returns text
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := upper(trim(coalesce(p_specialty, '')));

  v := replace(v, 'أ', 'ا');
  v := replace(v, 'إ', 'ا');
  v := replace(v, 'آ', 'ا');
  v := replace(v, 'ٱ', 'ا');
  v := replace(v, 'ة', 'ه');

  v := regexp_replace(v, '\s+', '', 'g');
  v := replace(v, '،', ',');
  v := replace(v, '／', '/');
  v := replace(v, '(', '');
  v := replace(v, ')', '');
  v := replace(v, '-', '');

  return v;
end;
$$;

create or replace function public.is_permanently_allowed_specialty(p_specialty text)
returns boolean
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := public.normalize_specialty_name(p_specialty);

  return v in (
    public.normalize_specialty_name('الإسعاف والطوارئ (DRS/NRS/EMT/MLT)'),
    public.normalize_specialty_name('الإسعاف والطوارئ - DRS/NRS/EMT/MLT'),
    public.normalize_specialty_name('الإسعاف والطوارئ DRS,NRS,EMT/MLT'),
    public.normalize_specialty_name('DRS,NRS,EMT/MLT'),
    public.normalize_specialty_name('DRS/NRS/EMT/MLT'),
    public.normalize_specialty_name('الإسعاف والطوارئ')
  );
end;
$$;

create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  lim record;
  used_count integer := 0;
  qr_required boolean := false;
  qr_ok boolean := true;
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل رقم الموظف ورقم الهاتف');
  end if;

  if p_qr_token is not null and length(trim(p_qr_token)) > 0 then
    qr_required := true;
    qr_ok := public.validate_and_use_qr_token(p_qr_token);
  end if;

  if qr_required and qr_ok = false then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object(
      'ok', true,
      'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا'
    );
  end if;

  if reg.status = 'PENDING' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'PENDING_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة');

    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة');
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'REJECTED_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة'
    );
  end if;

  -- Permanently allowed specialty group:
  -- الإسعاف والطوارئ (DRS/NRS/EMT/MLT)
  -- هذا الاختصاص لا يدخل في specialty_daily_limits ولا يتحول إلى LIMITED.
  if public.is_permanently_allowed_specialty(reg.specialty) then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'ALLOWED',
      'PERMANENTLY_ALLOWED_SPECIALTY',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
    );

    perform public.set_guard_status(
      'ALLOWED',
      reg.full_name,
      reg.employee_id,
      'مسموح بالدخول — اختصاص مسموح دائمًا'
    );

    return jsonb_build_object(
      'ok', true,
      'result', 'ALLOWED',
      'message', 'مسموح بالدخول — اختصاص مسموح دائمًا'
    );
  end if;

  -- APPROVED employee: check specialty limit.
  select *
  into lim
  from public.specialty_daily_limits
  where specialty_name = reg.specialty
    and is_active = true
  limit 1;

  if lim.id is not null then
    select count(*)
    into used_count
    from public.gate_access_logs
    where specialty = reg.specialty
      and result = 'LIMITED'
      and created_at >= date_trunc('day', now())
      and created_at < date_trunc('day', now()) + interval '1 day';

    if used_count >= lim.daily_limit then
      insert into public.gate_access_logs (
        employee_registration_id,
        employee_id,
        mobile_number,
        full_name,
        specialty,
        result,
        reason
      )
      values (
        reg.id,
        reg.employee_id,
        reg.mobile_number,
        reg.full_name,
        reg.specialty,
        'DENIED',
        'SPECIALTY_DAILY_LIMIT_REACHED'
      );

      perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم الوصول للحد اليومي لهذا الاختصاص');

      return jsonb_build_object(
        'ok', true,
        'result', 'DENIED',
        'message', 'غير مسموح — تم الوصول للحد اليومي لهذا الاختصاص'
      );
    end if;

    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'LIMITED',
      'SPECIALTY_LIMITED_ACCESS',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'مسموح جزئيًا حسب الاختصاص');

    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'مسموح جزئيًا حسب الاختصاص');
  end if;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  )
  values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    'ALLOWED',
    'APPROVED_EMPLOYEE',
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول');

  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول');
end;
$$;

notify pgrst, 'reload schema';

-- بعد تشغيل الباتش: الموظف APPROVED صاحب هذا الاختصاص سيظهر ALLOWED دائمًا.


-- #########################################################
-- SOURCE FILE: security_fixes_v2.sql
-- #########################################################
-- =========================================================
-- SECURITY FIXES V2 — Emergency Room Parking (كراج طوارئ البشير)
-- =========================================================
-- شغّلي هذا الملف مرة واحدة في Supabase SQL Editor، بعد:
--   schema.sql
--   schema_patch_auto_verify.sql
--   schema_patch_permanent_specialty.sql
--   setup_sub_admins.sql
--
-- الملف Idempotent: يمكن إعادة تشغيله بأمان دون أي ضرر.
-- لا يحذف أي بيانات موجودة.
--
-- يعالج:
--  1) تجاوز QR في manual_employee_check (RPC-level bypass)
--  2) صور المخالفات العامة (Storage bucket public)
--  3) شاشة الحارس بدون مصادقة (Guard Authentication)
--  4) Race condition في الحد اليومي (specialty_daily_limits)
--  5) كشف بيانات الموظف في guard_screen_status للـ anon
--  6) ضعف تفعيل "الجهاز الموثوق" (trusted device) بعاملين فقط
--  7) رسم QR وهمي عند تعطل Supabase (fallback QR) — الجزء الخاص
--     بالواجهة الأمامية موجود في index.html، وهذا الملف يجهز
--     RPC حالة النظام التي تستخدمها الواجهة الجديدة.
-- =========================================================


-- =========================================================
-- 1) دور الحارس (GUARD) — إعادة استخدام admin_profiles + Supabase Auth
-- =========================================================

alter table public.admin_profiles
  drop constraint if exists admin_profiles_role_check;

alter table public.admin_profiles
  add constraint admin_profiles_role_check
  check (role in ('SUPER_ADMIN', 'SUB_ADMIN', 'GUARD'));

create or replace function public.is_guard()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_admin_role() = 'GUARD', false);
$$;

create or replace function public.is_guard_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_guard() or public.is_admin(), false);
$$;

-- ملاحظة: is_admin() تبقى كما هي (SUPER_ADMIN / SUB_ADMIN فقط)،
-- لذلك أي مكان في المشروع يعتمد على is_admin() لصلاحيات الإدارة
-- لن يتأثر — دور GUARD منفصل تمامًا عن صلاحيات الإدارة.


-- =========================================================
-- 2) عمود تتبع "آخر تحقق ناجح عبر QR" — يُستخدم لربط تفعيل
--    الجهاز الموثوق بتحقق QR حقيقي بدل employee_id+mobile فقط
-- =========================================================

alter table public.employee_registrations
  add column if not exists last_verified_at timestamptz;


-- =========================================================
-- 3) إغلاق تجاوز QR في manual_employee_check
--    QR أصبح إلزاميًا دائمًا (لا يوجد مسار بدون QR بعد الآن).
--    (هذا يستبدل التعريف الذي في schema.sql وأيضًا الذي في
--     schema_patch_permanent_specialty.sql — لأن هذا آخر تعريف
--     يُشغَّل، فهو الذي يبقى فعليًا في القاعدة).
-- =========================================================

create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  lim record;
  used_count integer := 0;
  qr_ok boolean := false;
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل رقم الموظف ورقم الهاتف');
  end if;

  -- === الإصلاح الجوهري: QR إلزامي دائمًا، بدون أي استثناء ===
  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok = false then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد من شاشة الحارس'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object(
      'ok', true,
      'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا'
    );
  end if;

  if reg.status = 'PENDING' then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'PENDING_EMPLOYEE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة');
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'REJECTED_EMPLOYEE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'تم رفض الطلب، يرجى مراجعة الإدارة');
  end if;

  -- اختصاص الدخول الدائم (الإسعاف والطوارئ)
  if public.is_permanently_allowed_specialty(reg.specialty) then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
      'ALLOWED', 'PERMANENTLY_ALLOWED_SPECIALTY', p_qr_token::uuid
    );

    update public.employee_registrations set last_verified_at = now() where id = reg.id;

    perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول — اختصاص مسموح دائمًا');
    return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول — اختصاص مسموح دائمًا');
  end if;

  -- === الإصلاح الثاني: قفل صف الحد اليومي (FOR UPDATE) يمنع
  --     تجاوز العدد عند دخول طلبين متزامنين لنفس اللحظة ===
  select *
  into lim
  from public.specialty_daily_limits
  where specialty_name = reg.specialty
    and is_active = true
  limit 1
  for update;

  if lim.id is not null then
    select count(*)
    into used_count
    from public.gate_access_logs
    where specialty = reg.specialty
      and result = 'LIMITED'
      and created_at >= date_trunc('day', now())
      and created_at < date_trunc('day', now()) + interval '1 day';

    if used_count >= lim.daily_limit then
      insert into public.gate_access_logs (
        employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
      ) values (
        reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
        'DENIED', 'SPECIALTY_DAILY_LIMIT_REACHED'
      );
      perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم الوصول للحد اليومي لهذا الاختصاص');
      return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'غير مسموح — تم الوصول للحد اليومي لهذا الاختصاص');
    end if;

    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
      'LIMITED', 'SPECIALTY_LIMITED_ACCESS', p_qr_token::uuid
    );

    update public.employee_registrations set last_verified_at = now() where id = reg.id;

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'مسموح جزئيًا حسب الاختصاص');
    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'مسموح جزئيًا حسب الاختصاص');
  end if;

  insert into public.gate_access_logs (
    employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token
  ) values (
    reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
    'ALLOWED', 'APPROVED_EMPLOYEE', p_qr_token::uuid
  );

  update public.employee_registrations set last_verified_at = now() where id = reg.id;

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول');
  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول');
end;
$$;

-- manual_employee_check يبقى متاحًا لـ anon/authenticated لأنه مسار
-- "التحقق الذاتي" الذي يستخدمه الموظف نفسه من verify.html بعد مسح
-- QR حقيقي من شاشة الحارس. الأمان الآن يعتمد على QR الإلزامي أعلاه،
-- وليس على إخفاء الدالة.
grant execute on function public.manual_employee_check(text, text, text) to anon, authenticated;


-- =========================================================
-- 4) مسار طوارئ حقيقي للحارس فقط (بديل آمن لما كان manual bypass)
--    يُستخدم فقط إذا تعطّل مسح QR فعليًا، ويتطلب تسجيل دخول حارس/إدارة.
-- =========================================================

create or replace function public.guard_emergency_override(
  p_employee_id text,
  p_mobile_number text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
  clean_reason text := trim(coalesce(p_reason, ''));
begin
  if not public.is_guard_or_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح — تسجيل دخول الحارس مطلوب');
  end if;

  if clean_emp = '' or clean_mobile = '' or clean_reason = '' then
    return jsonb_build_object('ok', false, 'message', 'رقم الموظف والهاتف وسبب الطوارئ كلها مطلوبة');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null or reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود أو غير معتمد');
  end if;

  insert into public.gate_access_logs (
    employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
  ) values (
    reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
    'ALLOWED', 'GUARD_EMERGENCY_OVERRIDE: ' || clean_reason
  );

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, target_id, details)
  values (
    auth.uid(), 'GUARD_EMERGENCY_OVERRIDE', 'employee_registrations', reg.id,
    jsonb_build_object('reason', clean_reason)
  );

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'دخول طوارئ بواسطة الحارس — ' || clean_reason);

  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'تم السماح (مسار طوارئ) — تم تسجيل الحدث');
end;
$$;

revoke all on function public.guard_emergency_override(text, text, text) from public, anon;
grant execute on function public.guard_emergency_override(text, text, text) to authenticated;


-- =========================================================
-- 5) حصر إنشاء/تصفير شاشة الحارس بالحارس أو الإدارة فقط
-- =========================================================

create or replace function public.create_qr_session()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_token uuid;
begin
  if not public.is_guard_or_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح — تسجيل دخول الحارس مطلوب');
  end if;

  delete from public.qr_sessions
  where expires_at < now() - interval '5 minutes';

  insert into public.qr_sessions (expires_at)
  values (now() + interval '30 seconds')
  returning token into new_token;

  return jsonb_build_object('ok', true, 'token', new_token::text, 'expires_in_seconds', 30);
end;
$$;

create or replace function public.reset_guard_screen()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_guard_or_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح — تسجيل دخول الحارس مطلوب');
  end if;

  update public.guard_screen_status
  set current_status = 'READY',
      employee_name = null,
      employee_id = null,
      message = 'QR جاهز للمسح',
      updated_at = now()
  where id = 1;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.create_qr_session() from public, anon;
grant execute on function public.create_qr_session() to authenticated;

revoke all on function public.reset_guard_screen() from public, anon;
grant execute on function public.reset_guard_screen() to authenticated;


-- =========================================================
-- 6) إخفاء بيانات الموظف عن anon في guard_screen_status
--    (القراءة الآن للحارس/الإدارة المسجّلين فقط)
-- =========================================================

drop policy if exists "Anyone can read guard screen status" on public.guard_screen_status;

create policy "Guard and admins can read guard screen status"
on public.guard_screen_status
for select
to authenticated
using (public.is_guard_or_admin());


-- =========================================================
-- 7) صور المخالفات: من Public إلى Private + Signed URLs
-- =========================================================

update storage.buckets
set public = false
where id = 'violation-photos';

drop policy if exists "Anyone can upload violation photos" on storage.objects;
drop policy if exists "Anyone can read violation photos" on storage.objects;

create policy "Guard can upload violation photos"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'violation-photos' and public.is_guard_or_admin());

create policy "Admins can read violation photos"
on storage.objects
for select
to authenticated
using (bucket_id = 'violation-photos' and public.is_admin());

-- تحويل الروابط العامة القديمة المخزّنة في violation_reports.photo_url
-- إلى مسار (path) فقط داخل الـ bucket، بدل الرابط العام الكامل،
-- حتى تعمل مع Signed URLs في admin_dashboard.html الجديد.
update public.violation_reports
set photo_url = regexp_replace(photo_url, '^.*/violation-photos/', '')
where photo_url like '%/violation-photos/%';


-- =========================================================
-- 8) تقوية تفعيل "الجهاز الموثوق"
--    الشرط الجديد: يجب أن يكون هناك تحقق QR ناجح فعليًا لهذا
--    الموظف خلال آخر 3 دقائق (last_verified_at) — أي لا يمكن
--    تفعيل جهاز بمجرد معرفة employee_id + mobile فقط.
-- =========================================================

create or replace function public.can_register_trusted_device(
  p_employee_id text,
  p_mobile_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'eligible', false, 'message', 'رقم الموظف ورقم الهاتف مطلوبان');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'الموظف غير موجود');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'التفعيل متاح بعد موافقة الإدارة فقط');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'الإدارة لم تفعل التحقق السريع لهذا الموظف بعد');
  end if;

  if reg.last_verified_at is null or reg.last_verified_at < now() - interval '3 minutes' then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'نفّذي تحقق QR ناجح أولًا (خلال آخر 3 دقائق) قبل تفعيل الجهاز');
  end if;

  return jsonb_build_object(
    'ok', true,
    'eligible', true,
    'already_linked', reg.trusted_device_token_hash is not null,
    'message', 'يمكن تفعيل التحقق السريع على هذا الجهاز'
  );
end;
$$;

create or replace function public.register_trusted_device(
  p_employee_id text,
  p_mobile_number text,
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
begin
  if clean_emp = '' or clean_mobile = '' or length(clean_token) < 40 then
    return jsonb_build_object('ok', false, 'message', 'بيانات تفعيل الجهاز غير مكتملة');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن ربط الجهاز قبل موافقة الإدارة');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', false, 'message', 'الإدارة لم تفعل التحقق السريع لهذا الموظف بعد');
  end if;

  -- === الإصلاح: يجب وجود تحقق QR ناجح حديث (last_verified_at) ===
  if reg.last_verified_at is null or reg.last_verified_at < now() - interval '3 minutes' then
    return jsonb_build_object('ok', false, 'message', 'يجب تنفيذ تحقق QR ناجح خلال آخر 3 دقائق قبل تفعيل الجهاز');
  end if;

  update public.employee_registrations
  set trusted_device_token_hash = public.hash_trusted_device_token(clean_token),
      trusted_device_registered_at = now(),
      trusted_device_last_used_at = null,
      trusted_device_revoked_at = null
  where id = reg.id;

  insert into public.admin_audit_logs (
    admin_auth_user_id, action, target_table, target_id, details
  ) values (
    null, 'TRUSTED_DEVICE_LINKED_BY_EMPLOYEE', 'employee_registrations', reg.id,
    jsonb_build_object('employee_id', reg.employee_id)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تفعيل الجهاز. من الآن فصاعدًا يكفي مسح QR فقط.');
end;
$$;

grant execute on function public.can_register_trusted_device(text, text) to anon, authenticated;
grant execute on function public.register_trusted_device(text, text, text) to anon, authenticated;


-- =========================================================
-- 9) RPC صغيرة تستخدمها الواجهة الجديدة (index.html) لمعرفة
--    هوية الحارس المسجّل دخوله وعرض اسمه/تسجيل خروجه
-- =========================================================

create or replace function public.get_my_guard_or_admin_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select * into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.id is null then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بدخول شاشة الحارس');
  end if;

  if prof.role not in ('GUARD', 'SUPER_ADMIN', 'SUB_ADMIN') then
    return jsonb_build_object('ok', false, 'message', 'هذا الحساب غير مصرح له بشاشة الحارس');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', prof.id,
    'email', prof.email,
    'full_name', prof.full_name,
    'role', prof.role
  );
end;
$$;

grant execute on function public.get_my_guard_or_admin_profile() to authenticated;

-- =========================================================
-- 10) إصلاح إضافي مهم اكتُشف أثناء إضافة دور GUARD:
--     has_admin_permission() كانت تتحقق فقط من وجود صف في
--     admin_profiles، دون التأكد أن role فعليًا SUPER_ADMIN أو
--     SUB_ADMIN. بما أن default_admin_permissions() تُرجع
--     can_approve_requests/can_review_violations/can_view_logs
--     = true افتراضيًا لأي دور غير SUPER_ADMIN، فإن حساب GUARD
--     كان سيرث صلاحيات إدارية فعلية (الموافقة على الموظفين،
--     مراجعة المخالفات، قراءة السجلات) عبر سياسات RLS التي تعتمد
--     على has_admin_permission(). تم إغلاق هذا الآن.
-- =========================================================

create or replace function public.has_admin_permission(p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select role, permissions, is_active
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.role is null then
    return false;
  end if;

  -- === الإصلاح: دور GUARD لا يملك أي صلاحية إدارية إطلاقًا ===
  if prof.role not in ('SUPER_ADMIN', 'SUB_ADMIN') then
    return false;
  end if;

  if prof.role = 'SUPER_ADMIN' then
    return true;
  end if;

  return coalesce((prof.permissions ->> p_permission)::boolean, false);
exception when others then
  return false;
end;
$$;

create or replace function public.default_admin_permissions(p_role text)
returns jsonb
language sql
stable
as $$
  select case
    when p_role = 'SUPER_ADMIN' then '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": true, "can_manage_limits": true, "can_view_audit": true}'::jsonb
    when p_role = 'SUB_ADMIN' then '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
    else '{"can_approve_requests": false, "can_review_violations": false, "can_view_logs": false, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
  end;
$$;

-- السماح لسوبر أدمن بإضافة/تعديل حسابات GUARD من نفس شاشة إدارة
-- المشرفين في admin_dashboard.html (بدل الاكتفاء بـ SQL يدوي).
create or replace function public.super_admin_upsert_admin_profile(
  p_email text,
  p_full_name text,
  p_phone_number text,
  p_role text,
  p_is_active boolean,
  p_permissions jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user record;
  final_permissions jsonb;
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if p_role not in ('SUPER_ADMIN', 'SUB_ADMIN', 'GUARD') then
    return jsonb_build_object('ok', false, 'message', 'دور غير صحيح');
  end if;

  select id, email
  into target_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user.id is null then
    return jsonb_build_object('ok', false, 'message', 'يجب إنشاء المستخدم أولًا من Supabase Auth بنفس الإيميل');
  end if;

  final_permissions := coalesce(p_permissions, public.default_admin_permissions(p_role));

  insert into public.admin_profiles (
    auth_user_id, email, full_name, phone_number, role, is_active, permissions
  ) values (
    target_user.id, target_user.email, p_full_name, p_phone_number, p_role, p_is_active, final_permissions
  )
  on conflict (auth_user_id)
  do update set full_name = excluded.full_name,
                phone_number = excluded.phone_number,
                role = excluded.role,
                is_active = excluded.is_active,
                permissions = excluded.permissions;

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, details)
  values (
    auth.uid(), 'UPSERT_ADMIN_PROFILE', 'admin_profiles',
    jsonb_build_object('email', p_email, 'full_name', p_full_name, 'phone_number', p_phone_number, 'role', p_role)
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ بيانات الحساب');
end;
$$;

notify pgrst, 'reload schema';


-- =========================================================
-- 11) تقليل البيانات: تخزين hash لرمز QR بدل الرمز نفسه في السجلات
--     (gate_access_logs.qr_token كان يخزن الـ UUID الفعلي؛ الآن
--     نخزن بصمة SHA-256 فقط في عمود جديد qr_token_hash، ونوقف
--     تعبئة العمود القديم في أي إدراج جديد).
-- =========================================================

alter table public.gate_access_logs
  add column if not exists qr_token_hash text;

update public.gate_access_logs
set qr_token_hash = encode(digest(qr_token::text, 'sha256'), 'hex')
where qr_token is not null
  and qr_token_hash is null;

update public.gate_access_logs
set qr_token = null
where qr_token is not null;

-- manual_employee_check: استبدال qr_token بـ qr_token_hash في الإدراجات الثلاثة
create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  lim record;
  used_count integer := 0;
  qr_ok boolean := false;
  qr_hash text;
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل رقم الموظف ورقم الهاتف');
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);
  qr_hash := encode(digest(coalesce(p_qr_token, ''), 'sha256'), 'hex');

  if qr_ok = false then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد من شاشة الحارس'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object(
      'ok', true,
      'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا'
    );
  end if;

  if reg.status = 'PENDING' then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'PENDING_EMPLOYEE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة');
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'REJECTED_EMPLOYEE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'تم رفض الطلب، يرجى مراجعة الإدارة');
  end if;

  if public.is_permanently_allowed_specialty(reg.specialty) then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token_hash
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
      'ALLOWED', 'PERMANENTLY_ALLOWED_SPECIALTY', qr_hash
    );

    update public.employee_registrations set last_verified_at = now() where id = reg.id;

    perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول — اختصاص مسموح دائمًا');
    return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول — اختصاص مسموح دائمًا');
  end if;

  select *
  into lim
  from public.specialty_daily_limits
  where specialty_name = reg.specialty
    and is_active = true
  limit 1
  for update;

  if lim.id is not null then
    select count(*)
    into used_count
    from public.gate_access_logs
    where specialty = reg.specialty
      and result = 'LIMITED'
      and created_at >= date_trunc('day', now())
      and created_at < date_trunc('day', now()) + interval '1 day';

    if used_count >= lim.daily_limit then
      insert into public.gate_access_logs (
        employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
      ) values (
        reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
        'DENIED', 'SPECIALTY_DAILY_LIMIT_REACHED'
      );
      perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم الوصول للحد اليومي لهذا الاختصاص');
      return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'غير مسموح — تم الوصول للحد اليومي لهذا الاختصاص');
    end if;

    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token_hash
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
      'LIMITED', 'SPECIALTY_LIMITED_ACCESS', qr_hash
    );

    update public.employee_registrations set last_verified_at = now() where id = reg.id;

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'مسموح جزئيًا حسب الاختصاص');
    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'مسموح جزئيًا حسب الاختصاص');
  end if;

  insert into public.gate_access_logs (
    employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token_hash
  ) values (
    reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
    'ALLOWED', 'APPROVED_EMPLOYEE', qr_hash
  );

  update public.employee_registrations set last_verified_at = now() where id = reg.id;

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول');
  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول');
end;
$$;

grant execute on function public.manual_employee_check(text, text, text) to anon, authenticated;

-- register_employee_request: نفس الاستبدال في مسار "الدخول الأول"
create or replace function public.register_employee_request(
  p_full_name text,
  p_employee_id text,
  p_mobile_number text,
  p_specialty text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  qr_ok boolean := false;
  clean_name text := trim(p_full_name);
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
  clean_specialty text := trim(p_specialty);
begin
  if clean_name = '' or clean_emp = '' or clean_mobile = '' or clean_specialty = '' then
    return jsonb_build_object(
      'ok', false, 'result', 'DENIED', 'message', 'الرجاء تعبئة الاسم ورقم الموظف ورقم الهاتف والقسم'
    );
  end if;

  select * into reg from public.employee_registrations where employee_id = clean_emp limit 1;

  if reg.id is null then
    insert into public.employee_registrations (
      full_name, employee_id, mobile_number, specialty, status, first_entry_used, first_entry_at
    ) values (
      clean_name, clean_emp, clean_mobile, clean_specialty, 'PENDING', false, null
    )
    returning * into reg;
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty, 'DENIED', 'REJECTED_EMPLOYEE'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب مسبقًا');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'تم رفض الطلب، يرجى مراجعة الإدارة');
  end if;

  if reg.status = 'APPROVED' then
    return public.manual_employee_check(reg.employee_id, reg.mobile_number, p_qr_token);
  end if;

  if reg.first_entry_used = true then
    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
      'DENIED', 'PENDING_FIRST_ENTRY_ALREADY_USED'
    );
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة — تم استخدام الدخول الأول سابقًا');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة، وتم استخدام الدخول الأول سابقًا');
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok then
    update public.employee_registrations
    set first_entry_used = true, first_entry_at = now()
    where id = reg.id
    returning * into reg;

    insert into public.gate_access_logs (
      employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token_hash
    ) values (
      reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
      'PENDING_FIRST_ENTRY', 'FIRST_ENTRY_AFTER_REGISTRATION',
      encode(digest(coalesce(p_qr_token, ''), 'sha256'), 'hex')
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'دخول أول مرة — بانتظار موافقة الإدارة');
    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'تم إرسال طلبك. تم السماح بدخول أول مرة فقط، والطلب بانتظار موافقة الإدارة');
  end if;

  return jsonb_build_object('ok', true, 'result', 'PENDING', 'message', 'تم إرسال طلبك، الرجاء انتظار موافقة الإدارة');
end;
$$;

grant execute on function public.register_employee_request(text, text, text, text, text) to anon, authenticated;

-- auto_employee_check: نفس الاستبدال في مسار الجهاز الموثوق
create or replace function public.auto_employee_check(
  p_device_token text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_token text := trim(coalesce(p_device_token, ''));
  qr_ok boolean := false;
begin
  if length(clean_token) < 40 then
    return jsonb_build_object(
      'ok', false, 'result', 'DENIED', 'clear_device', true,
      'message', 'رمز الجهاز غير صالح. أعد التفعيل من التحقق اليدوي.'
    );
  end if;

  select * into reg
  from public.employee_registrations
  where trusted_device_enabled = true
    and trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
  limit 1;

  if reg.id is null then
    return jsonb_build_object(
      'ok', true, 'result', 'DENIED', 'clear_device', true,
      'message', 'هذا الجهاز غير مربوط أو تم إلغاء ربطه. استخدم التحقق اليدوي ثم أعد التفعيل.'
    );
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'clear_device', true, 'message', 'الموظف غير معتمد حاليًا');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if p_qr_token is null or length(trim(p_qr_token)) = 0 then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'يجب مسح QR مباشر من شاشة الحارس');
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok = false then
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'QR غير صالح أو منتهي');
    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد');
  end if;

  update public.employee_registrations
  set trusted_device_last_used_at = now(),
      last_verified_at = now()
  where id = reg.id;

  insert into public.gate_access_logs (
    employee_registration_id, employee_id, mobile_number, full_name, specialty, result, reason, qr_token_hash
  ) values (
    reg.id, reg.employee_id, reg.mobile_number, reg.full_name, reg.specialty,
    'ALLOWED', 'AUTO_TRUSTED_DEVICE', encode(digest(coalesce(p_qr_token, ''), 'sha256'), 'hex')
  );

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول — تحقق تلقائي من جهاز موثوق');

  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول — تحقق تلقائي من جهاز موثوق');
end;
$$;

grant execute on function public.auto_employee_check(text, text) to anon, authenticated;


-- =========================================================
-- 12) سياسة الاحتفاظ بالبيانات (Retention Policy)
--     دالة تنظيف يدوية يمكن استدعاؤها من السوبر أدمن، أو جدولتها
--     تلقائيًا عبر pg_cron إن كان متاحًا في مشروع Supabase.
--     المدد الافتراضية (عدّليها حسب سياسة المستشفى):
--       - gate_access_logs   → أقدم من 365 يومًا
--       - admin_audit_logs   → أقدم من 365 يومًا
--       - violation_reports + الصور المرتبطة بها → أقدم من 90 يومًا
-- =========================================================

create or replace function public.purge_expired_records()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_logs integer;
  deleted_audit integer;
  deleted_violation_photos integer;
  deleted_violations integer;
begin
  -- تسمح بالتنفيذ إما لسوبر أدمن مسجّل دخوله من الواجهة، أو عند
  -- عدم وجود جلسة مستخدم إطلاقًا (استدعاء من SQL Editor بصلاحية
  -- postgres، أو من مهمة pg_cron مجدولة) — أي مستخدم anon/authenticated
  -- عادي يملك auth.uid() دائمًا، لذلك هذا لا يفتح الباب لغير الموثوقين.
  if auth.uid() is not null and not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  delete from public.gate_access_logs
  where created_at < now() - interval '365 days';
  get diagnostics deleted_logs = row_count;

  delete from public.admin_audit_logs
  where created_at < now() - interval '365 days';
  get diagnostics deleted_audit = row_count;

  delete from storage.objects
  where bucket_id = 'violation-photos'
    and name in (
      select photo_url from public.violation_reports
      where created_at < now() - interval '90 days'
    );
  get diagnostics deleted_violation_photos = row_count;

  delete from public.violation_reports
  where created_at < now() - interval '90 days';
  get diagnostics deleted_violations = row_count;

  insert into public.admin_audit_logs (admin_auth_user_id, action, target_table, details)
  values (
    auth.uid(), 'PURGE_EXPIRED_RECORDS', 'multiple',
    jsonb_build_object(
      'deleted_gate_access_logs', deleted_logs,
      'deleted_admin_audit_logs', deleted_audit,
      'deleted_violation_photos', deleted_violation_photos,
      'deleted_violation_reports', deleted_violations
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deleted_gate_access_logs', deleted_logs,
    'deleted_admin_audit_logs', deleted_audit,
    'deleted_violation_photos', deleted_violation_photos,
    'deleted_violation_reports', deleted_violations
  );
end;
$$;

grant execute on function public.purge_expired_records() to authenticated;

-- === جدولة تلقائية اختيارية عبر pg_cron ===
-- إن كان extension "pg_cron" مفعّلًا في مشروع Supabase (Database →
-- Extensions)، شغّلي هذا السطر مرة واحدة لتشغيل التنظيف يوميًا
-- الساعة 3 فجرًا. إن لم يكن مفعّلًا، يمكنك استدعاء
-- purge_expired_records() يدويًا من SQL Editor بين فترة وأخرى.
--
-- select cron.schedule(
--   'purge-expired-records-daily',
--   '0 3 * * *',
--   $cron$select public.purge_expired_records()$cron$
-- );

notify pgrst, 'reload schema';

-- =========================================================
-- خطوات يدوية متبقية (لا يمكن تنفيذها من هذا الملف):
--
-- 1) أنشئي حساب/حسابات "حارس" في Supabase Auth (Authentication →
--    Users → Add user)، ثم أضيفي صفًا في admin_profiles بـ
--    role = 'GUARD' لكل حساب حارس، تمامًا كما تُضاف حسابات
--    SUB_ADMIN حاليًا عبر setup_sub_admins.sql. مثال:
--
--    insert into public.admin_profiles (auth_user_id, email, full_name, role)
--    values ('AUTH_USER_UID_HERE', 'guard1@example.com', 'اسم الحارس', 'GUARD');
--
-- 2) دوّري (Rotate) أي كلمات مرور مرتبطة بالحسابات التي كانت
--    UIDs/بريدها منشورة سابقًا في README.md قبل تنظيفه.
--
-- 3) نظّفي أرشيف Git (تاريخ الـ commits) من README القديم عبر
--    git filter-repo أو BFG Repo-Cleaner، ثم push --force.
-- =========================================================


-- #########################################################
-- SCALE SECTION (300-400 employees): extra composite indexes
-- #########################################################
CREATE INDEX IF NOT EXISTS idx_logs_specialty_result_created ON public.gate_access_logs(specialty, result, created_at);
CREATE INDEX IF NOT EXISTS idx_regs_employee_mobile ON public.employee_registrations(employee_id, mobile_number);

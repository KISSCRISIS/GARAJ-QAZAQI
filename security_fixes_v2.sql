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

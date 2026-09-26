-- =========================================================
-- setup_sub_admins.sql
-- Emergency Room Parking
--
-- هذا الملف يضيف المشرفين الفرعيين SUB_ADMIN مباشرة.
--
-- قبل تشغيله:
-- 1) شغّلي schema.sql أولًا.
-- 2) تأكدي أن هؤلاء المستخدمين موجودون في:
--    Supabase → Authentication → Users
-- 3) لا تضعي كلمات المرور هنا.
--
-- الصلاحيات الافتراضية:
-- - موافقة / رفض طلبات التسجيل: نعم
-- - مراجعة بلاغات الحارس: نعم
-- - رؤية سجلات الدخول والإحصائيات: نعم
-- - تصدير CSV: لا
-- - تعديل حدود الاختصاصات اليومية: لا
-- - رؤية Audit: لا
--
-- يمكنك تغيير الصلاحيات لاحقًا من:
-- admin_dashboard.html → Admins
-- =========================================================

alter table public.admin_profiles
add column if not exists phone_number text;

alter table public.admin_profiles
add column if not exists permissions jsonb not null default '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb;

-- ⚠️ تنبيه أمني: هذا الملف كان يحتوي سابقًا على أسماء وبريد
-- إلكتروني وأرقام UID وهواتف حقيقية للمشرفين، منشورة داخل
-- مستودع GitHub عام. تم استبدالها بالكامل بقيم توضيحية (placeholders).
--
-- لا تُعيدي أبدًا كتابة بيانات حقيقية داخل ملف يُرفع لمستودع عام.
-- عبّئي البيانات الحقيقية محليًا فقط قبل التشغيل في Supabase SQL
-- Editor، ولا تحفظي/ترفعي النسخة المعبّأة إلى Git.
--
-- إذا كانت بيانات المشرفين الثلاثة (Hasan Shehadeh, Suliman Abu
-- Awaad, Osama Kanan) قد نُشرت فعليًا من قبل في تاريخ هذا
-- المستودع العام، يجب اعتبار بريدهم/UID الخاص بهم "مكشوفًا"،
-- ويُنصح بتدوير/تحديث حساباتهم في Supabase Authentication.

insert into public.admin_profiles (
  auth_user_id,
  email,
  full_name,
  phone_number,
  role,
  is_active,
  permissions
)
values
(
  'PASTE_AUTH_USER_UID_1'::uuid,
  'sub-admin-1@example.com',
  'اسم المشرف الأول',
  '07XXXXXXXX',
  'SUB_ADMIN',
  true,
  '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
),
(
  'PASTE_AUTH_USER_UID_2'::uuid,
  'sub-admin-2@example.com',
  'اسم المشرف الثاني',
  '07XXXXXXXX',
  'SUB_ADMIN',
  true,
  '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
),
(
  'PASTE_AUTH_USER_UID_3'::uuid,
  'sub-admin-3@example.com',
  'اسم المشرف الثالث',
  '07XXXXXXXX',
  'SUB_ADMIN',
  true,
  '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
)
on conflict (auth_user_id)
do update set
  email = excluded.email,
  full_name = excluded.full_name,
  phone_number = excluded.phone_number,
  role = 'SUB_ADMIN',
  is_active = true,
  permissions = excluded.permissions;

-- للتأكد بعد التشغيل (بدّلي الإيميلات أعلاه بالإيميلات الحقيقية محليًا فقط):
select
  email,
  full_name,
  phone_number,
  role,
  is_active,
  permissions
from public.admin_profiles
where role = 'SUB_ADMIN'
order by full_name;

-- =========================================================
-- إضافة حسابات "حارس" (GUARD) — جديد مع إصلاحات الأمان V2
-- كرري نفس الأسلوب أعلاه لكل حارس، بـ role = 'GUARD':
--
-- insert into public.admin_profiles (auth_user_id, email, full_name, role, is_active)
-- values ('PASTE_AUTH_USER_UID', 'guard1@example.com', 'اسم الحارس', 'GUARD', true)
-- on conflict (auth_user_id) do update set role = 'GUARD', is_active = true;
-- =========================================================

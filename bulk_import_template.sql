-- =========================================================
-- BULK IMPORT TEMPLATE — 300-400 employees
-- RL: run AFTER full-deploy.sql. Inserts PENDING requests only
-- (employees still get first-entry + need admin approval).
-- How to use:
--  1) Put your list in Excel with columns: full_name | employee_id | mobile_number | specialty
--  2) Specialty must match EXACTLY one of the dashboard names, e.g:
--     'الإسعاف والطوارئ (DRS/NRS/EMT/MLT)', 'جراحة عامة', 'باطني', 'ENT',
--     'نسائية', 'مسالك بولية', 'عيون', 'جراحة دماغ وأعصاب', 'تخدير',
--     'طب عام', 'جراحة أوعية دموية', 'أخرى'
--  3) In Excel, build one line per row with a formula like:
--     ="('"&A2&"', '"&B2&"', '"&C2&"', '"&D2&"'),"
--  4) Paste the generated lines into the VALUES list below (replace examples),
--     delete the last trailing comma, then Run. Duplicates (employee_id)
--     are skipped automatically (ON CONFLICT DO NOTHING).
-- =========================================================

INSERT INTO public.employee_registrations
  (full_name, employee_id, mobile_number, specialty, status)
VALUES
  ('مثال: أحمد محمد', '1001', '0790000001', 'جراحة عامة', 'PENDING'),
  ('مثال: سارة خالد', '1002', '0790000002', 'الإسعاف والطوارئ (DRS/NRS/EMT/MLT)', 'PENDING')
ON CONFLICT (employee_id) DO NOTHING;

-- Verify after import:
-- SELECT status, count(*) FROM public.employee_registrations GROUP BY status;
-- Expected: one row PENDING with your total count (300-400).

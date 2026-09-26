-- =====================================================
-- Emergency Room Parking System V2
-- Production Schema
-- Supabase PostgreSQL
-- =====================================================

BEGIN;


-- =====================================================
-- Extensions
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;



-- =====================================================
-- 1) Employees
-- الموظفون والكادر الطبي
-- =====================================================

CREATE TABLE IF NOT EXISTS employees (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    employee_id VARCHAR(50)
    UNIQUE
    NOT NULL,


    full_name VARCHAR(255)
    NOT NULL,


    specialty VARCHAR(100),


    department VARCHAR(100),


    employee_type VARCHAR(30)
    NOT NULL
    CHECK
    (
        employee_type IN
        (
            'DOCTOR',
            'NURSE',
            'TECHNICIAN',
            'SECURITY',
            'ADMIN',
            'OTHER'
        )
    ),


    phone_number VARCHAR(20),


    email VARCHAR(255),


    -- حالة الحساب
    status VARCHAR(20)
    DEFAULT 'PENDING'
    CHECK
    (
        status IN
        (
            'PENDING',
            'APPROVED',
            'REJECTED'
        )
    ),


    -- صلاحية الدخول
    permit_type VARCHAR(20)
    DEFAULT 'DENIED'
    CHECK
    (
        permit_type IN
        (
            'ALLOWED',
            'LIMITED',
            'DENIED'
        )
    ),



    -- اعتماد الرقم الوظيفي

    employee_id_verified BOOLEAN
    DEFAULT FALSE,


    verified_by UUID,


    verified_at TIMESTAMP WITH TIME ZONE,


    rejection_reason TEXT,


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW(),


    updated_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);





-- =====================================================
-- 2) User Roles
-- صلاحيات المستخدمين
-- =====================================================

CREATE TABLE IF NOT EXISTS user_roles (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    user_id UUID
    REFERENCES auth.users(id)
    ON DELETE CASCADE,


    employee_id UUID
    REFERENCES employees(id)
    ON DELETE CASCADE,


    role VARCHAR(30)
    NOT NULL
    CHECK
    (
        role IN
        (
            'SUPER_ADMIN',
            'ADMIN',
            'GUARD',
            'EMPLOYEE'
        )
    ),


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW(),


    UNIQUE(user_id, role)

);



COMMIT;

BEGIN;


-- =====================================================
-- 3) Employee Devices
-- الأجهزة المرتبطة بحساب الموظف
-- =====================================================

CREATE TABLE IF NOT EXISTS employee_devices (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    employee_id UUID
    REFERENCES employees(id)
    ON DELETE CASCADE,


    device_id TEXT
    NOT NULL,


    device_name TEXT,


    platform VARCHAR(30)
    CHECK
    (
        platform IN
        (
            'ANDROID',
            'IOS',
            'WEB',
            'OTHER'
        )
    ),


    active BOOLEAN
    DEFAULT TRUE,


    verified BOOLEAN
    DEFAULT FALSE,


    last_seen TIMESTAMP WITH TIME ZONE
    DEFAULT NOW(),


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW(),


    UNIQUE(employee_id, device_id)

);





-- =====================================================
-- 4) QR Sessions
-- جلسات QR التي ينشئها الحارس
-- =====================================================

CREATE TABLE IF NOT EXISTS qr_sessions (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    token UUID
    DEFAULT gen_random_uuid()
    UNIQUE
    NOT NULL,


    created_by UUID
    REFERENCES auth.users(id)
    ON DELETE SET NULL,


    gate_name VARCHAR(100)
    DEFAULT 'بوابة الطوارئ الرئيسية',


    status VARCHAR(20)
    DEFAULT 'ACTIVE'
    CHECK
    (
        status IN
        (
            'ACTIVE',
            'EXPIRED',
            'USED',
            'CANCELLED'
        )
    ),


    expires_at TIMESTAMP WITH TIME ZONE
    NOT NULL,


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);



-- =====================================================
-- Indexes
-- تحسين سرعة البحث
-- =====================================================


CREATE INDEX IF NOT EXISTS idx_employee_device

ON employee_devices(employee_id);



CREATE INDEX IF NOT EXISTS idx_qr_token

ON qr_sessions(token);



CREATE INDEX IF NOT EXISTS idx_qr_expiry

ON qr_sessions(expires_at);



COMMIT;


BEGIN;


-- =====================================================
-- 5) Access Attempts
-- كل محاولة مسح QR
-- =====================================================

CREATE TABLE IF NOT EXISTS access_attempts (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    employee_id UUID
    REFERENCES employees(id)
    ON DELETE SET NULL,


    qr_session_id UUID
    REFERENCES qr_sessions(id)
    ON DELETE SET NULL,


    device_id TEXT,


    result VARCHAR(20)
    NOT NULL
    CHECK
    (
        result IN
        (
            'ALLOWED',
            'DENIED'
        )
    ),


    reason TEXT,


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);





-- =====================================================
-- 6) Gate Access Logs
-- سجل الدخول النهائي
-- =====================================================

CREATE TABLE IF NOT EXISTS gate_access_logs (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    employee_id UUID
    REFERENCES employees(id)
    ON DELETE SET NULL,


    result VARCHAR(20)
    NOT NULL
    CHECK
    (
        result IN
        (
            'ALLOWED',
            'DENIED'
        )
    ),


    gate_name VARCHAR(100)
    DEFAULT 'بوابة الطوارئ الرئيسية',


    guard_id UUID
    REFERENCES auth.users(id)
    ON DELETE SET NULL,


    access_time TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);





-- =====================================================
-- 7) System Status
-- حالة البوابة الواحدة
-- =====================================================

CREATE TABLE IF NOT EXISTS system_status (

    id INTEGER PRIMARY KEY
    DEFAULT 1,


    gate_name VARCHAR(100)
    DEFAULT 'بوابة الطوارئ الرئيسية',


    gate_status VARCHAR(30)
    DEFAULT 'CLOSED'
    CHECK
    (
        gate_status IN
        (
            'CLOSED',
            'OPEN_REQUESTED'
        )
    ),


    requested_by UUID
    REFERENCES auth.users(id)
    ON DELETE SET NULL,


    updated_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);



INSERT INTO system_status
(
id
)

VALUES
(
1
)

ON CONFLICT (id)
DO NOTHING;





-- =====================================================
-- 8) Notifications
-- لإظهار النتيجة للطرفين مباشرة
-- =====================================================

CREATE TABLE IF NOT EXISTS notifications (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    employee_id UUID
    REFERENCES employees(id)
    ON DELETE CASCADE,


    guard_id UUID
    REFERENCES auth.users(id)
    ON DELETE CASCADE,


    title TEXT
    NOT NULL,


    message TEXT
    NOT NULL,


    notification_type VARCHAR(30)
    CHECK
    (
        notification_type IN
        (
            'ACCESS_ALLOWED',
            'ACCESS_DENIED',
            'SYSTEM'
        )
    ),


    read_by_employee BOOLEAN
    DEFAULT FALSE,


    read_by_guard BOOLEAN
    DEFAULT FALSE,


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);





-- =====================================================
-- Indexes
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_access_attempt_employee

ON access_attempts(employee_id);



CREATE INDEX IF NOT EXISTS idx_access_logs_employee

ON gate_access_logs(employee_id);



CREATE INDEX IF NOT EXISTS idx_notifications_employee

ON notifications(employee_id);



COMMIT;

BEGIN;


-- =====================================================
-- 9) Function: إنشاء QR Session للحارس
-- صلاحية QR = 30 ثانية
-- =====================================================

CREATE OR REPLACE FUNCTION create_qr_session()

RETURNS UUID

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

DECLARE

    new_session UUID;

BEGIN


INSERT INTO qr_sessions
(
    created_by,
    expires_at
)

VALUES

(
    auth.uid(),
    NOW() + INTERVAL '30 seconds'
)

RETURNING id INTO new_session;



INSERT INTO audit_logs
(
    user_id,
    action,
    details
)

VALUES

(
    auth.uid(),
    'CREATE_QR_SESSION',
    jsonb_build_object(
        'session_id',
        new_session
    )
);



RETURN new_session;


END;

$$;





-- =====================================================
-- 10) Function: التحقق من صلاحية الموظف
-- =====================================================

CREATE OR REPLACE FUNCTION check_employee_access
(
    p_employee_id UUID
)

RETURNS BOOLEAN

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

DECLARE

    allowed BOOLEAN;


BEGIN


SELECT

(
    status = 'APPROVED'
    AND
    permit_type = 'ALLOWED'
)

INTO allowed


FROM employees


WHERE id = p_employee_id;



RETURN COALESCE(allowed,FALSE);


END;

$$;





-- =====================================================
-- 11) Function: التحقق من الجهاز
-- =====================================================

CREATE OR REPLACE FUNCTION check_employee_device

(
    p_employee_id UUID,

    p_device_id TEXT

)

RETURNS BOOLEAN


LANGUAGE plpgsql

SECURITY DEFINER


AS $$


DECLARE

    valid_device BOOLEAN;


BEGIN


SELECT EXISTS

(
    SELECT 1

    FROM employee_devices

    WHERE employee_id = p_employee_id

    AND device_id = p_device_id

    AND active = TRUE

    AND verified = TRUE
)

INTO valid_device;



RETURN valid_device;


END;

$$;





-- =====================================================
-- 12) Function: عملية الدخول الكاملة
-- =====================================================

CREATE OR REPLACE FUNCTION verify_gate_access

(

    p_qr_token UUID,

    p_employee_id UUID,

    p_device_id TEXT

)

RETURNS JSONB


LANGUAGE plpgsql

SECURITY DEFINER


AS $$


DECLARE


    qr_valid BOOLEAN;

    employee_valid BOOLEAN;

    device_valid BOOLEAN;


    final_result TEXT;

    final_reason TEXT;


    session_id UUID;


BEGIN



-- فحص QR

SELECT

EXISTS

(

SELECT 1

FROM qr_sessions

WHERE token = p_qr_token

AND status='ACTIVE'

AND expires_at > NOW()

)

INTO qr_valid;



IF NOT qr_valid THEN


    final_result := 'DENIED';

    final_reason := 'Invalid or expired QR';


ELSE



-- فحص الموظف

employee_valid :=
check_employee_access
(
p_employee_id
);



IF NOT employee_valid THEN


    final_result := 'DENIED';

    final_reason := 'Employee not approved';



ELSE



-- فحص الجهاز

device_valid :=
check_employee_device
(
p_employee_id,
p_device_id
);



IF NOT device_valid THEN


    final_result := 'DENIED';

    final_reason := 'Device not verified';



ELSE


    final_result := 'ALLOWED';

    final_reason := 'Access granted';



END IF;


END IF;


END IF;





-- جلب جلسة QR

SELECT id

INTO session_id

FROM qr_sessions

WHERE token=p_qr_token

LIMIT 1;





-- تسجيل المحاولة

INSERT INTO access_attempts

(

employee_id,

qr_session_id,

device_id,

result,

reason

)

VALUES

(

p_employee_id,

session_id,

p_device_id,

final_result,

final_reason

);





-- سجل الدخول

INSERT INTO gate_access_logs

(

employee_id,

result

)

VALUES

(

p_employee_id,

final_result

);





-- إشعار الطرفين

INSERT INTO notifications

(

employee_id,

title,

message,

notification_type

)

VALUES

(

p_employee_id,


CASE

WHEN final_result='ALLOWED'

THEN 'تم السماح بالدخول'

ELSE 'تم رفض الدخول'

END,


final_reason,


CASE

WHEN final_result='ALLOWED'

THEN 'ACCESS_ALLOWED'

ELSE 'ACCESS_DENIED'

END

);





RETURN jsonb_build_object

(

'result',
final_result,


'reason',
final_reason,


'time',
NOW()

);



END;

$$;



COMMIT;

BEGIN;


-- =====================================================
-- تفعيل RLS
-- =====================================================

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE employee_devices ENABLE ROW LEVEL SECURITY;

ALTER TABLE qr_sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE access_attempts ENABLE ROW LEVEL SECURITY;

ALTER TABLE gate_access_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE system_status ENABLE ROW LEVEL SECURITY;

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;




-- =====================================================
-- Function لمعرفة صلاحية المستخدم
-- =====================================================

CREATE OR REPLACE FUNCTION has_role
(
    required_role TEXT
)

RETURNS BOOLEAN

LANGUAGE sql

SECURITY DEFINER

AS $$

SELECT EXISTS
(
    SELECT 1

    FROM user_roles

    WHERE user_id = auth.uid()

    AND role = required_role
);

$$;





-- =====================================================
-- 1) Employees Policies
-- =====================================================


-- الموظف يرى بياناته فقط

CREATE POLICY employee_read_self

ON employees

FOR SELECT

TO authenticated

USING

(
id IN
(
SELECT employee_id

FROM user_roles

WHERE user_id = auth.uid()
)
);




-- الإدارة تدير الموظفين

CREATE POLICY admin_manage_employees

ON employees

FOR ALL

TO authenticated

USING

(
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
)

WITH CHECK

(
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 2) User Roles
-- =====================================================


CREATE POLICY admin_manage_roles

ON user_roles

FOR ALL

TO authenticated

USING

(
has_role('SUPER_ADMIN')
)

WITH CHECK

(
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 3) Employee Devices
-- =====================================================


-- الموظف يرى أجهزته

CREATE POLICY employee_view_devices

ON employee_devices

FOR SELECT

TO authenticated

USING

(
employee_id IN
(
SELECT employee_id

FROM user_roles

WHERE user_id = auth.uid()
)
);




-- الإدارة تدير الأجهزة

CREATE POLICY admin_manage_devices

ON employee_devices

FOR ALL

TO authenticated

USING

(
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 4) QR Sessions
-- =====================================================


-- الحارس ينشئ ويرى QR الخاص به

CREATE POLICY guard_qr_access

ON qr_sessions

FOR ALL

TO authenticated

USING

(
created_by = auth.uid()

OR

has_role('ADMIN')

OR

has_role('SUPER_ADMIN')
)

WITH CHECK

(
has_role('GUARD')
OR
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 5) Access Attempts
-- =====================================================


CREATE POLICY guard_view_attempts

ON access_attempts

FOR SELECT

TO authenticated

USING

(
has_role('GUARD')
OR
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 6) Gate Logs
-- =====================================================


CREATE POLICY guard_view_logs

ON gate_access_logs

FOR SELECT

TO authenticated

USING

(
has_role('GUARD')
OR
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 7) System Status
-- =====================================================


CREATE POLICY guard_control_gate

ON system_status

FOR ALL

TO authenticated

USING

(
has_role('GUARD')
OR
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
)

WITH CHECK

(
has_role('GUARD')
OR
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 8) Notifications
-- =====================================================


CREATE POLICY employee_read_notifications

ON notifications

FOR SELECT

TO authenticated

USING

(
employee_id IN
(
SELECT employee_id

FROM user_roles

WHERE user_id = auth.uid()
)

OR

guard_id = auth.uid()

OR

has_role('ADMIN')
);





COMMIT;

BEGIN;


-- =====================================================
-- 1) Audit Logs
-- سجل العمليات الحساسة
-- =====================================================

CREATE TABLE IF NOT EXISTS audit_logs (

    id UUID PRIMARY KEY
    DEFAULT gen_random_uuid(),


    user_id UUID
    REFERENCES auth.users(id)
    ON DELETE SET NULL,


    action TEXT NOT NULL,


    table_name TEXT,


    record_id UUID,


    details JSONB,


    created_at TIMESTAMP WITH TIME ZONE
    DEFAULT NOW()

);



ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;



CREATE POLICY admin_read_audit

ON audit_logs

FOR SELECT

TO authenticated

USING

(
has_role('ADMIN')
OR
has_role('SUPER_ADMIN')
);





-- =====================================================
-- 2) تحديث updated_at تلقائياً
-- =====================================================


CREATE OR REPLACE FUNCTION update_timestamp()

RETURNS TRIGGER

LANGUAGE plpgsql

AS $$

BEGIN

NEW.updated_at = NOW();

RETURN NEW;

END;

$$;



CREATE TRIGGER employees_updated_at

BEFORE UPDATE

ON employees

FOR EACH ROW

EXECUTE FUNCTION update_timestamp();





-- =====================================================
-- 3) تسجيل تغييرات الموظفين
-- =====================================================


CREATE OR REPLACE FUNCTION employee_audit_trigger()

RETURNS TRIGGER

LANGUAGE plpgsql

AS $$

BEGIN


INSERT INTO audit_logs

(
user_id,
action,
table_name,
record_id,
details
)

VALUES

(
auth.uid(),
TG_OP,
'employees',
NEW.id,
jsonb_build_object(
'old_status', OLD.status,
'new_status', NEW.status,
'old_permission', OLD.permit_type,
'new_permission', NEW.permit_type
)
);



RETURN NEW;


END;

$$;



CREATE TRIGGER employees_audit

AFTER UPDATE

ON employees

FOR EACH ROW

EXECUTE FUNCTION employee_audit_trigger();





-- =====================================================
-- 4) تنظيف QR المنتهي
-- =====================================================


CREATE OR REPLACE FUNCTION expire_qr_sessions()

RETURNS VOID

LANGUAGE sql

AS $$


UPDATE qr_sessions

SET status='EXPIRED'

WHERE expires_at < NOW()

AND status='ACTIVE';


$$;





-- =====================================================
-- 5) منع تعديل السجلات الحساسة
-- =====================================================


REVOKE UPDATE, DELETE

ON gate_access_logs

FROM PUBLIC;



REVOKE UPDATE, DELETE

ON access_attempts

FROM PUBLIC;



REVOKE UPDATE, DELETE

ON audit_logs

FROM PUBLIC;





-- =====================================================
-- 6) Indexes النهائية
-- =====================================================


CREATE INDEX IF NOT EXISTS idx_employee_status

ON employees(status);



CREATE INDEX IF NOT EXISTS idx_employee_permission

ON employees(permit_type);



CREATE INDEX IF NOT EXISTS idx_access_result

ON access_attempts(result);



CREATE INDEX IF NOT EXISTS idx_logs_time

ON gate_access_logs(access_time);



CREATE INDEX IF NOT EXISTS idx_notifications_time

ON notifications(created_at);





COMMIT;
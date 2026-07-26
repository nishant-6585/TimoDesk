-- 016: Microsoft Entra ID (Azure AD) directory sync support.
--
-- staff.entra_id anchors a staff row to its Graph user (users/{id}) so the
-- sync is idempotent: match by entra_id first, adopt-by-name once, and
-- deactivate rows whose Graph account disappeared. Manually-created staff
-- (entra_id NULL) are never touched by the sync's deactivation pass.

alter table staff add column if not exists entra_id text;

create unique index if not exists idx_staff_entra_id
  on staff (entra_id)
  where entra_id is not null;

comment on column staff.entra_id is
  'Microsoft Graph user id (Entra ID / Azure AD). NULL = manually created staff.';

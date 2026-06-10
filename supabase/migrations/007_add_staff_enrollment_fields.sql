-- Migration 007: Add phone and person_type to staff table
-- Enables staff enrollment form to capture contact info and person type

ALTER TABLE staff ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS person_type text CHECK (person_type IN ('Employee', 'Staff'));

-- Create index for duplicate detection (by phone + person_type)
CREATE INDEX IF NOT EXISTS idx_staff_phone_person_type ON staff(phone, person_type);

-- Add comment
COMMENT ON COLUMN staff.phone IS 'Staff phone number (validated format)';
COMMENT ON COLUMN staff.person_type IS 'Staff type: Employee or Staff (internal only)';

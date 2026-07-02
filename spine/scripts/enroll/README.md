# Face Recognition Enrollment Pipeline

Enroll staff faces into `staff_face_embedding` table with DPDP-compliant consent tracking.

## Setup

### 1. Install Dependencies

```bash
cd spine
npm install @vladmandic/face-api canvas supabase
```

### 2. Get Test Data (LFW - Labeled Faces in the Wild)

For smoke-testing the pipeline with real faces (non-synthetic):

```bash
cd spine/scripts/enroll

# Download LFW (252MB, ~13K images of 5K+ identities)
wget http://vis-www.cs.umass.edu/lfw/lfw.tgz
tar -xzf lfw.tgz

# Create small test slice: ~10 identities × 3-5 images each
mkdir -p photos
cd lfw

# Pick 10 random identities (or manually select known-good ones)
ls | head -10 | while read identity; do
  mkdir -p ../photos/test-lfw-${identity}
  # Copy 3-5 images from each identity
  ls ${identity}/*.jpg 2>/dev/null | head -5 | xargs -I {} cp {} ../photos/test-lfw-${identity}/
done

cd ..
echo "✅ Test photos copied to photos/"
```

### 3. Update Consent Manifest

Edit `consent_manifest.json`:
- **For test data**: Use `consent_ref: "TEST-LFW-*"` and `consent_method: "test_dataset"` (tagged for purge)
- **For real staff**: Use `consent_ref: "consent-YYYY-MM-DD-<name>"` with actual consent dates

Example:
```json
{
  "test-lfw-1": {
    "full_name": "Test LFW 1",
    "role": "TEST_DATASET",
    "consent_ref": "TEST-LFW-001",
    ...
  },
  "alice-johnson": {
    "full_name": "Alice Johnson",
    "role": "Reception",
    "consent_ref": "consent-2024-06-09-alice",
    ...
  }
}
```

### 4. Run Enrollment

```bash
# Set env vars
export SUPABASE_URL="https://agjygqllxdclyzfxidgy.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<your-service-role-key>"

# Enroll
npx ts-node enroll.ts --consent-manifest consent_manifest.json
```

Output:
```
[Enroll] Processing 13 staff folders...

[Enroll] Processing Test LFW 1...
  ✅ 1.jpg: Embedded (128-dim descriptor)
  ✅ 2.jpg: Embedded (128-dim descriptor)
  ✅ 3.jpg: Embedded (128-dim descriptor)
  📊 Test LFW 1: 3/3 photos enrolled (3 embeddings)

...

════════════════════════════════════════════════════════════════
ENROLLMENT SUMMARY
════════════════════════════════════════════════════════════════

✅ Test LFW 1: 3/3 photos → 3 embeddings
✅ Alice Johnson: 4/4 photos → 4 embeddings
...
✅ TOTAL: 13 staff, 40 photos processed, 40 embeddings enrolled
════════════════════════════════════════════════════════════════

⚠️  TEST DATA DETECTED

To purge all test embeddings before go-live, run:

  delete from staff_face_embedding where consent_ref like 'TEST-%';
  delete from staff where id like 'test-%';
```

## Calibration (after enrollment)

After enrolling real faces, calibrate the L2 distance threshold:

```bash
node --env-file=.env scripts/enroll/calibrate.js
```

This measures distances with the SAME nearest-neighbour rule the recognizer uses
(leave-one-out), excludes TEST rows, and prints:

1. Per-person **enrollment health** — pose count + worst self-distance, flagging
   `THIN` (<5 poses) and `LOOSE` enrollments, plus the closest impostor pair —
   i.e. an explicit **re-enrollment worklist** (who to re-capture sharper).
2. Genuine vs impostor nearest-neighbour distributions + the gap (SEPARATED/OVERLAP).
3. A recommended threshold: the gap midpoint when separated, or a precision value
   (just below the closest impostor) when the distributions overlap.

Apply the result in `spine/src/config/face-recognition.ts` → `FACE_CONFIG.threshold`.

## Purge Test Data (before go-live)

```sql
-- Delete all TEST-* embeddings
DELETE FROM staff_face_embedding WHERE consent_ref LIKE 'TEST-%';

-- Delete all test-* staff entries
DELETE FROM staff WHERE id LIKE 'test-%';
```

Or via CLI:
```bash
npx supabase db push
psql "$DATABASE_URL" -c "DELETE FROM staff_face_embedding WHERE consent_ref LIKE 'TEST-%';"
psql "$DATABASE_URL" -c "DELETE FROM staff WHERE id LIKE 'test-%';"
```

## Real Staff Enrollment

Once calibration is complete and you have real staff photos:

1. Create real staff folders in `photos/`:
   ```
   photos/
   ├── alice-johnson/
   │   ├── 1.jpg (varied angles/lighting)
   │   ├── 2.jpg
   │   └── 3.jpg
   └── bob-smith/
       └── 1.jpg
   ```

2. Update `consent_manifest.json` with real staff + actual consent dates/refs

3. Run enrollment again (new insertions won't conflict with test data)

## DPDP Hygiene Checklist

- ✅ Consent metadata (consent_ref, consent_at) captured for every embedding
- ✅ Test data clearly tagged (consent_ref: "TEST-*") for purge
- ✅ Visitor faces NOT stored (anonymous counting only in recognition phase)
- ✅ Staff embeddings permanent until consent withdrawn
- ✅ Purge command provided and documented

## Notes

- **Vector dimension**: 128-dim (face-api.js / face_recognition_net)
- **Distance metric**: Euclidean (L2)
- **Index**: IVFFlat with l2_ops
- **Threshold**: Calibrated per dataset (typically 0.50-0.60)
- **Multiple images per staff**: Improves matching robustness

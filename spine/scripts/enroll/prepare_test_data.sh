#!/bin/bash

# Prepare test data from LFW
# Extracts 10 random identities × 3-5 photos each

cd "$(dirname "$0")"

if [ ! -d "lfw" ]; then
  echo "❌ lfw/ directory not found. Run download first."
  exit 1
fi

echo "Preparing test data..."
echo ""

mkdir -p photos

cd lfw
identities=($(ls -d */ | sed 's|/||' | shuf | head -10))

for identity in "${identities[@]}"; do
  echo "  Extracting $identity..."

  photos_dir="../photos/test-lfw-${identity}"
  mkdir -p "$photos_dir"

  # Copy 3-5 photos
  photo_count=0
  for photo in ${identity}/*.jpg; do
    if [ -f "$photo" ] && [ $photo_count -lt 5 ]; then
      cp "$photo" "$photos_dir/"
      ((photo_count++))
    fi
  done

  echo "    ✅ Copied $photo_count photos"
done

cd ..

echo ""
echo "✅ Test data ready"
ls -d photos/test-lfw-*/ | wc -l
echo "identities prepared"
ls photos/test-lfw-*/ | wc -l
echo "photos total"

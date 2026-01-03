#!/bin/bash
set -e

# Remove MLX package dependencies from Xcode project for x86_64 builds

PROJECT="aizen.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT" ]; then
    echo "Error: $PROJECT not found"
    exit 1
fi

# Verify MLX references exist before modification
if ! grep -q "mlx-swift" "$PROJECT"; then
    echo "Error: No MLX references found in project"
    exit 1
fi

INITIAL_MLX_COUNT=$(grep -c "MLX.*in Frameworks\|mlx-swift" "$PROJECT" || echo "0")

# Remove MLX framework references from linking phase (exact line matches)
sed -i.bak '/21DCDAD9BE07D782912A77AD \/\* MLX in Frameworks \*\/,$/d' "$PROJECT"
sed -i.bak '/5C2187920444BE7967808AED \/\* MLXNN in Frameworks \*\/,$/d' "$PROJECT"
sed -i.bak '/72C10A3C810BBB650192A3DC \/\* MLXFFT in Frameworks \*\/,$/d' "$PROJECT"
sed -i.bak '/F023734E9DB882ACB5152A8C \/\* MLX in Frameworks \*\/,$/d' "$PROJECT"
sed -i.bak '/143D01456282D2C9CC8261F8 \/\* MLXNN in Frameworks \*\/,$/d' "$PROJECT"
sed -i.bak '/D40AC0EE6127B8397D78C242 \/\* MLXFFT in Frameworks \*\/,$/d' "$PROJECT"

# Remove package reference from packageReferences array
sed -i.bak '/79EC426B0DCDB46C628589C2 \/\* XCRemoteSwiftPackageReference "mlx-swift" \*\/,$/d' "$PROJECT"

# Remove MLX package product dependency definitions (multi-line blocks)
awk '
BEGIN { skip=0 }
/F9A93A2E8948A4831C8E4835 \/\* MLX \*\/ = \{/ { skip=1; next }
/8A569477FDE9E6427210C021 \/\* MLXNN \*\/ = \{/ { skip=1; next }
/2CE06D116E3316BF792222D8 \/\* MLXFFT \*\/ = \{/ { skip=1; next }
skip && /^\t\t\};$/ { skip=0; next }
!skip { print }
' "$PROJECT" > "$PROJECT.tmp"

if [ ! -s "$PROJECT.tmp" ]; then
    echo "Error: awk processing failed"
    rm -f "$PROJECT.tmp" "$PROJECT.bak"
    exit 1
fi
mv "$PROJECT.tmp" "$PROJECT"

# Remove package reference definition block
awk '
BEGIN { skip=0 }
/79EC426B0DCDB46C628589C2 \/\* XCRemoteSwiftPackageReference "mlx-swift" \*\/ = \{/ { skip=1; next }
skip && /^\t\t\};$/ { skip=0; next }
!skip { print }
' "$PROJECT" > "$PROJECT.tmp"

if [ ! -s "$PROJECT.tmp" ]; then
    echo "Error: awk processing failed"
    rm -f "$PROJECT.tmp" "$PROJECT.bak"
    exit 1
fi
mv "$PROJECT.tmp" "$PROJECT"

rm -f "$PROJECT.bak"

# Verify removal succeeded
FINAL_MLX_COUNT=$(grep -c "MLX.*in Frameworks\|mlx-swift" "$PROJECT" || echo "0")

if [ "$FINAL_MLX_COUNT" -lt "$INITIAL_MLX_COUNT" ]; then
    echo "✓ Removed MLX package and dependencies (reduced from $INITIAL_MLX_COUNT to $FINAL_MLX_COUNT references)"
else
    echo "Warning: MLX reference count unchanged ($INITIAL_MLX_COUNT -> $FINAL_MLX_COUNT)"
fi

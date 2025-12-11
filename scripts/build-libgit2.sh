#!/bin/bash
set -e

LIBGIT2_VERSION="v1.9.1"
LIBSSH2_VERSION="libssh2-1.11.1"
OPENSSL_VERSION="openssl-3.3.2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../Vendor/libgit2"
TMP_DIR="/tmp/libgit2-build-$$"

echo "Building libgit2 $LIBGIT2_VERSION with SSH support..."

# Cleanup any previous build
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Build OpenSSL first (universal binary)
echo "=== Building OpenSSL $OPENSSL_VERSION ==="
cd "$TMP_DIR"
git clone --depth 1 --branch $OPENSSL_VERSION https://github.com/openssl/openssl.git
cd openssl

# Build for arm64
echo "Building OpenSSL for arm64..."
./Configure darwin64-arm64-cc no-shared no-tests --prefix="$TMP_DIR/openssl-arm64" --openssldir="$TMP_DIR/openssl-arm64"
make -j$(sysctl -n hw.ncpu)
make install_sw
make clean

# Build for x86_64
echo "Building OpenSSL for x86_64..."
./Configure darwin64-x86_64-cc no-shared no-tests --prefix="$TMP_DIR/openssl-x86_64" --openssldir="$TMP_DIR/openssl-x86_64"
make -j$(sysctl -n hw.ncpu)
make install_sw

# Create universal OpenSSL libraries
echo "Creating universal OpenSSL libraries..."
mkdir -p "$TMP_DIR/openssl-universal/lib"
mkdir -p "$TMP_DIR/openssl-universal/include"
lipo -create "$TMP_DIR/openssl-arm64/lib/libssl.a" "$TMP_DIR/openssl-x86_64/lib/libssl.a" -output "$TMP_DIR/openssl-universal/lib/libssl.a"
lipo -create "$TMP_DIR/openssl-arm64/lib/libcrypto.a" "$TMP_DIR/openssl-x86_64/lib/libcrypto.a" -output "$TMP_DIR/openssl-universal/lib/libcrypto.a"
cp -r "$TMP_DIR/openssl-arm64/include/openssl" "$TMP_DIR/openssl-universal/include/"

echo "OpenSSL built:"
lipo -info "$TMP_DIR/openssl-universal/lib/libssl.a"
lipo -info "$TMP_DIR/openssl-universal/lib/libcrypto.a"

# Build libssh2
echo ""
echo "=== Building libssh2 $LIBSSH2_VERSION ==="
cd "$TMP_DIR"
git clone --depth 1 --branch $LIBSSH2_VERSION https://github.com/libssh2/libssh2.git
cd libssh2
mkdir build && cd build

cmake .. \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DCRYPTO_BACKEND=OpenSSL \
    -DOPENSSL_ROOT_DIR="$TMP_DIR/openssl-universal" \
    -DOPENSSL_INCLUDE_DIR="$TMP_DIR/openssl-universal/include" \
    -DOPENSSL_SSL_LIBRARY="$TMP_DIR/openssl-universal/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$TMP_DIR/openssl-universal/lib/libcrypto.a" \
    -DCMAKE_INSTALL_PREFIX="$TMP_DIR/libssh2-install"

cmake --build . --config Release
cmake --install .

echo "libssh2 built:"
lipo -info "$TMP_DIR/libssh2-install/lib/libssh2.a"

# Build libgit2
echo ""
echo "=== Building libgit2 $LIBGIT2_VERSION ==="
cd "$TMP_DIR"
git clone --depth 1 --branch $LIBGIT2_VERSION https://github.com/libgit2/libgit2.git
cd libgit2
mkdir build && cd build

# Set CMAKE_PREFIX_PATH so cmake can find our libssh2
export CMAKE_PREFIX_PATH="$TMP_DIR/libssh2-install"
export PKG_CONFIG_PATH=""

cmake .. \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_SSH=ON \
    -DCMAKE_PREFIX_PATH="$TMP_DIR/libssh2-install" \
    -DUSE_HTTPS=SecureTransport \
    -DBUILD_TESTS=OFF \
    -DBUILD_CLI=OFF \
    -DUSE_BUNDLED_ZLIB=ON

cmake --build . --config Release

# Verify universal binary
echo ""
echo "Verifying universal binary..."
lipo -info libgit2.a

# Copy to Vendor
echo ""
echo "Copying to $OUTPUT_DIR..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/lib"
mkdir -p "$OUTPUT_DIR/include"

# Copy all libraries
cp libgit2.a "$OUTPUT_DIR/lib/"
cp "$TMP_DIR/libssh2-install/lib/libssh2.a" "$OUTPUT_DIR/lib/"
cp "$TMP_DIR/openssl-universal/lib/libssl.a" "$OUTPUT_DIR/lib/"
cp "$TMP_DIR/openssl-universal/lib/libcrypto.a" "$OUTPUT_DIR/lib/"

# Copy headers
cp -r ../include/git2 "$OUTPUT_DIR/include/"
cp ../include/git2.h "$OUTPUT_DIR/include/"

# Create module.modulemap with SSH support
cat > "$OUTPUT_DIR/include/module.modulemap" << 'EOF'
module Clibgit2 [system] {
    header "git2.h"
    link "git2"
    link "ssh2"
    link "ssl"
    link "crypto"
    link "z"
    link "iconv"
    export *
}
EOF

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "libgit2 $LIBGIT2_VERSION with SSH support built successfully!"
echo "Location: $OUTPUT_DIR"
echo ""
echo "Files:"
ls -la "$OUTPUT_DIR/lib/"
echo ""
echo "All dependencies are statically linked - no external OpenSSL required!"

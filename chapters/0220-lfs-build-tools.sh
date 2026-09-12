#!/bin/sh
# Copyright (c) 2026 REVYTECH, Inc.
# SPDX-License-Identifier: BSD-3-Clause
#
# chapters/0220-lfs-build-tools.sh — gettext, Python, ninja, meson, cmake
# into $LFS (cross from Alpine builder). Needed before Qt6 / Plasma.
set -eu
: "${LFS:?LFS root DESTDIR must be set}"
: "${LF_CHAPTER_ID:=0220}"

LFS_TGT="${LFS_TGT:-x86_64-lfs-linux-gnu}"
VENDOR="${LF_VENDOR:-/mnt/lfs/vendor}"
BUILD_ROOT="${LF_BUILD_ROOT:-/var/tmp/lfs-build}"
JOBS="${LF_JOBS:-$(nproc 2>/dev/null || echo 2)}"
export PATH="$LFS/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

echo "=== chapter ${LF_CHAPTER_ID}: LFS build tools (gettext/python/cmake/…) ==="
[ -x "$LFS/tools/bin/${LFS_TGT}-gcc" ] || {
	echo "cross gcc required in \$LFS/tools" >&2
	exit 1
}

export CC="${LFS_TGT}-gcc" CXX="${LFS_TGT}-g++"
export AR="${LFS_TGT}-ar" RANLIB="${LFS_TGT}-ranlib"
export CFLAGS="${CFLAGS:--g -O2} -Wno-implicit-function-declaration"
export CXXFLAGS="${CXXFLAGS:--g -O2}"
if [ -x "$LFS/usr/bin/pkgconf" ]; then
	export PKG_CONFIG="$LFS/usr/bin/pkgconf"
	export PKG_CONFIG_LIBDIR="$LFS/usr/lib/pkgconfig:$LFS/usr/share/pkgconfig"
	export PKG_CONFIG_SYSROOT_DIR="$LFS"
fi

extract() {
	name="$1"
	tarball="$2"
	[ -f "$VENDOR/$tarball" ] || {
		echo "missing $VENDOR/$tarball" >&2
		return 1
	}
	rm -rf "$BUILD_ROOT/$name"
	mkdir -p "$BUILD_ROOT/$name"
	tar -C "$BUILD_ROOT/$name" --strip-components=1 -xf "$VENDOR/$tarball"
}

if [ -x "$LFS/usr/bin/gettext" ]; then
	echo "--- skip gettext (already installed) ---"
else
	echo "--- building gettext ---"
	extract gettext gettext-0.24.tar.xz
	cd "$BUILD_ROOT/gettext"
	./configure --prefix=/usr --host="$LFS_TGT" \
		--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
		--disable-static --disable-java --disable-csharp \
		--docdir=/usr/share/doc/gettext-0.24
	make -j"$JOBS"
	make DESTDIR="$LFS" install
	cd /
	rm -rf "$BUILD_ROOT/gettext"
fi

if [ -x "$LFS/usr/bin/python3" ]; then
	echo "--- skip Python (already installed) ---"
else
echo "--- building Python ---"
extract python Python-3.13.2.tar.xz
# Cross builds require a same-version *build* interpreter. Alpine ships 3.12,
# so bootstrap a host Python 3.13 first (native musl gcc).
HOST_PY_PREFIX="$BUILD_ROOT/host-python-3.13"
HOST_PY="$HOST_PY_PREFIX/bin/python3"
if [ ! -x "$HOST_PY" ]; then
	echo "--- bootstrapping host Python 3.13 for cross ---"
	rm -rf "$BUILD_ROOT/python-host"
	mkdir -p "$BUILD_ROOT/python-host"
	tar -C "$BUILD_ROOT/python-host" --strip-components=1 -xf "$VENDOR/Python-3.13.2.tar.xz"
	cd "$BUILD_ROOT/python-host"
	CC=gcc CXX=g++ AR=ar RANLIB=ranlib \
		./configure --prefix="$HOST_PY_PREFIX" --enable-shared --without-ensurepip
	make -j"$JOBS"
	make install
	cd /
	rm -rf "$BUILD_ROOT/python-host"
fi
cd "$BUILD_ROOT/python"
# Host libpython must be visible while regenerating freeze modules.
export LD_LIBRARY_PATH="$HOST_PY_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
./configure --prefix=/usr --host="$LFS_TGT" \
	--build="$(./config.guess 2>/dev/null || echo x86_64-pc-linux-musl)" \
	--enable-shared --without-ensurepip \
	--with-build-python="$HOST_PY" \
	ac_cv_buggy_getaddrinfo=no \
	ac_cv_file__dev_ptmx=yes \
	ac_cv_file__dev_ptc=no
make -j"$JOBS"
make DESTDIR="$LFS" install
cd /
rm -rf "$BUILD_ROOT/python"
fi

if [ -x "$LFS/usr/bin/ninja" ]; then
	echo "--- skip ninja (already installed) ---"
else
	echo "--- building ninja ---"
	extract ninja ninja-1.12.1.tar.gz
	cd "$BUILD_ROOT/ninja"
	# Bootstrap must use the *host* toolchain (CXX is the cross compiler).
	(
		unset CC CXX AR RANLIB CFLAGS CXXFLAGS LDFLAGS
		python3 configure.py --bootstrap
	)
	mv -f ninja ninja.host
	# Rebuild for the LFS target; static libgcc avoids _Unwind_* DSO clashes.
	CXX="$CXX" AR="$AR" \
		CFLAGS="-O2" CXXFLAGS="-O2" \
		LDFLAGS="-static-libgcc -static-libstdc++" \
		python3 configure.py
	./ninja.host -j"$JOBS"
	install -d "$LFS/usr/bin"
	install -m755 ninja "$LFS/usr/bin/ninja"
	cd /
	rm -rf "$BUILD_ROOT/ninja"
fi

if [ -x "$LFS/usr/bin/meson" ]; then
	echo "--- skip meson (already installed) ---"
else
	echo "--- installing meson ---"
	extract meson meson-1.7.0.tar.gz
	cd "$BUILD_ROOT/meson"
	install -d "$LFS/usr/lib/meson-1.7.0" "$LFS/usr/bin"
	cp -a mesonbuild "$LFS/usr/lib/meson-1.7.0/"
	cp meson.py "$LFS/usr/lib/meson-1.7.0/"
	cat >"$LFS/usr/bin/meson" <<'EOF'
#!/usr/bin/env python3
import runpy, sys
sys.path.insert(0, "/usr/lib/meson-1.7.0")
sys.exit(runpy.run_path("/usr/lib/meson-1.7.0/meson.py", run_name="__main__"))
EOF
	chmod 755 "$LFS/usr/bin/meson"
	cd /
	rm -rf "$BUILD_ROOT/meson"
fi

if [ -x "$LFS/usr/bin/cmake" ]; then
	echo "--- skip cmake (already installed) ---"
else
	echo "--- building cmake (cross via host cmake) ---"
	command -v cmake >/dev/null 2>&1 || apk add --no-cache cmake
	extract cmake cmake-3.31.6.tar.gz
	rm -rf "$BUILD_ROOT/cmake-build"
	mkdir -p "$BUILD_ROOT/cmake-build"
	cd "$BUILD_ROOT/cmake-build"
	# tools g++ (pass1) has --disable-threads, so its <mutex> has no std::mutex.
	# gcc pass2 installed a threaded libstdc++ under $LFS/usr — use those
	# headers (-nostdinc++) while still driving the tools cross compiler.
	# Also force static libstdc++/libgcc: tools g++ was --disable-shared.
	CXX_VER="$("$CXX" -dumpversion)"
	CXX_DEST_FLAGS="-nostdinc++"
	CXX_DEST_FLAGS="$CXX_DEST_FLAGS -isystem $LFS/usr/include/c++/$CXX_VER"
	CXX_DEST_FLAGS="$CXX_DEST_FLAGS -isystem $LFS/usr/include/c++/$CXX_VER/$LFS_TGT"
	CXX_DEST_FLAGS="$CXX_DEST_FLAGS -isystem $LFS/usr/include/c++/$CXX_VER/backward"
	CXX_DEST_FLAGS="$CXX_DEST_FLAGS -isystem $LFS/usr/include"
	cmake "$BUILD_ROOT/cmake" \
		-DCMAKE_SYSTEM_NAME=Linux \
		-DCMAKE_SYSTEM_PROCESSOR=x86_64 \
		-DCMAKE_C_COMPILER="$CC" \
		-DCMAKE_CXX_COMPILER="$CXX" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_FIND_ROOT_PATH="$LFS" \
		-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
		-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
		-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
		-DCMAKE_C_FLAGS="-O2" \
		-DCMAKE_CXX_FLAGS="-O2 $CXX_DEST_FLAGS -static-libstdc++ -static-libgcc" \
		-DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
		-DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
		-DCMAKE_USE_SYSTEM_ZLIB=ON \
		-DBUILD_TESTING=OFF \
		-DCMake_ENABLE_DEBUGGER=OFF \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build . -j"$JOBS"
	DESTDIR="$LFS" cmake --install .
	cd /
	rm -rf "$BUILD_ROOT/cmake" "$BUILD_ROOT/cmake-build"
fi

[ -x "$LFS/usr/bin/python3" ] || {
	echo "ERROR: python3 missing from DESTDIR" >&2
	exit 1
}
[ -x "$LFS/usr/bin/ninja" ] || {
	echo "ERROR: ninja missing from DESTDIR" >&2
	exit 1
}
[ -x "$LFS/usr/bin/cmake" ] || {
	echo "ERROR: cmake missing from DESTDIR" >&2
	exit 1
}

mkdir -p "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}"
touch "${LF_CHAPTER_STATE:-/var/tmp/lfs-chapters}/${LF_CHAPTER_ID}.done"
echo "=== chapter ${LF_CHAPTER_ID} done ==="

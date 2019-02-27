#!/bin/bash

version=1.69.0
echo "Building boost $version..."

while getopts "a:c:" opt; do
  case $opt in
    a)
	ARCH=$OPTARG ;;
    c)
	FLAVOR=$OPTARG ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [[ -z "${ARCH}" ]] ; then
	echo 'You need to input arch with -a ARCH.'
	echo 'Supported archs are:'
	echo -e '\tarm arm64 x86 x86_64'
	exit 1
fi

LOCAL_PATH=$(readlink -f .)
NDK_PATH=$(dirname "$(which ndk-build)")
NDK_VERSION=r19-beta2

if [ -z ${NDK_PATH} ] || [ ! -d ${NDK_PATH} ] || [ ${NDK_PATH} == . ]; then
    NDK_NAME="android-ndk-${NDK_VERSION}"
	if [ -d ~/"${NDK_NAME}" ]; then
        echo 'using home ndk'
        NDK_PATH=$(readlink -f ~/"${NDK_NAME}")
        else
        if [ ! -d "${NDK_NAME}" ]; then
		    echo "downloading android ndk ${NDK_NAME}..."
		    wget https://dl.google.com/android/repository/${NDK_NAME}-linux-x86_64.zip
		    unzip "${NDK_NAME}-linux-x86_64.zip"
		    rm -f "${NDK_NAME}-linux-x86_64.zip"
	    fi
	    echo 'using integrated ndk'
	    NDK_PATH=$(readlink -f "${NDK_NAME}")
     fi
fi

ANDROID_API=21

ARCH_CONFIG_OPT=

case "${ARCH}" in
	'arm')
		ARCH_TRIPLET='arm-linux-androideabi'
        ARCH_TRIPLET_VARIANT='armv7a-linux-androideabi'
		ABI='armeabi-v7a'
		ARCH_CFLAGS='-march=armv7-a -mfpu=neon -mfloat-abi=softfp -mthumb'
		ARCH_LDFLAGS='-march=armv7-a -Wl,--fix-cortex-a8'
        B_ARCH='arm' 
        B_ADDRESS_MODEL=32 ;;
	'arm64')
		ARCH_TRIPLET='aarch64-linux-android'
        ARCH_TRIPLET_VARIANT=$ARCH_TRIPLET
		ABI='arm64-v8a'
		B_ARCH='arm'     
        B_ADDRESS_MODEL=64 ;;
    'x86')
		ARCH_TRIPLET='i686-linux-android'
        ARCH_TRIPLET_VARIANT=$ARCH_TRIPLET
		ARCH_CONFIG_OPT='--disable-asm'
		ARCH_CFLAGS='-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32'
		ABI='x86' 
        B_ARCH='x86'        
        B_ADDRESS_MODEL=32 ;;
    'x86_64')
		ARCH_TRIPLET='x86_64-linux-android'
        ARCH_TRIPLET_VARIANT=$ARCH_TRIPLET
		ABI='x86_64'
		ARCH_CFLAGS='-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel'
		B_ARCH='x86'        
        B_ADDRESS_MODEL=64 ;;
	*)
		echo "Arch ${ARCH} is not supported."
		exit 1 ;;
esac

os=$(uname -s | tr '[:upper:]' '[:lower:]')
CROSS_PREFIX="${NDK_PATH}"/toolchains/llvm/prebuilt/${os}-x86_64/bin

set -eu

dir_name=boost_$(sed 's#\.#_#g' <<< $version)
archive=${dir_name}.tar.bz2
if [ ! -f "$archive" ]; then
  wget -O $archive "https://dl.bintray.com/boostorg/release/$version/source/$archive"
else
  echo "Archive $archive already downloaded"
fi

echo "Extracting..."
if [ ! -d "$dir_name" ]; then
  # rm -rf $dir_name
  tar xf $archive
else
  echo "Archive $archive already unpacked into $dir_name"
fi
if [ ! -d "${dir_name}-${ABI}" ]; then
  mv $dir_name ${dir_name}-${ABI}
  dir_name=${dir_name}-${ABI}
  cd $dir_name
else
  echo "Already built for ${ABI}"
  exit 0
fi

echo "Generating config..."
user_config=tools/build/src/user-config.jam
rm -f $user_config
cat <<EOF > $user_config
import os ;

using clang : android
:
"${CROSS_PREFIX}/${ARCH_TRIPLET_VARIANT}${ANDROID_API}-clang++"
:
<archiver>${CROSS_PREFIX}/${ARCH_TRIPLET}-ar
<ranlib>${CROSS_PREFIX}/${ARCH_TRIPLET}-ranlib
;
EOF

echo "Bootstrapping..."
./bootstrap.sh #--with-toolset=clang

echo "Building..."
./b2 -j32 \
    --with-atomic \
    --with-chrono \
    --with-container \
    --with-date_time \
    --with-exception \
    --with-fiber \
    --with-filesystem \
    --with-graph \
    --with-graph_parallel \
    --with-iostreams \
    --with-locale \
    --with-log \
    --with-math \
    --with-mpi \
    --with-program_options \
    --with-random \
    --with-regex \
    --with-serialization \
    --with-system \
    --with-test \
    --with-thread \
    --with-timer \
    --with-type_erasure \
    --with-wave \
    toolset=clang-android \
    architecture=${B_ARCH} \
    address-model=${B_ADDRESS_MODEL}
    variant=release \
    --layout=versioned \
    target-os=android \
    threading=multi \
    threadapi=pthread \
    link=static \
    runtime-link=static \
    install || true


echo "Running ranlib on libraries..."
libs=$(find "bin.v2/libs/" -name '*.a')
for lib in $libs; do
  "${CROSS_PREFIX}ranlib" "$lib"
done

echo "Done!"

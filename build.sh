#!/bin/bash

version=1.72.0
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

if [ -z "${ARCH}" ]
then
  echo 'You need to input arch with -a ARCH.'
  echo 'Supported archs are:'
  echo -e '\tarm arm64 x86 x86_64'
  exit 1
fi

LOCAL_PATH=$(readlink -f .)

# android sdk directory is changing
[ -n "${ANDROID_HOME}" ] && androidSdk=${ANDROID_HOME}
[ -n "${ANDROID_SDK_ROOT}" ] && androidSdk=${ANDROID_SDK_ROOT}
# multiple sdkmanager paths
export PATH=${androidSdk}/cmdline-tools/tools/bin:${androidSdk}/tools/bin:$PATH
[ ! -d "${androidSdk}/ndk-bundle" -a ! -d "${androidSdk}/ndk" ] && sdkmanager ndk-bundle
[ -d "${androidSdk}/ndk" ] && NDK_PATH=$(ls -d ${androidSdk}/ndk/* | sort -V | tail -n 1)
[ -d "${androidSdk}/ndk-bundle" ] && NDK_PATH=${androidSdk}/ndk-bundle
echo NDK_PATH is ${NDK_PATH}

ANDROID_API=24

ARCH_CONFIG_OPT=

case "${ARCH}" in
  'arm')
    ARCH_TRIPLET='arm-linux-androideabi'
    ARCH_TRIPLET_VARIANT='armv7a-linux-androideabi'
    ABI='armeabi-v7a'
    ARCH_CFLAGS='-march=armv7-a -mfpu=neon -mfloat-abi=softfp -mthumb'
    ARCH_LDFLAGS='-march=armv7-a -Wl,--fix-cortex-a8'
    B_ARCH='arm'
    B_ABI='aapcs'
    B_ADDRESS_MODEL=32 ;;
  'arm64')
    ARCH_TRIPLET='aarch64-linux-android'
    ARCH_TRIPLET_VARIANT=$ARCH_TRIPLET
    ABI='arm64-v8a'
    B_ARCH='arm'
    B_ABI='aapcs'
    B_ADDRESS_MODEL=64 ;;
  'x86')
    ARCH_TRIPLET='i686-linux-android'
    ARCH_TRIPLET_VARIANT=$ARCH_TRIPLET
    ARCH_CONFIG_OPT='--disable-asm'
    ARCH_CFLAGS='-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32'
    ABI='x86' 
    B_ARCH='x86'
    B_ABI='sysv'
    B_ADDRESS_MODEL=32 ;;
  'x86_64')
    ARCH_TRIPLET='x86_64-linux-android'
    ARCH_TRIPLET_VARIANT=$ARCH_TRIPLET
    ABI='x86_64'
    ARCH_CFLAGS='-march=x86-64 -msse4.2 -mpopcnt -m64 -mtune=intel'
    B_ARCH='x86'
    B_ABI='sysv'
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
if [ ! -f "$archive" ]
then
  wget -O $archive "https://dl.bintray.com/boostorg/release/$version/source/$archive"
else
  echo "Archive $archive already downloaded"
fi

echo "Extracting..."
if [ ! -d "$dir_name" ]
then
  # rm -rf $dir_name
  tar xf $archive
else
  echo "Archive $archive already unpacked into $dir_name"
fi
[ ! -d "${dir_name}-${ABI}" ] && mkdir -p ${dir_name}-${ABI}/stage

cd $dir_name

user_config=../${dir_name}-${ABI}/user-config.jam
if [ ! -f "$user_config" ]; then
echo "Generating config..."
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
fi

if [ ! -f b2 ]
then
  echo "Bootstrapping..."
  ./bootstrap.sh #--with-toolset=clang
fi

echo "Building..."
./b2 -j4 \
    -a -q \
    --with-system \
    --layout=system \
    --build-dir=../${dir_name}-${ABI} \
    --stagedir=../${dir_name}-${ABI}/stage \
    --user-config=${user_config} \
    target-os=android \
    toolset=clang-android \
    architecture=${B_ARCH} \
    address-model=${B_ADDRESS_MODEL} \
    abi=${B_ABI} \
    binary-format=elf \
    variant=release \
    threading=multi \
    threadapi=pthread \
    link=static \
    runtime-link=static \
    stage


echo "Running ranlib on libraries..."
libs=$(find "../${dir_name}-${ABI}/boost/bin.v2/libs" -name '*.a')
for lib in $libs
do
  "${CROSS_PREFIX}/${ARCH_TRIPLET}-ranlib" "$lib"
done

echo "Done!"

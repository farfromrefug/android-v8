#!/bin/bash 
set -x

case $(uname | tr '[:upper:]' '[:lower:]') in
  linux*)
    export OS_NAME=linux
    ;;
  darwin*)
    export OS_NAME=darwin
    ;;
  msys*)
    export OS_NAME=windows
    ;;
  *)
    export OS_NAME=notset
    ;;
esac

GCLIENT_SYNC_ARGS="--reset --with_branch_head"
while getopts 'r:s' opt; do
  case ${opt} in
    r)
      GCLIENT_SYNC_ARGS+=" --revision ${OPTARG}"
      ;;
    s)
      GCLIENT_SYNC_ARGS+=" --no-history"
      ;;
  esac
done
shift $(expr ${OPTIND} - 1)

source $(dirname $0)/env.sh
GCLIENT_SYNC_ARGS+=" --revision $V8_VERSION"

function verify_platform()
{
  local arg=$1
  SUPPORTED_PLATFORMS=(android ios)
  local valid_platform=
  for platform in ${SUPPORTED_PLATFORMS[@]}
  do
    if [[ ${arg} = ${platform} ]]; then
      valid_platform=${platform}
    fi
  done
  if [[ -z ${valid_platform} ]]; then
    echo "Invalid platfrom: ${arg}" >&2
    exit 1
  fi
  echo ${valid_platform}
}

# Install NDK
function installNDK() {
  pushd .
  cd "${V8_DIR}"
  if [[ ! -d " android-ndk-${NDK_VERSION}" ]]; then
    FILENAME="android-ndk-${NDK_VERSION}-${OS_NAME}.zip"
    wget -q https://dl.google.com/android/repository/${FILENAME}
    unzip -q ${FILENAME}
    rm -f${FILENAME}
  fi
  popd
  ls -d ${V8_DIR}
}

if [[ ! -d "${DEPOT_TOOLS_DIR}" || ! -f "${DEPOT_TOOLS_DIR}/gclient" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "${DEPOT_TOOLS_DIR}"
fi

gclient config --name v8 --unmanaged "https://chromium.googlesource.com/v8/v8.git"

if [[ "$1" = "" ]]; then
  gclient sync ${GCLIENT_SYNC_ARGS}
  exit 0
fi
PLATFORM=$(verify_platform $1)

if [[ ${PLATFORM} = "ios" ]]; then
  gclient sync --deps=ios ${GCLIENT_SYNC_ARGS}

  cd "${V8_DIR}/tools/clang/dsymutil"
  curl -O http://commondatastorage.googleapis.com/chromium-browser-clang-staging/Mac/dsymutil-354873-1.tgz
  tar -zxvf dsymutil-354873-1.tgz
  # Apply N Patches
  patch -d "${V8_DIR}" -p1 < "${PATCHES_DIR}/ios/main.patch"
  exit 0
fi

if [[ ${PLATFORM} = "android" ]]; then
  gclient sync --deps=android ${GCLIENT_SYNC_ARGS}

  # Patch build-deps installer for snapd not available in docker
  patch -d "${V8_DIR}" -p1 < "${PATCHES_DIR}/prebuild_no_snapd.patch"

  sudo bash -c 'v8/build/install-build-deps-android.sh'

  # Reset changes after installation
  patch -d "${V8_DIR}" -p1 -R < "${PATCHES_DIR}/prebuild_no_snapd.patch"

  # Workaround to install missing sysroot
  gclient sync

  # Workaround to install missing android_sdk tools
  gclient sync --deps=android ${GCLIENT_SYNC_ARGS}

  # Apply N Patches
  patch -d "${V8_DIR}" -p1 < "${PATCHES_DIR}/android/main.patch"
  # patch -d "${V8_DIR}" -p1 < "${PATCHES_DIR}/android/main.patch"

  installNDK
  exit 0
fi

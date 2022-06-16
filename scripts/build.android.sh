#!/bin/bash -e
source $(dirname $0)/env.sh

ARCH_ARR=(arm arm64 x86 x64)
while getopts 'l:' opt; do
  case ${opt} in
    l)
        ARCH_ARR=($OPTARG)
      ;;
  esac
done
shift $(expr ${OPTIND} - 1)
## prepare configuration


declare -A NDK_BUILD_TOOLS_ARR
if [ "$(uname)" == "Darwin" ]; then
        NDK_BUILD_TOOLS_ARR=$ANDROID_NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin
else
        NDK_BUILD_TOOLS_ARR=$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
fi


declare -A OUTPUT_FOLDERNAMES

OUTPUT_FOLDERNAMES[arm]=armeabi-v7a
OUTPUT_FOLDERNAMES[arm64]=arm64-v8a
OUTPUT_FOLDERNAMES[x86]=x86
OUTPUT_FOLDERNAMES[x64]=x86_64

# The order of CPU architectures in this array must be the same
# as the order of NDK tools in the NDK_BUILD_TOOLS_ARR array

BUILD_DIR_PREFIX="outgn"

BUILD_TYPE="release"

cd ${V8_DIR}
if [[ $1 == "debug" ]] ;then
        BUILD_TYPE="debug"
fi
# generate project in release mode
for CURRENT_ARCH in ${ARCH_ARR[@]}
do
        if [[ $BUILD_TYPE == "debug" ]] ;then
                ARGS="use_custom_libcxx=true use_goma=false is_clang=true enable_resource_allowlist_generation=false is_component_build=true v8_use_external_startup_data=false is_official_build=true use_thin_lto=false is_debug=true symbol_level=2 target_cpu=\"$CURRENT_ARCH\" v8_target_cpu=\"$CURRENT_ARCH\" v8_enable_i18n_support=false target_os=\"android\" v8_android_log_stdout=false cc_wrapper=\"ccache\""
        else
                ARGS="use_custom_libcxx=true use_goma=false is_clang=true enable_resource_allowlist_generation=false is_component_build=true v8_use_external_startup_data=false is_official_build=true use_thin_lto=false is_debug=false symbol_level=0 target_cpu=\"$CURRENT_ARCH\" v8_target_cpu=\"$CURRENT_ARCH\" v8_enable_i18n_support=false target_os=\"android\" v8_android_log_stdout=false cc_wrapper=\"ccache\""
        fi
        gn gen $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE --args="$ARGS  android32_ndk_api_level=$NDK_API_LEVEL android_ndk_major_version=$NDK_MAJOR_VERSION android_sdk_platform_version=$ANDROID_SDK_PLATFORM_VERSION android_sdk_build_tools_version=\"$ANDROID_SDK_BUILD_TOOLS_VERSION\"  android_sdk_version=$ANDROID_SDK_PLATFORM_VERSION android64_ndk_api_level=$NDK_64_API_LEVEL"
done

# compile project
for CURRENT_ARCH in ${ARCH_ARR[@]}
do
        echo "building $CURRENT_ARCH for $BUILD_TYPE"

        # make fat build
        V8_FOLDERS=(v8_base_without_compiler v8_bigint v8_compiler v8_heap_base v8_libbase v8_libplatform v8_snapshot v8_turboshaft torque_generated_initializers torque_generated_definitions)
        export CCACHE_CPP2=yes
	export CCACHE_SLOPPINESS=time_macros
	export PATH=$V8_DIR/third_party/llvm-build/Release+Asserts/bin:$PATH
        SECONDS=0
        ninja -C $BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE ${V8_FOLDERS[@]} inspector

        echo "build finished in $SECONDS seconds"


        OUTFOLDER=${BUILD_DIR_PREFIX}/${CURRENT_ARCH}-${BUILD_TYPE}
        CURRENT_BUILD_TOOL=${NDK_BUILD_TOOLS_ARR}
        OUTPUT_FOLDERNAME=${OUTPUT_FOLDERNAMES[$CURRENT_ARCH]}
        V8_FOLDERS_LEN=${#V8_FOLDERS[@]}
        LAST_PARAM=""
        CURRENT_DIST_DIR="$DIST_DIR/$BUILD_TYPE/$OUTPUT_FOLDERNAME"
        CURRENT_DIST_DIR_INCLUDES="$DIST_DIR/$BUILD_TYPE/"
        echo "CURRENT_ARCH $CURRENT_ARCH"
        echo "OUTPUT_FOLDERNAME $OUTPUT_FOLDERNAME"
        echo "CURRENT_BUILD_TOOL $CURRENT_BUILD_TOOL"
        echo "CURRENT_DIST_DIR $CURRENT_DIST_DIR"
        echo "CURRENT_DIST_DIR_INCLUDES $CURRENT_DIST_DIR_INCLUDES"
        # echo "ar $CURRENT_BUILD_TOOL"

        mkdir -p $CURRENT_DIST_DIR

        for CURRENT_V8_FOLDER in ${V8_FOLDERS[@]}
        do
        LAST_PARAM="${LAST_PARAM} ${OUTFOLDER}/obj/${CURRENT_V8_FOLDER}/*.o"
        done

        $CURRENT_BUILD_TOOL/llvm-ar r $CURRENT_DIST_DIR/libinspector_protocol.a $OUTFOLDER/obj/third_party/inspector_protocol/crdtp/*.o $OUTFOLDER/obj/third_party/inspector_protocol/crdtp_platform/*.o
        $CURRENT_BUILD_TOOL/llvm-ranlib $CURRENT_DIST_DIR/libinspector_protocol.a

        LAST_PARAM="${LAST_PARAM} $OUTFOLDER/obj/third_party/zlib/zlib/*.o ${OUTFOLDER}/obj/third_party/zlib/zlib/*.o ${OUTFOLDER}/obj/third_party/zlib/zlib_adler32_simd/*.o ${OUTFOLDER}/obj/third_party/zlib/google/compression_utils_portable/*.o ${OUTFOLDER}/obj/third_party/zlib/zlib_inflate_chunk_simd/*.o"

        LAST_PARAM="${LAST_PARAM} ${OUTFOLDER}/obj/third_party/android_ndk/cpu_features/*.o"
        LAST_PARAM="${LAST_PARAM} ${OUTFOLDER}/obj/cppgc_base/*.o"
        
        if [[ $CURRENT_ARCH = "arm" || $CURRENT_ARCH = "arm64" ]]; then
                LAST_PARAM="${LAST_PARAM} ${OUTFOLDER}/obj/third_party/zlib/zlib_arm_crc32/*.o"
        fi

        if [[ $CURRENT_ARCH = "x86" || $CURRENT_ARCH = "x64" ]]; then
                LAST_PARAM="${LAST_PARAM} ${OUTFOLDER}/obj/third_party/zlib/zlib_crc32_simd/*.o"
        fi

        THIRD_PARTY_OUT=$BUILD_DIR_PREFIX/$CURRENT_ARCH-$BUILD_TYPE/obj/buildtools/third_party
        LAST_PARAM="${LAST_PARAM} $THIRD_PARTY_OUT/libc++/libc++/*.o $THIRD_PARTY_OUT/libc++abi/libc++abi/*.o"
        
        # echo "$CURRENT_BUILD_TOOL/llvm-ar r $CURRENT_DIST_DIR/libv8.a ${LAST_PARAM}"
        $CURRENT_BUILD_TOOL/llvm-ar r $CURRENT_DIST_DIR/libv8.a ${LAST_PARAM}
        
        # include files
        rsync -r --exclude '.git' --exclude '.cache' --exclude 'DEPS' --exclude 'DIR_METADATA' "$V8_DIR/include/" "$CURRENT_DIST_DIR_INCLUDES/include/"
        rsync -r --exclude '.git' --exclude '.git' "${OUTFOLDER}/gen/include/" "$CURRENT_DIST_DIR_INCLUDES/include/"
        # rsync -r --exclude '.git' --exclude '.git' "$V8_DIR/third_party/googletest/src/googletest/include/" "$CURRENT_DIST_DIR_INCLUDES/include/testing/gtest/include/"
        rsync -r --exclude '.git' --exclude '.git' "$V8_DIR/buildtools/third_party/libc++/trunk/include/" "$CURRENT_DIST_DIR_INCLUDES/include/libc++/"
        
        # generated files
        rsync -r --exclude '.git' --exclude '*.cache' --exclude 'snapshot.cc' --exclude 'embedded.S' "${OUTFOLDER}/gen/" "$CURRENT_DIST_DIR_INCLUDES/generated/"
        
        mkdir -p "$CURRENT_DIST_DIR_INCLUDES/v8_inspector"
        INSPECTOR_LIST=($(grep "\"+.*\""  $V8_DIR/src/inspector/DEPS | sed 's/[+,"]//g'))
        # remove last one ../../third_party/inspector_protocol/crdtp
        unset INSPECTOR_LIST[-1]
	INSPECTOR_LIST+=("base/trace_event")
	INSPECTOR_LIST+=("src/base")
	INSPECTOR_LIST+=("src/common")
        rsync -auR --exclude '.git' --exclude '*.cache' --exclude 'DEPS' --exclude 'DIR_METADATA'  --exclude 'OWNERS' --exclude 'BUILD.gn' "${INSPECTOR_LIST[@]}" "$CURRENT_DIST_DIR_INCLUDES/v8_inspector/"
        rsync -ur --exclude '.git' --exclude '*.cache' --exclude 'DEPS' --exclude 'DIR_METADATA'  --exclude 'OWNERS' --exclude 'BUILD.gn' "$CURRENT_DIST_DIR_INCLUDES/generated/src/" "$CURRENT_DIST_DIR_INCLUDES/v8_inspector/src/"
        echo "done $CURRENT_ARCH"
done

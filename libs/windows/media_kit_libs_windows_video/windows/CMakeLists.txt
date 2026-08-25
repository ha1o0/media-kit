# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)
cmake_policy(SET CMP0175 NEW)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_libmpv_extraction dir result_var)
  set(required_files
    "${dir}/libmpv-2.dll"
    "${dir}/libmpv.dll.a"
    "${dir}/include/client.h"
    "${dir}/include/render.h"
    "${dir}/include/render_d3d11.h"
  )
  set(is_valid TRUE)

  foreach(required_file IN LISTS required_files)
    if(NOT EXISTS "${required_file}")
      set(is_valid FALSE)
      message(STATUS "Required libmpv file is missing: ${required_file}")
    endif()
  endforeach()

  set(${result_var} ${is_valid} PARENT_SCOPE)
endfunction()

# Detect architecture and set appropriate libmpv archive
if(${FLUTTER_TARGET_PLATFORM} STREQUAL "windows-x64")
  set(LIBMPV_ARCH "x86_64")
  set(LIBMPV "mpv-dev-x86_64-20260825-git-8c8ec83.7z")
  set(LIBMPV_MD5 "5dab5115423f5b3a6af2cd63eb75881d")
else()
  set(LIBMPV_ARCH "aarch64")
  set(LIBMPV "mpv-dev-aarch64-20260219-git-d93c669.7z")
  set(LIBMPV_MD5 "0612bbd955aca27ef6f7052db852727d")
endif()

# Download URL for the libmpv archive from the latest release.
set(LIBMPV_URL "https://github.com/bota-official/bota/releases/download/v0.5.6/${LIBMPV}")

# Local testing override. Drop a matching mpv-dev-<arch>-*.7z into this folder,
# or pass -DMEDIA_KIT_LIBMPV_LOCAL_ARCHIVE=/path/to/mpv-dev-<arch>-*.7z.
set(MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE "" CACHE FILEPATH "Local libmpv .7z archive for Windows video testing.")
set(MEDIA_KIT_LIBMPV_LOCAL_DIR "${CMAKE_CURRENT_LIST_DIR}/local_libmpv" CACHE PATH "Directory containing local libmpv .7z archives.")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
set(LIBMPV_STAMP "${LIBMPV_SRC}/.media_kit_libmpv_archive")
set(LIBMPV_SOURCE "remote")

if(MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE)
  get_filename_component(MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_ABS "${MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE}" ABSOLUTE)

  if(NOT EXISTS "${MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_ABS}")
    message(FATAL_ERROR "MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE does not exist: ${MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_ABS}")
  endif()

  set(LIBMPV_SOURCE "local")
  set(LIBMPV_ARCHIVE "${MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_ABS}")
else()
  file(GLOB MEDIA_KIT_LIBMPV_LOCAL_ARCHIVES CONFIGURE_DEPENDS "${MEDIA_KIT_LIBMPV_LOCAL_DIR}/mpv-dev-${LIBMPV_ARCH}-*.7z")

  if(MEDIA_KIT_LIBMPV_LOCAL_ARCHIVES)
    list(LENGTH MEDIA_KIT_LIBMPV_LOCAL_ARCHIVES MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_COUNT)
    set(MEDIA_KIT_LIBMPV_SELECTED_ARCHIVE "")
    set(MEDIA_KIT_LIBMPV_SELECTED_TIMESTAMP "")

    foreach(MEDIA_KIT_LIBMPV_CANDIDATE IN LISTS MEDIA_KIT_LIBMPV_LOCAL_ARCHIVES)
      file(TIMESTAMP "${MEDIA_KIT_LIBMPV_CANDIDATE}" MEDIA_KIT_LIBMPV_CANDIDATE_TIMESTAMP "%Y%m%d%H%M%S" UTC)

      if(NOT MEDIA_KIT_LIBMPV_SELECTED_ARCHIVE OR MEDIA_KIT_LIBMPV_CANDIDATE_TIMESTAMP STRGREATER MEDIA_KIT_LIBMPV_SELECTED_TIMESTAMP)
        set(MEDIA_KIT_LIBMPV_SELECTED_ARCHIVE "${MEDIA_KIT_LIBMPV_CANDIDATE}")
        set(MEDIA_KIT_LIBMPV_SELECTED_TIMESTAMP "${MEDIA_KIT_LIBMPV_CANDIDATE_TIMESTAMP}")
      endif()
    endforeach()

    set(LIBMPV_ARCHIVE "${MEDIA_KIT_LIBMPV_SELECTED_ARCHIVE}")

    if(MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_COUNT GREATER 1)
      message(STATUS "Found ${MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE_COUNT} local libmpv archives in ${MEDIA_KIT_LIBMPV_LOCAL_DIR}; using newest modified archive ${LIBMPV_ARCHIVE}. Set MEDIA_KIT_LIBMPV_LOCAL_ARCHIVE to choose explicitly.")
    endif()

    set(LIBMPV_SOURCE "local")
  endif()
endif()

if(LIBMPV_SOURCE STREQUAL "local")
  get_filename_component(LIBMPV "${LIBMPV_ARCHIVE}" NAME)

  if(NOT LIBMPV MATCHES "^mpv-dev-${LIBMPV_ARCH}-.*\\.7z$")
    message(WARNING "Local libmpv archive name does not match the current target architecture (${LIBMPV_ARCH}): ${LIBMPV}")
  endif()

  file(MD5 "${LIBMPV_ARCHIVE}" LIBMPV_MD5)
  message(STATUS "Using local libmpv archive: ${LIBMPV_ARCHIVE}")
else()
  message(STATUS "Using remote libmpv archive: ${LIBMPV_URL}")
endif()

set(LIBMPV_ID "${LIBMPV_SOURCE}|${LIBMPV}|${LIBMPV_MD5}")

if(EXISTS "${LIBMPV_SRC}")
  if(EXISTS "${LIBMPV_STAMP}")
    file(READ "${LIBMPV_STAMP}" LIBMPV_EXTRACTED_ID)
    string(STRIP "${LIBMPV_EXTRACTED_ID}" LIBMPV_EXTRACTED_ID)
  else()
    set(LIBMPV_EXTRACTED_ID "")
  endif()

  if(NOT LIBMPV_EXTRACTED_ID STREQUAL LIBMPV_ID)
    message(STATUS "Removing stale libmpv extraction from ${LIBMPV_SRC}.")
    file(REMOVE_RECURSE "${LIBMPV_SRC}")
  endif()
endif()

if(LIBMPV_SOURCE STREQUAL "remote")
  download_and_verify(
    ${LIBMPV_URL}
    ${LIBMPV_MD5}
    ${LIBMPV_ARCHIVE}
  )
endif()

check_libmpv_extraction(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# Find 7zip for extraction (preferred for .7z files)
find_program(SEVENZ_EXECUTABLE NAMES 7z 7za)

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  if(EXISTS "${LIBMPV_SRC}")
    file(REMOVE_RECURSE "${LIBMPV_SRC}")
  endif()
  make_directory("${LIBMPV_SRC}")
  file(WRITE "${LIBMPV_STAMP}" "${LIBMPV_ID}\n")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  
  if(SEVENZ_EXECUTABLE)
    message(STATUS "Using 7zip for extraction: ${SEVENZ_EXECUTABLE}")
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      POST_BUILD
      COMMAND "${SEVENZ_EXECUTABLE}" x -y "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  else()
    message(STATUS "7zip not found, falling back to CMake tar")
    add_custom_command(
      TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
      POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
      COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
      COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
      COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
      WORKING_DIRECTORY "${LIBMPV_SRC}"
    )
  endif()
endif()

set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  PARENT_SCOPE
)

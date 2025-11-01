#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${ROOT_DIR}/c-tests"
BUILD_DIR="${TEST_DIR}/build"
SUMMARY_FILE="${BUILD_DIR}/summary.txt"

mkdir -p "${BUILD_DIR}"

cc_bin="${CC:-}"
if [[ -z "${cc_bin}" ]]; then
  if command -v gcc >/dev/null 2>&1; then
    cc_bin="gcc"
  elif command -v clang >/dev/null 2>&1; then
    cc_bin="clang"
  else
    echo "No C compiler found (gcc/clang)" >&2
    exit 1
  fi
fi

echo "Using compiler: ${cc_bin}" | tee "${BUILD_DIR}/compiler.txt"

tests=("${TEST_DIR}"/*.c)
if [[ ${#tests[@]} -eq 1 && ! -f "${tests[0]}" ]]; then
  echo "No C tests found in ${TEST_DIR}" >&2
  exit 1
fi

failures=0
passed=0

echo "# C Test Results" > "${SUMMARY_FILE}"
echo >> "${SUMMARY_FILE}"

for src in "${TEST_DIR}"/*.c; do
  base="$(basename "${src}" .c)"
  bin="${BUILD_DIR}/${base}"
  out_file="${BUILD_DIR}/${base}.out"
  err_file="${BUILD_DIR}/${base}.err"
  status_file="${BUILD_DIR}/${base}.status"

  echo "Compiling ${src} -> ${bin}"
  if "${cc_bin}" -std=c11 -O2 -Wall -Wextra -Werror -o "${bin}" "${src}" 2>"${err_file}.compile"; then
    :
  else
    echo "❌ Compile failed: ${base}" | tee -a "${SUMMARY_FILE}"
    echo "status=compile_failed" > "${status_file}"
    cat "${err_file}.compile" >> "${SUMMARY_FILE}"
    echo "" >> "${SUMMARY_FILE}"
    ((failures++))
    continue
  fi

  # Run with a timeout to prevent hangs
  echo "Running ${bin}"
  if command -v timeout >/dev/null 2>&1; then
    set +e
    timeout 5s "${bin}" >"${out_file}" 2>"${err_file}"
    exit_code=$?
    set -e
  else
    set +e
    "${bin}" >"${out_file}" 2>"${err_file}"
    exit_code=$?
    set -e
  fi

  if [[ ${exit_code} -eq 0 ]]; then
    echo "✅ ${base} (exit=0)" | tee -a "${SUMMARY_FILE}"
    echo "status=ok" > "${status_file}"
    ((passed++))
  else
    echo "❌ ${base} (exit=${exit_code})" | tee -a "${SUMMARY_FILE}"
    echo "status=failed exit=${exit_code}" > "${status_file}"
    ((failures++))
  fi

  echo "Output (stdout):" >> "${SUMMARY_FILE}"
  sed -n '1,100p' "${out_file}" >> "${SUMMARY_FILE}" || true
  echo >> "${SUMMARY_FILE}"
  if [[ -s "${err_file}" ]]; then
    echo "Output (stderr):" >> "${SUMMARY_FILE}"
    sed -n '1,100p' "${err_file}" >> "${SUMMARY_FILE}" || true
    echo >> "${SUMMARY_FILE}"
  fi
  echo "---" >> "${SUMMARY_FILE}"
done

echo >> "${SUMMARY_FILE}"
echo "Passed: ${passed}  Failed: ${failures}" | tee -a "${SUMMARY_FILE}"

# Write to GitHub Step Summary if available
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "# C Test Results"
    echo
    cat "${SUMMARY_FILE}"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [[ ${failures} -gt 0 ]]; then
  exit 1
fi


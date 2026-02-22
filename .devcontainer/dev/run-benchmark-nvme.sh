#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# Benchmark script for NVMe performance testing using FIO
#
# Usage:
#   sudo ./benchmark-nvme.sh [OPTIONS]
#
# Options:
#   --target DIR      Target directory (default: /var/cache/fscache)
#   --runtime SECS    Runtime per test in seconds (default: 30)
#   --sizes LIST      Comma-separated file sizes (default: 1G)
#   --tests LIST      Comma-separated test names (default: all)
#                     Test names: rand-read,rand-write,seq-read,seq-write,mixed-rw,
#                            	  high-qd-seq-read,mixed-bs-read,mixed-bs-write
#   --buffered        Use buffered I/O (direct=0) instead of direct I/O (direct=1).
#                     Buffered I/O exercises the page cache, filesystem journal,
#                     and writeback paths
#   --output DIR      Output directory (default: /tmp/fio-results-<timestamp>)
#   --help            Show this help message
#
# Expected NVMe performance targets (i3en.6xlarge, 2 x NVMe, RAID0):
#   Random 4K 100% Read:  ~500K IOPS
#   Random 4K 100% Write: ~400K IOPS
#   Sequential 128K Read:  ~4 GB/s
#   Sequential 128K Write: ~2 GB/s
#   Mixed BS Read (4k/8k/32k): realistic NFS workload baseline
#   Mixed BS Write (4k/8k/32k): realistic NFS workload baseline

set -o errexit
set -o pipefail

# defaults
TARGET="/var/cache/fscache"
RUNTIME=30
SIZES="1G"
TESTS="rand-read,rand-write,seq-read,seq-write,mixed-rw,high-qd-seq-read,mixed-bs-read,mixed-bs-write"
DIRECT=1
OUTPUT=""

usage() {
	echo "Usage: sudo ./$0 [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --target DIR      Target directory (default: /var/cache/fscache)"
	echo "  --runtime SECS    Runtime per test (default: 30)"
	echo "  --sizes LIST      Comma-separated file sizes (default: 1G)"
	echo "  --tests LIST      Comma-separated test names (default: all)"
	echo "  --buffered        Use buffered I/O (direct=0) instead of direct I/O (direct=1)"
	echo "  --output DIR      Output directory (default: /tmp/fio-results-<timestamp>)"
	echo "  --help            Show this help message"
	echo ""
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--target)
				TARGET="$2"
				shift 2
				;;
			--runtime)
				RUNTIME="$2"
				shift 2
				;;
			--sizes)
				SIZES="$2"
				shift 2
				;;
			--tests)
				TESTS="$2"
				shift 2
				;;
			--buffered)
				DIRECT=0
				shift
				;;
			--output)
				OUTPUT="$2"
				shift 2
				;;
			--help)
				usage
				exit 0
				;;
			*)
				echo "ERROR: Unknown option: $1" >&2
				usage
				exit 1
				;;
		esac
	done
}

# check_prereqs verifies root privileges, fio is installed, and target is writable
check_prereqs() {
	if [[ "${EUID}" -ne 0 ]]; then
		echo "ERROR: This script must be run as root (use sudo)" >&2
		exit 1
	fi

	if ! command -v fio > /dev/null 2>&1; then
		echo "ERROR: fio is not installed. Run: sudo apt-get install -y fio" >&2
		exit 1
	fi

	if [[ ! -d "${TARGET}" ]]; then
		echo "ERROR: Target directory does not exist: ${TARGET}" >&2
		exit 1
	fi

	if ! touch "${TARGET}/.fio-test-probe" 2> /dev/null; then
		echo "ERROR: Target directory is not writable: ${TARGET}" >&2
		exit 1
	fi
	rm -f "${TARGET}/.fio-test-probe"
}

# print_device_info captures current block device and filesystem state
print_device_info() {
	echo "============================================="
	echo "Benchmark script for NVMe performance testing"
	echo "============================================="
	echo ""
	echo "Date:      $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	echo "Hostname:  $(hostname)"
	echo "Kernel:    $(uname -r)"
	echo "Target:    ${TARGET}"
	echo "Runtime:   ${RUNTIME}s per test"
	echo "Sizes:     ${SIZES}"
	echo "Tests:     ${TESTS}"
	echo "Direct:    ${DIRECT} (0=buffered, 1=direct)"
	echo "Output:    ${OUTPUT}"
	echo ""

	echo "--- Filesystem ---"
	df -hT "${TARGET}" 2> /dev/null || true
	echo ""
	mount | grep "$(df --output=source "${TARGET}" 2> /dev/null | tail -1)" 2> /dev/null || true
	echo ""

	echo "--- Block devices ---"
	lsblk -o NAME,TYPE,SIZE,ROTA,SCHED,RQ-SIZE,MODEL 2> /dev/null || true
	echo ""

	echo "--- RAID status ---"
	cat /proc/mdstat 2> /dev/null || echo "No RAID arrays"
	echo ""

	echo "--- Block queue settings ---"
	for dev in /sys/block/nvme*/queue /sys/block/md*/queue; do
		if [[ -d "${dev}" ]]; then
			local devname
			devname=$(basename "$(dirname "${dev}")")
			echo "${devname}:"
			echo "  scheduler:     $(cat "${dev}/scheduler" 2> /dev/null || echo 'N/A')"
			echo "  nr_requests:   $(cat "${dev}/nr_requests" 2> /dev/null || echo 'N/A')"
			echo "  nomerges:      $(cat "${dev}/nomerges" 2> /dev/null || echo 'N/A')"
			echo "  read_ahead_kb: $(cat "${dev}/read_ahead_kb" 2> /dev/null || echo 'N/A')"
		fi
	done
	echo ""

	echo "--- VM sysctls ---"
	echo "  vm.dirty_ratio:              $(sysctl -n vm.dirty_ratio 2> /dev/null)"
	echo "  vm.dirty_background_ratio:   $(sysctl -n vm.dirty_background_ratio 2> /dev/null)"
	echo "  vm.swappiness:               $(sysctl -n vm.swappiness 2> /dev/null)"
	echo "  vm.min_free_kbytes:          $(sysctl -n vm.min_free_kbytes 2> /dev/null)"
	echo "  vm.compaction_proactiveness: $(sysctl -n vm.compaction_proactiveness 2> /dev/null)"
	echo "  vm.vfs_cache_pressure:       $(sysctl -n vm.vfs_cache_pressure 2> /dev/null)"
	echo ""
}

# run_fio executes a single fio test and saves JSON output
# $1 = test name, $2 = file size, $3+ = fio arguments
run_fio() {
	local test_name="$1"
	local file_size="$2"
	shift 2

	local json_file="${OUTPUT}/${test_name}_${file_size}.json"
	local fio_dir="${TARGET}/fio-bench"

	mkdir -p "${fio_dir}"

	echo -n "  [${test_name}] size=${file_size} ... "

	fio \
		--name="${test_name}" \
		--directory="${fio_dir}" \
		--size="${file_size}" \
		--runtime="${RUNTIME}" \
		--time_based \
		--output-format=json \
		--output="${json_file}" \
		--group_reporting \
		--eta=never \
		"$@"

	# extract summary from JSON
	local read_iops read_bw_mb read_lat_p50 read_lat_p95 read_lat_p99
	local write_iops write_bw_mb write_lat_p50 write_lat_p95 write_lat_p99

	read_iops=$(jq -r '.jobs[0].read.iops // 0' "${json_file}" 2> /dev/null)
	read_bw_mb=$(jq -r '(.jobs[0].read.bw // 0) / 1024 | floor' "${json_file}" 2> /dev/null)
	read_lat_p50=$(jq -r '.jobs[0].read.clat_ns.percentile["50.000000"] // 0' "${json_file}" 2> /dev/null)
	read_lat_p95=$(jq -r '.jobs[0].read.clat_ns.percentile["95.000000"] // 0' "${json_file}" 2> /dev/null)
	read_lat_p99=$(jq -r '.jobs[0].read.clat_ns.percentile["99.000000"] // 0' "${json_file}" 2> /dev/null)

	write_iops=$(jq -r '.jobs[0].write.iops // 0' "${json_file}" 2> /dev/null)
	write_bw_mb=$(jq -r '(.jobs[0].write.bw // 0) / 1024 | floor' "${json_file}" 2> /dev/null)
	write_lat_p50=$(jq -r '.jobs[0].write.clat_ns.percentile["50.000000"] // 0' "${json_file}" 2> /dev/null)
	write_lat_p95=$(jq -r '.jobs[0].write.clat_ns.percentile["95.000000"] // 0' "${json_file}" 2> /dev/null)
	write_lat_p99=$(jq -r '.jobs[0].write.clat_ns.percentile["99.000000"] // 0' "${json_file}" 2> /dev/null)

	# format latencies from nanoseconds to microseconds
	read_lat_p50=$(echo "scale=1; ${read_lat_p50} / 1000" | bc 2> /dev/null || echo "0")
	read_lat_p95=$(echo "scale=1; ${read_lat_p95} / 1000" | bc 2> /dev/null || echo "0")
	read_lat_p99=$(echo "scale=1; ${read_lat_p99} / 1000" | bc 2> /dev/null || echo "0")
	write_lat_p50=$(echo "scale=1; ${write_lat_p50} / 1000" | bc 2> /dev/null || echo "0")
	write_lat_p95=$(echo "scale=1; ${write_lat_p95} / 1000" | bc 2> /dev/null || echo "0")
	write_lat_p99=$(echo "scale=1; ${write_lat_p99} / 1000" | bc 2> /dev/null || echo "0")

	# print inline result
	if [[ "${read_iops}" != "0" ]] && [[ "${write_iops}" != "0" ]]; then
		printf "R: %.0f IOPS %s MB/s (p50=%s p95=%s p99=%s us) " \
			"${read_iops}" "${read_bw_mb}" "${read_lat_p50}" "${read_lat_p95}" "${read_lat_p99}"
		printf "W: %.0f IOPS %s MB/s (p50=%s p95=%s p99=%s us)\n" \
			"${write_iops}" "${write_bw_mb}" "${write_lat_p50}" "${write_lat_p95}" "${write_lat_p99}"
	elif [[ "${read_iops}" != "0" ]]; then
		printf "R: %.0f IOPS %s MB/s (p50=%s p95=%s p99=%s us)\n" \
			"${read_iops}" "${read_bw_mb}" "${read_lat_p50}" "${read_lat_p95}" "${read_lat_p99}"
	elif [[ "${write_iops}" != "0" ]]; then
		printf "W: %.0f IOPS %s MB/s (p50=%s p95=%s p99=%s us)\n" \
			"${write_iops}" "${write_bw_mb}" "${write_lat_p50}" "${write_lat_p95}" "${write_lat_p99}"
	else
		echo "no data"
	fi

	# append to summary CSV
	echo "${test_name},${file_size},${read_iops},${read_bw_mb},${read_lat_p50},${read_lat_p95},${read_lat_p99},${write_iops},${write_bw_mb},${write_lat_p50},${write_lat_p95},${write_lat_p99}" \
		>> "${OUTPUT}/summary.csv"

	# clean up test files between runs to avoid filling disk
	rm -rf "${fio_dir:?}/"*
}

# drop_caches drops page cache, dentries, and inodes between tests
drop_caches() {
	sync
	echo 3 > /proc/sys/vm/drop_caches 2> /dev/null || true
}

# test_rand_read: random 4K reads
test_rand_read() {
	local size="$1"
	run_fio "rand-read" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bs=4k \
		--rw=randread \
		--iodepth=128 \
		--numjobs=4
}

# test_rand_write: random 4K writes
test_rand_write() {
	local size="$1"
	run_fio "rand-write" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bs=4k \
		--rw=randwrite \
		--iodepth=128 \
		--numjobs=4
}

# test_seq_read: sequential 128K reads
test_seq_read() {
	local size="$1"
	run_fio "seq-read" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bs=128k \
		--rw=read \
		--iodepth=32 \
		--numjobs=4
}

# test_seq_write: sequential 128K writes
test_seq_write() {
	local size="$1"
	run_fio "seq-write" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bs=128k \
		--rw=write \
		--iodepth=32 \
		--numjobs=4
}

# test_mixed_rw: mixed 70% read / 30% write random 4K
test_mixed_rw() {
	local size="$1"
	run_fio "mixed-rw" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bs=4k \
		--rw=randrw \
		--rwmixread=70 \
		--iodepth=128 \
		--numjobs=4
}

# test_high_qd_seq_read: high queue depth sequential read (stress test)
test_high_qd_seq_read() {
	local size="$1"
	run_fio "high-qd-seq-read" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bs=128k \
		--rw=read \
		--iodepth=256 \
		--numjobs=1
}

# test_mixed_bs_read: realistic mixed block-size random reads
# bssplit: 60% 4K, 20% 8K, 20% 32K -- models real NFS/fscache read traffic
# where small metadata-like reads mix with slightly larger data reads.
# iodepth=16 represents moderate nfsd concurrency per file.
test_mixed_bs_read() {
	local size="$1"
	run_fio "mixed-bs-read" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bssplit=4k/60:8k/20:32k/20 \
		--rw=randread \
		--iodepth=16 \
		--numjobs=4
}

# test_mixed_bs_write: realistic mixed block-size random writes
# bssplit: 60% 4K, 20% 8K, 20% 32K -- models real NFS/fscache write traffic
# for cache fill operations with varied block sizes.
# iodepth=16 represents moderate nfsd concurrency per file.
test_mixed_bs_write() {
	local size="$1"
	run_fio "mixed-bs-write" "${size}" \
		--ioengine=libaio \
		--direct=${DIRECT} \
		--bssplit=4k/60:8k/20:32k/20 \
		--rw=randwrite \
		--iodepth=16 \
		--numjobs=4
}

# print_summary displays the summary CSV as a formatted table
print_summary() {
	echo ""
	echo "============================================="
	echo "SUMMARY"
	echo "============================================="
	echo ""
	echo "Results saved to: ${OUTPUT}/"
	echo ""

	if [[ ! -f "${OUTPUT}/summary.csv" ]]; then
		echo "No results collected."
		return
	fi

	# header
	printf "%-20s %6s %12s %10s %10s %10s %10s %12s %10s %10s %10s %10s\n" \
		"Test" "Size" "R_IOPS" "R_MB/s" "R_p50us" "R_p95us" "R_p99us" \
		"W_IOPS" "W_MB/s" "W_p50us" "W_p95us" "W_p99us"
	printf "%-20s %6s %12s %10s %10s %10s %10s %12s %10s %10s %10s %10s\n" \
		"--------------------" "------" "------------" "----------" "----------" "----------" "----------" \
		"------------" "----------" "----------" "----------" "----------"

	while IFS=',' read -r test_name file_size r_iops r_bw r_p50 r_p95 r_p99 w_iops w_bw w_p50 w_p95 w_p99; do
		printf "%-20s %6s %12s %10s %10s %10s %10s %12s %10s %10s %10s %10s\n" \
			"${test_name}" "${file_size}" "${r_iops}" "${r_bw}" "${r_p50}" "${r_p95}" "${r_p99}" \
			"${w_iops}" "${w_bw}" "${w_p50}" "${w_p95}" "${w_p99}"
	done < "${OUTPUT}/summary.csv"

	echo ""

	local total_tests
	total_tests=$(wc -l < "${OUTPUT}/summary.csv")
	local total_time=$((total_tests * RUNTIME))
	echo "Total tests: ${total_tests}, estimated wall time: ~${total_time}s"
	echo "JSON files for detailed analysis are in: ${OUTPUT}/"
}

main() {
	parse_args "$@"

	# set output directory
	if [[ -z "${OUTPUT}" ]]; then
		OUTPUT="/tmp/fio-results-$(date +%Y%m%d-%H%M%S)"
	fi
	mkdir -p "${OUTPUT}"

	check_prereqs
	print_device_info | tee "${OUTPUT}/system-info.txt"

	# initialise summary CSV
	echo "test,size,read_iops,read_bw_mb,read_lat_p50_us,read_lat_p95_us,read_lat_p99_us,write_iops,write_bw_mb,write_lat_p50_us,write_lat_p95_us,write_lat_p99_us" \
		> "${OUTPUT}/summary.csv"

	# parse sizes and tests into arrays
	IFS=',' read -ra SIZE_ARRAY <<< "${SIZES}"
	IFS=',' read -ra TEST_ARRAY <<< "${TESTS}"

	local total_count=$((${#TEST_ARRAY[@]} * ${#SIZE_ARRAY[@]}))
	local current=0

	echo "Running ${total_count} tests (${#TEST_ARRAY[@]} tests x ${#SIZE_ARRAY[@]} sizes @ ${RUNTIME}s each)"
	echo "Estimated total time: ~$((total_count * RUNTIME))s"
	echo ""

	for size in "${SIZE_ARRAY[@]}"; do
		echo "=== File size: ${size} ==="

		for test_name in "${TEST_ARRAY[@]}"; do
			current=$((current + 1))
			echo -n "[${current}/${total_count}]"

			drop_caches

			case "${test_name}" in
				rand-read)
					test_rand_read "${size}"
					;;
				rand-write)
					test_rand_write "${size}"
					;;
				seq-read)
					test_seq_read "${size}"
					;;
				seq-write)
					test_seq_write "${size}"
					;;
				mixed-rw)
					test_mixed_rw "${size}"
					;;
				high-qd-seq-read)
					test_high_qd_seq_read "${size}"
					;;
				mixed-bs-read)
					test_mixed_bs_read "${size}"
					;;
				mixed-bs-write)
					test_mixed_bs_write "${size}"
					;;
				*)
					echo "  WARNING: Unknown test '${test_name}', skipping" >&2
					;;
			esac
		done

		echo ""
	done

	print_summary | tee "${OUTPUT}/summary.txt"
}

main "$@"

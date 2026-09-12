#!/usr/bin/env bash
# Exact non-negative decimal arithmetic for byte counters. Never send kernel
# uint64 counters or long-lived totals through floating point or signed Bash
# arithmetic. Ordinary small counters retain a cheap builtin fast path.
uint_normalize_v() {
  local value=$1
  [[ $value =~ ^[0-9]+$ && ${#value} -le 100 ]] || return 1
  while [[ ${#value} -gt 1 && $value == 0* ]]; do value=${value#0}; done
  UINT_VALUE=$value
}

uint_compare_v() {
  local a=$1 b=$2 LC_ALL=C
  UINT_COMPARE=0
  if ((${#a} > ${#b})); then UINT_COMPARE=1
  elif ((${#a} < ${#b})); then UINT_COMPARE=-1
  elif [[ $a > $b ]]; then UINT_COMPARE=1
  elif [[ $a < $b ]]; then UINT_COMPARE=-1; fi
}

uint_add_v() {
  local a=$1 b=$2 i j carry=0 n x y out=''
  if ((${#a} < 16 && ${#b} < 16)); then UINT_VALUE=$((10#$a + 10#$b)); return 0; fi
  for ((i=${#a}-1,j=${#b}-1; i>=0 || j>=0 || carry; i--,j--)); do
    x=0 y=0
    ((i < 0)) || x=${a:i:1}
    ((j < 0)) || y=${b:j:1}
    n=$((x + y + carry)); carry=$((n / 10)); out="$((n % 10))$out"
  done
  UINT_VALUE=${out:-0}
}

uint_subtract_v() {
  local a=$1 b=$2 i j borrow=0 n x y out=''
  uint_compare_v "$a" "$b"
  ((UINT_COMPARE >= 0)) || return 1
  if ((${#a} < 16 && ${#b} < 16)); then UINT_VALUE=$((10#$a - 10#$b)); return 0; fi
  for ((i=${#a}-1,j=${#b}-1; i>=0; i--,j--)); do
    x=${a:i:1} y=0
    ((j < 0)) || y=${b:j:1}
    n=$((x - y - borrow)); borrow=0
    if ((n < 0)); then n=$((n + 10)); borrow=1; fi
    out="$n$out"
  done
  uint_normalize_v "$out"
}

# floor(bytes * 1000 / elapsed_ms), without overflowing bytes * 1000.
uint_rate_v() {
  local value=$1 ms=$2 digits i rem=0 out='' n
  [[ $ms =~ ^[1-9][0-9]{0,12}$ ]] || return 1
  if ((${#value} < 16)); then UINT_VALUE=$((value * 1000 / ms)); return 0; fi
  digits="${value}000"
  for ((i=0; i<${#digits}; i++)); do
    n=$((rem * 10 + ${digits:i:1}))
    out+=$((n / ms)); rem=$((n % ms))
  done
  uint_normalize_v "$out"
}

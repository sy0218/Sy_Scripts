#!/bin/bash
# Alloy → Loki 행 카운트 정합성 검증

ALLOY_URL="http://localhost:9101"

# Alloy 가 파일에서 읽은 라인 수
READ=$(curl -s ${ALLOY_URL}/metrics \
  | awk '/^loki_source_file_read_lines_total\{/ {sum+=$2} END {print sum+0}')

# Alloy 가 Loki 로 전송 성공한 라인 수
SENT=$(curl -s ${ALLOY_URL}/metrics \
  | awk '/^loki_write_sent_entries_total\{/ {sum+=$2} END {print sum+0}')

# 드롭(전송 실패)된 라인 수
DROP=$(curl -s ${ALLOY_URL}/metrics \
  | awk '/^loki_write_dropped_entries_total\{/ {sum+=$2} END {print sum+0}')

DIFF=$((READ - SENT))

echo "─────────────────────────────────────"
echo " Alloy → Loki 정합성 ($(date '+%H:%M:%S'))"
echo "─────────────────────────────────────"
printf " 읽음 (read)  : %s\n" "$READ"
printf " 전송 (sent)  : %s\n" "$SENT"
printf " 차이 (diff)  : %s\n" "$DIFF"
printf " 드롭 (drop)  : %s\n" "$DROP"
echo "─────────────────────────────────────"

if [ "$READ" -eq "$SENT" ] && [ "$DROP" -eq 0 ]; then
  echo " 정합성 OK"
  exit 0
elif [ "$DROP" -gt 0 ]; then
  echo " 드롭 발생 — Loki 거절 (rate limit / schema 확인)"
  exit 1
elif [ "$DIFF" -gt 0 ]; then
  echo " 전송 지연 또는 실패 (read - sent = $DIFF)"
  exit 1
else
  echo " 예상치 못한 상태"
  exit 2
fi

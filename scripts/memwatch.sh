#!/bin/zsh
# 사용: scripts/memwatch.sh <상한 MB> <명령...>   (예: scripts/memwatch.sh 4000 build-dev/Build/Products/Debug/madi-spike digestprogress 영상.mp4)
# 긴 영상 실험은 반드시 이걸로 — 2026-09-29 해독 프레임 누수로 개발 맥이 두 번 재부팅됐다 (AGENTS.md §17)
# 명령을 띄우고 1초마다 그 프로세스 + 새로 생긴 VTDecoderXPCService 의 footprint 를 잰다. 상한을 넘으면 끊는다.
LIMIT=$1; shift
before=($(pgrep -f VTDecoderXPCService))
"$@" > /tmp/memwatch.out 2>&1 &
PID=$!
peak_self=0; peak_dec=0; t=0
fp() { footprint -p $1 2>/dev/null | awk '/phys_footprint:/{v=$2; u=$3; if(u=="GB")v*=1024; else if(u=="KB")v/=1024; printf "%d", v; exit}'; }
while kill -0 $PID 2>/dev/null; do
  sleep 1; t=$((t+1))
  self=$(fp $PID); self=${self:-0}
  dec=0
  for p in $(pgrep -f VTDecoderXPCService); do
    if (( ${before[(Ie)$p]} == 0 )); then d=$(fp $p); dec=$((dec + ${d:-0})); fi
  done
  (( self > peak_self )) && peak_self=$self
  (( dec > peak_dec )) && peak_dec=$dec
  (( t % 5 == 0 )) && echo "${t}s  도구 ${self}MB  새 해독기 ${dec}MB"
  if (( self > LIMIT || dec > LIMIT )); then
    echo "상한 ${LIMIT}MB 넘음 — 끊는다 (도구 ${self}MB · 해독기 ${dec}MB)"; kill -9 $PID; break
  fi
done
wait $PID 2>/dev/null
echo "최고: 도구 ${peak_self}MB · 새 해독기 ${peak_dec}MB · ${t}초"
tail -2 /tmp/memwatch.out

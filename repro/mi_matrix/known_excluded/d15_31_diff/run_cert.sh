#!/usr/bin/env bash
# Task 9f.1 certification harness. Test-only; no sf/src edits.
set -u
ROOT=/workspace/znineeight
BASE=/tmp/t9a_base_build/zig1_5_clean
FINAL=/tmp/t9f2_final_build/zig1_5_clean
PRE=/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean
EV=/tmp/t9f1_evidence
LIST=$EV/entries.tsv
mkdir -p "$EV"

resolve_entry() {
  local d="$1" name
  name="$(basename "$d")"
  if [ -f "$d/main.zig" ]; then echo "$d/main.zig"
  elif [ -f "$d/$name.zig" ]; then echo "$d/$name.zig"
  else find "$d" -maxdepth 1 -type f -name '*.zig' | LC_ALL=C sort | head -1
  fi
}

dump() { # compiler outdir entry log
  local Z="$1" out="$2" entry="$3" log="$4"
  rm -rf "$out"; mkdir -p "$out"
  ( cd "$ROOT" && "$Z" -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir "$out" "$entry" ) >"$log" 2>&1
  echo $?
}

build() { # outdir bin log
  local dir="$1" bin="$2" log="$3" rc=0
  rm -f "$dir"/*.o "$bin"
  ( cd "$dir" && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I . -c ./*.c ) >"$log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    ( cd "$dir" && gcc -m32 -O0 ./*.o -o "$bin" ) >>"$log" 2>&1 || rc=$?
  fi
  echo "$rc"
}

runbin() { # bin tag outprefix
  local bin="$1" pfx="$2"
  timeout 20 "$bin" </dev/null >"$pfx.stdout" 2>"$pfx.stderr"
  local rc=$?
  echo "$rc"
}

printf 'category\tentry\tbase_dump_rc\tfinal_dump_rc\tbase_c\tfinal_c\tbase_build\tfinal_build\tbase_run\tfinal_run\tbase_stdout_sha\tfinal_stdout_sha\tbase_out_eq_final\tfinal_out_eq_pre\n' > "$EV/results.tsv"

while IFS=$'\t' read -r cat entry; do
  [ -n "$entry" ] || continue
  tag="$(printf '%s' "$entry" | tr '/' '_')"
  d="$EV/$tag"; mkdir -p "$d"
  ef="$(resolve_entry "$ROOT/$entry")"
  bd="$d/base"; fd="$d/final"
  rb=$(dump "$BASE" "$bd" "$ef" "$d/base.dump.log")
  rf=$(dump "$FINAL" "$fd" "$ef" "$d/final.dump.log")
  bc=$(find "$bd" -maxdepth 1 -name '*.c' | wc -l)
  fc=$(find "$fd" -maxdepth 1 -name '*.c' | wc -l)
  bb="-"; fb="-"; rb_run="-"; rf_run="-"; bs="-"; fs="-"; eqbf="-"; eqfp="-"
  if [ "$rb" -eq 0 ]; then bb=$(build "$bd" "$d/base.bin" "$d/base.build.log"); fi
  if [ "$rf" -eq 0 ]; then fb=$(build "$fd" "$d/final.bin" "$d/final.build.log"); fi
  if [ "$bb" = "0" ]; then rb_run=$(runbin "$d/base.bin" "$d/base.run"); bs=$(sha256sum "$d/base.run.stdout" | awk '{print $1}'); fi
  if [ "$fb" = "0" ]; then rf_run=$(runbin "$d/final.bin" "$d/final.run"); fs=$(sha256sum "$d/final.run.stdout" | awk '{print $1}'); fi
  if [ "$bb" = "0" ] && [ "$fb" = "0" ]; then
    if cmp -s "$d/base.run.stdout" "$d/final.run.stdout" && [ "$rb_run" = "$rf_run" ]; then eqbf=YES; else eqbf=NO; fi
  fi
  if [ "$cat" = "12-recovered" ]; then
    pd="$d/pre"; rp=$(dump "$PRE" "$pd" "$ef" "$d/pre.dump.log")
    pc=$(find "$pd" -maxdepth 1 -name '*.c' | wc -l)
    if [ "$rp" -eq 0 ]; then
      pb=$(build "$pd" "$d/pre.bin" "$d/pre.build.log")
      if [ "$pb" = "0" ]; then
        pr=$(runbin "$d/pre.bin" "$d/pre.run")
        if [ "$fb" = "0" ] && cmp -s "$d/pre.run.stdout" "$d/final.run.stdout" && [ "$pr" = "$rf_run" ]; then eqfp=YES; else eqfp=NO; fi
      else eqfp="BUILD$pb"; fi
    else eqfp="DUMP$rp"; fi
    # record pre metadata line separately
    printf 'PRE\t%s\tdump=%s\tc=%s\tbuild=%s\trun=%s\n' "$entry" "$rp" "$pc" "$pb" "$pr" >> "$d/pre.meta"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$cat" "$entry" "$rb" "$rf" "$bc" "$fc" "$bb" "$fb" "$rb_run" "$rf_run" "$bs" "$fs" "$eqbf" "$eqfp" >> "$EV/results.tsv"
  printf '%s %s dump=%s/%s build=%s/%s run=%s/%s eq=%s pre=%s\n' "$cat" "$entry" "$rb" "$rf" "$bb" "$fb" "$rb_run" "$rf_run" "$eqbf" "$eqfp"
done < "$LIST"

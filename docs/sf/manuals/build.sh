#!/usr/bin/env bash
#
# build.sh - assemble the Z98 manual static site.
#
# Clears and recreates dist/, regenerates the English search index from the
# en/*.html pages, then copies the hand-authored top-level pages and the whole
# en/ tree into dist/. Offline only; paths resolve relative to this script so
# it works from any working directory. Idempotent.

set -e

LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EN_DIR="$SCRIPT_DIR/en"
DIST_DIR="$SCRIPT_DIR/dist"
SEARCH_DATA="$EN_DIR/search-data.js"

# Escape a value for a double-quoted JavaScript string literal, flattening any
# embedded newlines. Plain 1998-era JS: backslash and double-quote only.
js_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\r\n'
}

# 1. Clear and recreate the output directory.
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 2. Regenerate the English search index by scanning every en/*.html page for
#    its <title>, its <meta name="keywords"> content, and its first <h1>.
#    Entries are emitted sorted by filename; doc.js doSearch() reads
#    file/title/keywords.
pages_indexed=0
{
	printf 'var z98SearchData = ['
	first=1
	for page in "$EN_DIR"/*.html; do
		[ -e "$page" ] || continue
		base="$(basename "$page")"
		title="$(sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$page" | head -n 1)"
		keywords="$(sed -n 's/.*<meta[[:space:]][^>]*name="keywords"[^>]*content="\([^"]*\)".*/\1/p' "$page" | head -n 1)"
		heading="$(sed -n 's/.*<h1>\(.*\)<\/h1>.*/\1/p' "$page" | head -n 1)"
		title="$(js_escape "$title")"
		keywords="$(js_escape "$keywords")"
		heading="$(js_escape "$heading")"
		if [ "$first" -eq 0 ]; then
			printf ','
		fi
		first=0
		printf '{file:"%s",title:"%s",keywords:"%s",heading:"%s"}' \
			"$base" "$title" "$keywords" "$heading"
		pages_indexed=$((pages_indexed + 1))
	done
	printf '];\n'
} > "$SEARCH_DATA"

# 3. Copy the top-level pages.
for f in index.html readme.html todo-figures-list.html; do
	cp "$SCRIPT_DIR/$f" "$DIST_DIR/$f"
done

# 4. Copy the whole en/ tree (HTML, CSS, JS, gfx) as dist/en/ so the relative
#    links inside the pages keep working.
cp -R "$EN_DIR" "$DIST_DIR/en"

files_copied="$(find "$DIST_DIR" -type f | wc -l | tr -d ' ')"

# 5. Summary.
printf 'build.sh: indexed %d pages, copied %d files to %s\n' \
	"$pages_indexed" "$files_copied" "$DIST_DIR"

#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────────────────
# Meñique Generator
#
# Usage: bash build.sh
# ─────────────────────────────────────────────────────────────────────────────

CHAPTERS_DIR="chapters"
IMAGES_DIR="images"
BUILD_DIR="build"
TEMPLATES_DIR="templates"

SITE_TITLE="Meñique Audiovisual"
BOOK_IMG_EXT="png"

##############################################################################
# Utility functions (no `local`)
##############################################################################

trim_spaces() {
  param="$1"
  echo "$param" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

slugify() {
  param="$1"
  echo "$param" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[[:space:]]\+/-/g'
}

# Convert the original .txt name => a safe .html
sanitize_filename() {
  base="$1"
  base="${base%.*}"                                  # remove .txt
  base="$(echo "$base" | tr '[:upper:]' '[:lower:]')"
  # Replace any non-alphanumeric with dashes
  base="$(echo "$base" | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//')"
  echo "$base.html"
}

# Split on commas => multiple tokens
split_by_commas() {
  line="$1"
  # Turn commas into newlines, then trim each
  echo "$line" | tr ',' '\n' | while read -r token; do
    trim_spaces "$token"
  done
}

# Book storing. We do not use `local` or advanced bash, just plain variables.
find_book_index_by_name() {
  bookName="$1"
  i=0
  while [ $i -lt ${#BOOK_NAMES[@]} ]; do
    if [ "${BOOK_NAMES[$i]}" = "$bookName" ]; then
      echo "$i"
      return
    fi
    i=$((i+1))
  done
  echo "-1"
}

set_book_chapters() {
  bookName="$1"
  chapterIndex="$2"

  idx="$(find_book_index_by_name "$bookName")"
  if [ "$idx" -eq "-1" ]; then
    BOOK_NAMES[${#BOOK_NAMES[@]}]="$bookName"
    BOOK_CHAPTER_LIST[${#BOOK_CHAPTER_LIST[@]}]="$chapterIndex"
  else
    oldList="${BOOK_CHAPTER_LIST[$idx]}"
    BOOK_CHAPTER_LIST[$idx]="$oldList $chapterIndex"
  fi
}

sort_book_chapters() {
  i=0
  while [ $i -lt ${#BOOK_NAMES[@]} ]; do
    bk="${BOOK_NAMES[$i]}"
    chList="${BOOK_CHAPTER_LIST[$i]}"
    chList="$(trim_spaces "$chList")"

    lines=""
    for cIdx in $chList; do
      dt="${CHAPTER_DATES[$cIdx]}"
      lines="$lines$dt\t$cIdx
"
    done

    sorted="$(echo -e "$lines" | sort)"  # ascending by date
    finalIndices=""
    while IFS=$'\t' read -r dateVal idxVal; do
      finalIndices="$finalIndices $idxVal"
    done <<< "$sorted"

    BOOK_CHAPTER_LIST[$i]="$(trim_spaces "$finalIndices")"
    i=$((i+1))
  done
}

# For home-page icons => newest chapter
get_newest_chapter_filename() {
  bookName="$1"
  idx="$(find_book_index_by_name "$bookName")"
  if [ "$idx" -lt 0 ]; then
    echo ""
    return
  fi
  chList="${BOOK_CHAPTER_LIST[$idx]}"
  chList="$(trim_spaces "$chList")"
  read -r -a arr <<< "$chList"
  arrLen=${#arr[@]}
  if [ $arrLen -lt 1 ]; then
    echo ""
    return
  fi
  newestIndex="${arr[$((arrLen - 1))]}"
  newestSlug="${CHAPTER_SLUGS[$newestIndex]}"
  echo "$newestSlug"
}

##############################################################################
# Global arrays
##############################################################################

CHAPTER_COUNT=0

declare -a CHAPTER_FILENAMES
declare -a CHAPTER_SLUGS
declare -a CHAPTER_TITLES
declare -a CHAPTER_RAW_AUTHORS
declare -a CHAPTER_RAW_BOOKS
declare -a CHAPTER_DATES
declare -a CHAPTER_BODYCLASS
declare -a CHAPTER_CONTENTS

# "primary" for each chapter => the first "Book:" in its comma list
declare -a CHAPTER_PRIMARY_BOOK

declare -a UNIQUE_AUTHORS
declare -a UNIQUE_YEARS

declare -a BOOK_NAMES
declare -a BOOK_CHAPTER_LIST

##############################################################################
# Parsing .txt
##############################################################################

parse_chapter() {
  file="$1"

  cTitle="Untitled"
  cAuthors=""
  cBooks=""
  cDate="1900-01-01"
  cClass=""
  cContent=""

  while IFS= read -r line; do
    [ -z "$line" ] && break

    case "$line" in
      Title:*)
        cTitle="$(trim_spaces "${line#Title:}")"
        ;;
      Author:*)
        cAuthors="$(trim_spaces "${line#Author:}")"
        ;;
      Book:*)
        cBooks="$(trim_spaces "${line#Book:}")"
        ;;
      Published:*)
        cDate="$(trim_spaces "${line#Published:}")"
        cDate="${cDate%%T*}"
        [ -z "$cDate" ] && cDate="1900-01-01"
        ;;
      BodyClass:*)
        cClass="$(trim_spaces "${line#BodyClass:}")"
        ;;
    esac
  done < "$file"

  htmlBuffer=""
  while IFS= read -r leftover; do
    htmlBuffer="$htmlBuffer$leftover
"
  done < <(tail -n +1 "$file" | sed '1,/^$/d')

  baseName="$(basename "$file")"
  safeHtml="$(sanitize_filename "$baseName")"

  CHAPTER_FILENAMES[$CHAPTER_COUNT]="$baseName"
  CHAPTER_SLUGS[$CHAPTER_COUNT]="$safeHtml"
  CHAPTER_TITLES[$CHAPTER_COUNT]="$cTitle"
  CHAPTER_RAW_AUTHORS[$CHAPTER_COUNT]="$cAuthors"
  CHAPTER_RAW_BOOKS[$CHAPTER_COUNT]="$cBooks"
  CHAPTER_DATES[$CHAPTER_COUNT]="$cDate"
  CHAPTER_BODYCLASS[$CHAPTER_COUNT]="$cClass"
  CHAPTER_CONTENTS[$CHAPTER_COUNT]="$htmlBuffer"

  CHAPTER_COUNT=$((CHAPTER_COUNT+1))
}

shopt -s nullglob
allTxt=("$CHAPTERS_DIR"/*.txt)
shopt -u nullglob

for f in "${allTxt[@]}"; do
  [ -f "$f" ] || continue
  parse_chapter "$f"
done

if [ $CHAPTER_COUNT -eq 0 ]; then
  echo "No .txt chapters found in '$CHAPTERS_DIR'."
fi

##############################################################################
# Fill arrays
##############################################################################

i=0
while [ $i -lt $CHAPTER_COUNT ]; do
  authorLine="${CHAPTER_RAW_AUTHORS[$i]}"
  # split authors
  while read -r oneAuthor; do
    [ -z "$oneAuthor" ] && continue
    j=0
    found=0
    while [ $j -lt ${#UNIQUE_AUTHORS[@]} ]; do
      if [ "${UNIQUE_AUTHORS[$j]}" = "$oneAuthor" ]; then
        found=1
        break
      fi
      j=$((j+1))
    done
    if [ $found -eq 0 ]; then
      UNIQUE_AUTHORS[${#UNIQUE_AUTHORS[@]}]="$oneAuthor"
    fi
  done < <(split_by_commas "$authorLine")

  # split books
  bookLine="${CHAPTER_RAW_BOOKS[$i]}"
  booksArray=()
  while IFS= read -r oneBook; do
    booksArray+=("$oneBook")
  done < <(split_by_commas "$bookLine")

  if [ ${#booksArray[@]} -gt 0 ]; then
    CHAPTER_PRIMARY_BOOK[$i]="${booksArray[0]}"
  else
    CHAPTER_PRIMARY_BOOK[$i]="Misc"
    booksArray=("Misc")
  fi

  # Add the chapter to each book
  for bName in "${booksArray[@]}"; do
    set_book_chapters "$bName" "$i"
  done

  dt="${CHAPTER_DATES[$i]}"
  yr="${dt:0:4}"

  j=0
  found=0
  while [ $j -lt ${#UNIQUE_YEARS[@]} ]; do
    if [ "${UNIQUE_YEARS[$j]}" = "$yr" ]; then
      found=1
      break
    fi
    j=$((j+1))
  done
  if [ $found -eq 0 ]; then
    UNIQUE_YEARS[${#UNIQUE_YEARS[@]}]="$yr"
  fi

  i=$((i+1))
done

# Sort UNIQUE_YEARS ascending
i=0
while [ $i -lt ${#UNIQUE_YEARS[@]} ]; do
  j=$((i+1))
  while [ $j -lt ${#UNIQUE_YEARS[@]} ]; do
    if [ "${UNIQUE_YEARS[$j]}" \< "${UNIQUE_YEARS[$i]}" ]; then
      temp="${UNIQUE_YEARS[$i]}"
      UNIQUE_YEARS[$i]="${UNIQUE_YEARS[$j]}"
      UNIQUE_YEARS[$j]="$temp"
    fi
    j=$((j+1))
  done
  i=$((i+1))
done

sort_book_chapters

##############################################################################
# Build HOME
##############################################################################

TEMPLATE_HOME="$TEMPLATES_DIR/home.html"
OUTPUT_HOME="$BUILD_DIR/index.html"

if [ ! -f "$TEMPLATE_HOME" ]; then
  echo "Error: $TEMPLATE_HOME not found."
  exit 1
fi

homeHTML=""
while IFS= read -r line; do
  homeHTML="$homeHTML$line
"
done < "$TEMPLATE_HOME"

authorsMenu=""
k=0
while [ $k -lt ${#UNIQUE_AUTHORS[@]} ]; do
  authorName="${UNIQUE_AUTHORS[$k]}"
  localSlug="$(slugify "$authorName")"
  authorsMenu="$authorsMenu<a href=\"authors/$localSlug.html\">$authorName</a>
"
  k=$((k+1))
done

# Generate book data for JavaScript instead of positioning elements directly
floatingBooks=""
b=0
cntBooks=${#BOOK_NAMES[@]}
while [ $b -lt $cntBooks ]; do
  bookName="${BOOK_NAMES[$b]}"
  safeBook="$(slugify "$bookName")"
  newestSlug="$(get_newest_chapter_filename "$bookName")"
  [ -z "$newestSlug" ] && newestSlug="#"

  floatingBooks="$floatingBooks<div class=\"floating\" data-factor=\"0.02\" data-book=\"$bookName\">
    <a href=\"chapters/$newestSlug\">
      <img draggable=\"false\" src=\"$safeBook.$BOOK_IMG_EXT\" alt=\"$bookName\" />
    </a>
</div>
"
  b=$((b+1))
done

homeHTML="${homeHTML/<!--AUTHORS_MENU-->/$authorsMenu}"
homeHTML="${homeHTML/<!--FLOATING_BOOKS-->/$floatingBooks}"

echo "$homeHTML" > "$OUTPUT_HOME"
echo "Generated homepage at $OUTPUT_HOME"

##############################################################################
# 404 PAGE
##############################################################################
cat <<EOF > "$BUILD_DIR/404.html"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>404 - Page Not Found</title>
</head>
<body>
  <h1>404 - Page Not Found</h1>
  <p>Oops! This page doesn't exist.</p>
  <p><a href="../index.html">Back to Home</a></p>
</body>
</html>
EOF

##############################################################################
# AUTHOR PAGES - SORT BY DATE DESC (NEWEST FIRST)
##############################################################################

cntAuthors=${#UNIQUE_AUTHORS[@]}
a=0
while [ $a -lt $cntAuthors ]; do
  authorName="${UNIQUE_AUTHORS[$a]}"
  safeAuthor="$(slugify "$authorName")"
  outFile="$BUILD_DIR/authors/$safeAuthor.html"

  cat <<EOF > "$outFile"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>$SITE_TITLE - Author: $authorName</title>
</head>
<body>
  <h1>Author: $authorName</h1>
  <p><a href="../index.html">Home</a></p>
  <hr/>
  <ul>
EOF

  # We'll gather matched chapters in a "lines" variable: "YYYY-MM-DD\tINDEX"
  lines=""
  cIndex=0
  while [ $cIndex -lt $CHAPTER_COUNT ]; do
    raw="${CHAPTER_RAW_AUTHORS[$cIndex]}"
    match=0
    while read -r oneAuth; do
      if [ "$oneAuth" = "$authorName" ]; then
        match=1
        break
      fi
    done < <(split_by_commas "$raw")

    if [ $match -eq 1 ]; then
      # We'll store lines so we can sort them by date desc
      dt="${CHAPTER_DATES[$cIndex]}"
      lines="$lines$dt\t$cIndex
"
    fi
    cIndex=$((cIndex+1))
  done

  # Now sort lines by date descending:
  # e.g. "sort -r" will put newest date at top
  sorted="$(echo -e "$lines" | sort -r)"

  # Output them in sorted order
  while IFS=$'\t' read -r dateVal idxVal; do
    localSlug="${CHAPTER_SLUGS[$idxVal]}"
    localTitle="${CHAPTER_TITLES[$idxVal]}"
    echo "    <li><a href=\"../chapters/$localSlug\">$localTitle</a> ($dateVal)</li>" >> "$outFile"
  done <<< "$sorted"

  cat <<EOF >> "$outFile"
  </ul>
</body>
</html>
EOF

  a=$((a+1))
done

##############################################################################
# YEAR PAGES
##############################################################################

haveMonthChapters() {
  hmYear="$1"
  hmMonth="$2"
  found=0
  idx=0
  while [ $idx -lt $CHAPTER_COUNT ]; do
    dd="${CHAPTER_DATES[$idx]}"
    yy="${dd:0:4}"
    mm="${dd:5:2}"
    if [ "$yy" = "$hmYear" ] && [ "$mm" = "$hmMonth" ]; then
      found=1
      break
    fi
    idx=$((idx+1))
  done
  return $found
}

cntYears=${#UNIQUE_YEARS[@]}
y=0
while [ $y -lt $cntYears ]; do
  yearNumber="${UNIQUE_YEARS[$y]}"
  outFile="$BUILD_DIR/years/$yearNumber.html"

  cat <<EOF > "$outFile"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>$SITE_TITLE - Year: $yearNumber</title>
</head>
<body>
  <h1>Year: $yearNumber</h1>
  <p><a href="../index.html">Home</a></p>
  <hr/>
  <aside style="float:left; width: 20%;">
    <h2>Months</h2>
    <ul>
EOF

  for m in {01..12}; do
    haveMonthChapters "$yearNumber" "$m"
    if [ $? -eq 1 ]; then
      echo "      <li><a href=\"#month-$m\">Month $m</a></li>" >> "$outFile"
    fi
  done

  cat <<EOF >> "$outFile"
    </ul>
  </aside>
  <div style="margin-left: 22%;">
EOF

  # list chapters by month
  mm=1
  while [ $mm -le 12 ]; do
    mon="$(printf "%02d" "$mm")"
    foundCh=()
    idx=0
    while [ $idx -lt $CHAPTER_COUNT ]; do
      dd="${CHAPTER_DATES[$idx]}"
      yy="${dd:0:4}"
      mo="${dd:5:2}"
      if [ "$yy" = "$yearNumber" ] && [ "$mo" = "$mon" ]; then
        foundCh+=("$idx")
      fi
      idx=$((idx+1))
    done

    if [ ${#foundCh[@]} -gt 0 ]; then
      echo "    <h2 id=\"month-$mon\">Month $mon</h2>" >> "$outFile"
      echo "    <ul>" >> "$outFile"
      fcIndex=0
      while [ $fcIndex -lt ${#foundCh[@]} ]; do
        fc="${foundCh[$fcIndex]}"
        localSlug="${CHAPTER_SLUGS[$fc]}"
        localTitle="${CHAPTER_TITLES[$fc]}"
        echo "      <li><a href=\"../chapters/$localSlug\">$localTitle</a></li>" >> "$outFile"
        fcIndex=$((fcIndex+1))
      done
      echo "    </ul>" >> "$outFile"
    fi
    mm=$((mm+1))
  done

  cat <<EOF >> "$outFile"
  </div>
</body>
</html>
EOF

  y=$((y+1))
done

##############################################################################
# CHAPTER PAGES
##############################################################################

make_chapter_sidebar() {
  primaryBook="$1"
  currentIndex="$2"

  idx="$(find_book_index_by_name "$primaryBook")"
  if [ "$idx" -lt 0 ]; then
    echo "<div class=\"chapterSidebar\"><p>No Book Found</p></div>"
    return
  fi

  chList="${BOOK_CHAPTER_LIST[$idx]}"
  chList="$(trim_spaces "$chList")"
  read -r -a arr <<< "$chList"

  sidebar="<div class=\"chapterSidebar\"><ul>"
  oneIdx=0
  while [ $oneIdx -lt ${#arr[@]} ]; do
    cIndex2="${arr[$oneIdx]}"
    cSlug="${CHAPTER_SLUGS[$cIndex2]}"
    cTitle="${CHAPTER_TITLES[$cIndex2]}"
    if [ "$cIndex2" -eq "$currentIndex" ]; then
      sidebar="$sidebar<li><strong>$cTitle</strong></li>"
    else
      sidebar="$sidebar<li><a href=\"$cSlug\">$cTitle</a></li>"
    fi
    oneIdx=$((oneIdx+1))
  done

  sidebar="$sidebar</ul></div>"
  echo "$sidebar"
}

get_prev_next() {
  primaryBook="$1"
  currentIndex="$2"

  idx="$(find_book_index_by_name "$primaryBook")"
  if [ "$idx" -lt 0 ]; then
    echo ""
    return
  fi

  chList="${BOOK_CHAPTER_LIST[$idx]}"
  chList="$(trim_spaces "$chList")"
  read -r -a arr <<< "$chList"

  position=0
  i=0
  while [ $i -lt ${#arr[@]} ]; do
    if [ "${arr[$i]}" = "$currentIndex" ]; then
      position=$i
      break
    fi
    i=$((i+1))
  done

  prevIndex=""
  nextIndex=""
  if [ $position -gt 0 ]; then
    prevIndex="${arr[$((position-1))]}"
  fi
  if [ $position -lt $(( ${#arr[@]} - 1 )) ]; then
    nextIndex="${arr[$((position+1))]}"
  fi
  echo "$prevIndex $nextIndex"
}

ch=0
while [ $ch -lt $CHAPTER_COUNT ]; do
  outSlug="${CHAPTER_SLUGS[$ch]}"
  title="${CHAPTER_TITLES[$ch]}"
  rawAuthors="${CHAPTER_RAW_AUTHORS[$ch]}"
  primaryBook="${CHAPTER_PRIMARY_BOOK[$ch]}"
  date="${CHAPTER_DATES[$ch]}"
  bodyClass="${CHAPTER_BODYCLASS[$ch]}"
  content="${CHAPTER_CONTENTS[$ch]}"

  outFile="$BUILD_DIR/chapters/$outSlug"

  sidebar="$(make_chapter_sidebar "$primaryBook" "$ch")"
  pn="$(get_prev_next "$primaryBook" "$ch")"
  prevIdx="$(echo "$pn" | awk '{print $1}')"
  nextIdx="$(echo "$pn" | awk '{print $2}')"

  cat <<EOF > "$outFile"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>$SITE_TITLE - $title</title>
  <style>
    .chapterNav {
      position: fixed; top: 50%;
      width: 40px; height: 40px;
      margin-top: -20px;
      text-align: center; line-height: 40px;
      font-size: 24px; font-weight: bold;
      cursor: pointer;
      z-index: 2000;
    }
    .chapterNav.left { left: 0; }
    .chapterNav.right { right: 0; }

    .chapterSidebar {
      position: fixed; top: 0; bottom: 0; left: 0;
      width: 250px; padding: 10px;
      overflow-y: auto;
      z-index: 1000;
    }
    .chapterContent {
      margin-left: 270px; padding: 20px;
    }
  </style>
</head>
<body class="$bodyClass">
  $sidebar
EOF

  if [ -n "$prevIdx" ]; then
    prevSlug="${CHAPTER_SLUGS[$prevIdx]}"
    echo "  <a class=\"chapterNav left\" href=\"$prevSlug\">«</a>" >> "$outFile"
  fi
  if [ -n "$nextIdx" ]; then
    nextSlug="${CHAPTER_SLUGS[$nextIdx]}"
    echo "  <a class=\"chapterNav right\" href=\"$nextSlug\">»</a>" >> "$outFile"
  fi

  cat <<EOF >> "$outFile"
  <div class="chapterContent">
    <header>
      <a href="../index.html">Home</a> |
      <strong>Book(s):</strong> $primaryBook
    </header>
    <hr/>
    <h1>$title</h1>
    <p><strong>Authors:</strong> $rawAuthors<br/>
       <strong>Book(s):</strong> $primaryBook<br/>
       <strong>Date:</strong> $date</p>
    <div>
$content
    </div>
  </div>
</body>
</html>
EOF

  ch=$((ch+1))
done

echo "Done! The multi-page site is in '$BUILD_DIR/'."
echo "Open '$BUILD_DIR/index.html' in a browser to see your new homepage!"

#!/usr/bin/env bash
# Enable extended pattern matching for trimming
shopt -s extglob

# ─────────────────────────────────────────────────────────────────────────────
# Meñique Generator
# Usage: bash build.sh
# ─────────────────────────────────────────────────────────────────────────────

CHAPTERS_DIR="chapters"
IMAGES_DIR="images"
BUILD_DIR="build"
TEMPLATES_DIR="templates"
BASE_URL="http://meñique.com.ar"

# Create necessary directories
mkdir -p "$BUILD_DIR" "$BUILD_DIR/authors" "$BUILD_DIR/chapters" "$BUILD_DIR/images"

SITE_TITLE="Meñique Audiovisual"
BOOK_IMG_EXT="png"

##############################################################################
# Utility functions
##############################################################################

trim_spaces() {
  var="$1"
  var="${var#"${var%%[![:space:]]*}"}"  # remove leading spaces
  var="${var%"${var##*[![:space:]]}"}"  # remove trailing spaces
  echo "$var"
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//'
}

sanitize_filename() {
  base="${1%.*}"
  echo "$(slugify "$base").html"
}

split_by_commas() {
  line="$1"
  oldIFS="$IFS"
  IFS=',' read -ra tokens <<< "$line"
  IFS="$oldIFS"
  for token in "${tokens[@]}"; do
    trim_spaces "$token"
  done
}

join_with_y() {
  arr=("$@")
  count=${#arr[@]}
  if [ $count -eq 0 ]; then
    echo ""
    return
  elif [ $count -eq 1 ]; then
    echo "${arr[0]}"
    return
  fi
  joined="${arr[0]}"
  for ((i=1; i<count; i++)); do
    joined="$joined y ${arr[i]}"
  done
  echo "$joined"
}

##############################################################################
# Book storing functions
##############################################################################

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
    chList="${BOOK_CHAPTER_LIST[$i]}"
    chList="$(trim_spaces "$chList")"
    lines=""
    for cIdx in $chList; do
      dt="${CHAPTER_DATES[$cIdx]}"
      lines="$lines$dt\t$cIdx"$'\n'
    done
    sorted="$(echo -e "$lines" | sort)"
    finalIndices=""
    while IFS=$'\t' read -r dateVal idxVal; do
      finalIndices="$finalIndices $idxVal"
    done <<< "$sorted"
    BOOK_CHAPTER_LIST[$i]="$(trim_spaces "$finalIndices")"
    i=$((i+1))
  done
}

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
declare -a CHAPTER_RAW_RADIOS
declare -a CHAPTER_RAW_LOCATIONS
declare -a CHAPTER_DATES
declare -a CHAPTER_BODYCLASS
declare -a CHAPTER_CONTENTS
declare -a CHAPTER_PRIMARY_BOOK
declare -a UNIQUE_AUTHORS
declare -a UNIQUE_YEARS
declare -a BOOK_NAMES
declare -a BOOK_CHAPTER_LIST

##############################################################################
# Parsing chapters (split header and content; trim blank line)
##############################################################################

parse_chapter() {
  file="$1"
  header=""
  content=""
  readingHeader=1
  while IFS= read -r line; do
    trimmed="$(trim_spaces "$line")"
    if [ "$readingHeader" -eq 1 ] && [ -z "$trimmed" ]; then
      readingHeader=0
      continue
    fi
    if [ "$readingHeader" -eq 1 ]; then
      header="${header}${line}"$'\n'
    else
      content="${content}${line}"$'\n'
    fi
  done < "$file"

  cTitle="Untitled"
  cAuthors=""
  cBooks=""
  cRadios=""
  cLocations=""
  cDate="1900-01-01"
  cClass=""

  while IFS= read -r hline; do
    case "$hline" in
      Title:*)
         cTitle="$(trim_spaces "${hline#Title:}")"
         ;;
      Author:*)
         cAuthors="$(trim_spaces "${hline#Author:}")"
         ;;
      Book:*)
         cBooks="$(trim_spaces "${hline#Book:}")"
         ;;
      Radio:*)
         cRadios="$(trim_spaces "${hline#Radio:}")"
         ;;
      Location:*)
         cLocations="$(trim_spaces "${hline#Location:}")"
         ;;
      Published:*)
         cDate="$(trim_spaces "${hline#Published:}")"
         cDate="${cDate%%T*}"
         [ -z "$cDate" ] && cDate="1900-01-01"
         ;;
      BodyClass:*)
         cClass="$(trim_spaces "${hline#BodyClass:}")"
         ;;
    esac
  done <<< "$header"

  baseName="$(basename "$file")"
  safeHtml="$(sanitize_filename "$baseName")"

  CHAPTER_FILENAMES[$CHAPTER_COUNT]="$baseName"
  CHAPTER_SLUGS[$CHAPTER_COUNT]="$safeHtml"
  CHAPTER_TITLES[$CHAPTER_COUNT]="$cTitle"
  CHAPTER_RAW_AUTHORS[$CHAPTER_COUNT]="$cAuthors"
  CHAPTER_RAW_BOOKS[$CHAPTER_COUNT]="$cBooks"
  CHAPTER_RAW_RADIOS[$CHAPTER_COUNT]="$cRadios"
  CHAPTER_RAW_LOCATIONS[$CHAPTER_COUNT]="$cLocations"
  CHAPTER_DATES[$CHAPTER_COUNT]="$cDate"
  CHAPTER_BODYCLASS[$CHAPTER_COUNT]="$cClass"
  CHAPTER_CONTENTS[$CHAPTER_COUNT]="$content"

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
  echo "ERROR: No .txt chapters found in '$CHAPTERS_DIR'."
fi

##############################################################################
# Fill arrays
##############################################################################

i=0
while [ $i -lt $CHAPTER_COUNT ]; do
  # Process Authors
  authorLine="${CHAPTER_RAW_AUTHORS[$i]}"
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

  # Process Books: add only nonempty values
  bookLine="${CHAPTER_RAW_BOOKS[$i]}"
  booksArray=()
  while IFS= read -r oneBook; do
    if [ -n "$oneBook" ]; then
      booksArray+=("$oneBook")
    fi
  done < <(split_by_commas "$bookLine")

  if [ ${#booksArray[@]} -gt 0 ]; then
    CHAPTER_PRIMARY_BOOK[$i]="${booksArray[0]}"
  else
    CHAPTER_PRIMARY_BOOK[$i]=""
  fi

  for bName in "${booksArray[@]}"; do
    if [ -n "$bName" ]; then
      set_book_chapters "$bName" "$i"
    fi
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
  echo "ERROR: $TEMPLATE_HOME not found."
  exit 1
fi

homeHTML=""
while IFS= read -r line; do
  homeHTML="${homeHTML}${line}"$'\n'
done < "$TEMPLATE_HOME"

authorsMenu=""
k=0
while [ $k -lt ${#UNIQUE_AUTHORS[@]} ]; do
  authorName="${UNIQUE_AUTHORS[$k]}"
  localSlug="$(slugify "$authorName")"
  authorsMenu="${authorsMenu}<a href=\"authors/$localSlug.html\">$authorName</a>"$'\n'
  k=$((k+1))
done

floatingBooks=""
b=0
cntBooks=${#BOOK_NAMES[@]}
while [ $b -lt $cntBooks ]; do
  bookName="${BOOK_NAMES[$b]}"
  if [ -z "$bookName" ]; then
    b=$((b+1))
    continue
  fi
  safeBook="$(slugify "$bookName")"
  newestSlug="$(get_newest_chapter_filename "$bookName")"
  [ -z "$newestSlug" ] && newestSlug="#"
  floatingBooks="${floatingBooks}<div class=\"floating\" data-factor=\"0.02\" data-book=\"$bookName\">
    <a href=\"chapters/$newestSlug\">
      <img draggable=\"false\" loading=\"lazy\" src=\"/images/$safeBook.$BOOK_IMG_EXT\" alt=\"$bookName\" />
    </a>
</div>"$'\n'
  b=$((b+1))
done

homeHTML="${homeHTML/<!--AUTHORS_MENU-->/$authorsMenu}"
homeHTML="${homeHTML/<!--FLOATING_BOOKS-->/$floatingBooks}"

echo "$homeHTML" > "$OUTPUT_HOME"

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
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
  <title>$authorName - $SITE_TITLE</title>
</head>
<body>
  <h1>Todo lo de $authorName</h1>
  <p><a href="../index.html">$SITE_TITLE</a></p>
  <hr/>
EOF

  lines=""
  cIndex=0
  while [ $cIndex -lt $CHAPTER_COUNT ]; do
    rawAuthors="${CHAPTER_RAW_AUTHORS[$cIndex]}"
    match=0
    while read -r oneAuth; do
      if [ "$oneAuth" = "$authorName" ]; then
        match=1
        break
      fi
    done < <(split_by_commas "$rawAuthors")
    if [ $match -eq 1 ]; then
      dt="${CHAPTER_DATES[$cIndex]}"
      lines="${lines}${dt}\t$cIndex"$'\n'
    fi
    cIndex=$((cIndex+1))
  done

  sorted="$(echo -e "$lines" | sort -r)"
  lastYear=""
  firstYearFound=0
  while IFS=$'\t' read -r dateVal idxVal; do
    year="${dateVal:0:4}"
    if [ "$year" != "$lastYear" ]; then
      if [ -n "$lastYear" ]; then
        echo "</ul>" >> "$outFile"
      fi
      echo "<h2>$year</h2>" >> "$outFile"
      echo "<ul>" >> "$outFile"
      lastYear="$year"
      firstYearFound=1
    fi
    localSlug="${CHAPTER_SLUGS[$idxVal]}"
    localTitle="${CHAPTER_TITLES[$idxVal]}"
    echo "  <li><a href=\"../chapters/$localSlug\">$localTitle</a> ($dateVal)</li>" >> "$outFile"
  done <<< "$sorted"
  if [ $firstYearFound -eq 1 ]; then
    echo "</ul>" >> "$outFile"
  fi
  cat <<EOF >> "$outFile"
</body>
</html>
EOF
  a=$((a+1))
done

##############################################################################
# CHAPTER PAGES (with sidebar)
##############################################################################

# Updated sidebar function: shows site title (linked to home) on top and groups chapters by year.
make_chapter_sidebar() {
  primaryBook="$1"
  currentIndex="$2"
  # Start with site title linked to home
  sidebar="<div class=\"chapterSidebar\"><div class=\"site-title\"><a href=\"${BASE_URL}/index.html\">$SITE_TITLE</a></div>"
  if [ -n "$primaryBook" ]; then
    idx="$(find_book_index_by_name "$primaryBook")"
    if [ "$idx" -ge 0 ]; then
      chList="${BOOK_CHAPTER_LIST[$idx]}"
    else
      chList=""
    fi
  else
    # If no primary book, group all chapters with no book.
    chList=""
    for (( i=0; i<CHAPTER_COUNT; i++ )); do
      if [ -z "${CHAPTER_PRIMARY_BOOK[$i]}" ]; then
        chList="$chList $i"
      fi
    done
  fi
  chList="$(trim_spaces "$chList")"
  lines=""
  for idx in $chList; do
      dt="${CHAPTER_DATES[$idx]}"
      lines="$lines${dt}\t$idx"$'\n'
  done
  sorted="$(echo -e "$lines" | sort -r)"
  lastYear=""
  haveOpenUl=0
  while IFS=$'\t' read -r dateVal idxVal; do
      year="${dateVal:0:4}"
      if [ "$year" != "$lastYear" ]; then
          if [ "$haveOpenUl" -eq 1 ]; then
              sidebar="$sidebar</ul>"
          fi
          sidebar="$sidebar<h3>$year</h3><ul>"
          haveOpenUl=1
          lastYear="$year"
      fi
      cSlug="${CHAPTER_SLUGS[$idxVal]}"
      cTitle="${CHAPTER_TITLES[$idxVal]}"
      if [ "$idxVal" -eq "$currentIndex" ]; then
          sidebar="$sidebar<li><strong>$cTitle</strong></li>"
      else
          sidebar="$sidebar<li><a href=\"../chapters/$cSlug\">$cTitle</a></li>"
      fi
  done <<< "$sorted"
  if [ "$haveOpenUl" -eq 1 ]; then
      sidebar="$sidebar</ul>"
  fi
  sidebar="$sidebar</div>"
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
  authorArray=()
  while IFS= read -r oneAuth; do
    [ -z "$oneAuth" ] && continue
    aSlug="$(slugify "$oneAuth")"
    authorArray+=("<a href=\"../authors/$aSlug.html\">$oneAuth</a>")
  done < <(split_by_commas "$rawAuthors")
  joinedAuthors="$(join_with_y "${authorArray[@]}")"

  rawBooks="${CHAPTER_RAW_BOOKS[$ch]}"
  bookArray=()
  while IFS= read -r oneBook; do
    [ -z "$oneBook" ] && continue
    bookArray+=("$oneBook")
  done < <(split_by_commas "$rawBooks")
  joinedBooks="$(join_with_y "${bookArray[@]}")"

  rawRadios="${CHAPTER_RAW_RADIOS[$ch]}"
  radioArray=()
  while IFS= read -r oneRadio; do
    [ -z "$oneRadio" ] && continue
    radioArray+=("$oneRadio")
  done < <(split_by_commas "$rawRadios")
  joinedRadios="$(join_with_y "${radioArray[@]}")"

  rawLocations="${CHAPTER_RAW_LOCATIONS[$ch]}"
  locationArray=()
  while IFS= read -r oneLoc; do
    [ -z "$oneLoc" ] && continue
    locationArray+=("$oneLoc")
  done < <(split_by_commas "$rawLocations")
  joinedLocations="$(join_with_y "${locationArray[@]}")"

  primaryBook="${CHAPTER_PRIMARY_BOOK[$ch]}"
  date="${CHAPTER_DATES[$ch]}"
  bodyClass="${CHAPTER_BODYCLASS[$ch]}"
  content="${CHAPTER_CONTENTS[$ch]}"
  outFile="$BUILD_DIR/chapters/$outSlug"

  sidebar="$(make_chapter_sidebar "$primaryBook" "$ch")"
  if [ -n "$primaryBook" ]; then
    pn="$(get_prev_next "$primaryBook" "$ch")"
    prevIdx="$(echo "$pn" | awk '{print $1}')"
    nextIdx="$(echo "$pn" | awk '{print $2}')"
  else
    prevIdx=""
    nextIdx=""
  fi

  metadataLine1=""
  if [ -n "$joinedRadios" ]; then
    metadataLine1="Desde el éter de $joinedRadios"
  fi
  if [ -n "$joinedLocations" ]; then
    if [ -n "$metadataLine1" ]; then
      metadataLine1="$metadataLine1, $joinedLocations"
    else
      metadataLine1="$joinedLocations"
    fi
  fi
  if [ -n "$date" ]; then
    if [ -n "$metadataLine1" ]; then
      metadataLine1="$metadataLine1, un $date"
    else
      metadataLine1="un $date"
    fi
  fi

  metadataLine2="Palabras de $joinedAuthors"
  if [ -n "$joinedBooks" ]; then
    metadataLine2="$metadataLine2 para $joinedBooks"
  fi

  cat <<EOF > "$outFile"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
  <title>$title - $SITE_TITLE</title>
  <style>
    @media only screen and (max-width: 600px) {
        .chapterContent { margin-left: unset !important; }
        .chapterSidebar { position: unset !important; width: unset !important; padding: 60px !important; }
    }
    body { font-family: sans-serif; font-size: clamp(1em, 2vw, 1.4em); line-height: 1.6; }
    .chapterNav { position: fixed; top: 50%; width: 40px; height: 40px; margin-top: -20px; text-align: center; line-height: 40px; font-size: 24px; font-weight: bold; cursor: pointer; z-index: 2000; }
    .chapterNav.left { translate: -50px 0; }
    .chapterNav.right { left: clamp(16rem, 100vw - 50px, 16rem + 40em + 10px); }
    .chapterSidebar { position: fixed; top: 0; bottom: 0; left: 0; width: 16rem; padding: 10px; overflow-y: auto; z-index: 1000; }
    .chapterSidebar>* { line-height: 1.6rem; }
    .chapterSidebar h3 { margin-top: 1rem; font-size: 1.1rem; }
    .chapterSidebar ul { list-style: none; padding: unset; }
    .chapterSidebar li { margin-bottom: 1rem; font-size: 1rem; }
    .chapterSidebar a { text-decoration: none; }
    .site-title { font-size: 1.3em; font-weight: bold; margin-bottom: 0.5em; }
    .chapterContent { margin-left: 16rem; padding: 60px; max-width: 40em; }
    h1 { font-size: clamp(2em, 4vw, 6em); line-height: 1em; }
    .book-image-container { margin-bottom: 1rem; }
    .book-image-container img { width: 10em; margin-right: 1rem; }
  </style>
</head>
<body class="$bodyClass">
  <div class="chapterContent">
    <div class="book-image-container">
EOF

  for bName in "${bookArray[@]}"; do
    safeBook="$(slugify "$bName")"
    echo "      <img loading=\"lazy\" src=\"/images/$safeBook.$BOOK_IMG_EXT\" alt=\"$bName\" />" >> "$outFile"
  done

  cat <<EOF >> "$outFile"
    </div>
    <h1>$title</h1>
    <p>$metadataLine1</p>
    <p>$metadataLine2</p>
    <div>
$content
    </div>
EOF

  if [ -n "$prevIdx" ]; then
    prevSlug="${CHAPTER_SLUGS[$prevIdx]}"
    echo "    <a class=\"chapterNav left\" href=\"$prevSlug\">«</a>" >> "$outFile"
  fi
  if [ -n "$nextIdx" ]; then
    nextSlug="${CHAPTER_SLUGS[$nextIdx]}"
    echo "    <a class=\"chapterNav right\" href=\"$nextSlug\">»</a>" >> "$outFile"
  fi

  cat <<EOF >> "$outFile"
  </div>
  $sidebar
</body>
</html>
EOF

  ch=$((ch+1))
done

##############################################################################
# COPY IMAGES
##############################################################################
cp -r "$IMAGES_DIR/"* "$BUILD_DIR/images/"

##############################################################################
# COPY robots.txt (if exists)
##############################################################################
if [ -f "robots.txt" ]; then
  cp "robots.txt" "$BUILD_DIR/robots.txt"
fi

##############################################################################
# Build RSS Feed
##############################################################################
rss_temp=""
for ((i=0; i<CHAPTER_COUNT; i++)); do
  dt="${CHAPTER_DATES[$i]}"
  rss_temp="${rss_temp}${dt}\t$i"$'\n'
done
sorted_rss="$(echo -e "$rss_temp" | sort -r)"
rss_items=""
while IFS=$'\t' read -r pubDate idx; do
  rfc_date=$(date -d "$pubDate" -R 2>/dev/null)
  if [ -z "$rfc_date" ]; then
    rfc_date="$pubDate"
  fi
  title="${CHAPTER_TITLES[$idx]}"
  slug="${CHAPTER_SLUGS[$idx]}"
  link="${BASE_URL}/chapters/${slug}"
  description="${CHAPTER_CONTENTS[$idx]}"
  rss_items="${rss_items}<item>
  <title>${title}</title>
  <link>${link}</link>
  <pubDate>${rfc_date}</pubDate>
  <description><![CDATA[${description}]]></description>
</item>"$'\n'
done <<< "$sorted_rss"

rss_feed="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<rss version=\"2.0\">
<channel>
  <title>${SITE_TITLE}</title>
  <link>${BASE_URL}</link>
  <description>RSS Feed for ${SITE_TITLE}</description>
  <lastBuildDate>$(date -R)</lastBuildDate>
  <pubDate>$(date -R)</pubDate>
${rss_items}
</channel>
</rss>"

echo "$rss_feed" > "$BUILD_DIR/rss.xml"

#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────────────────
# Meñique Audiovisual Site Generator
# (No "local" usage, no "declare -A", uses a home page template)
# ─────────────────────────────────────────────────────────────────────────────
#
# 1) Looks in "chapters/" for .txt files with front matter:
#      Title: ...
#      Author: ...
#      Book: ...
#      Published: YYYY-MM-DD
#      BodyClass: ...
#    (blank line, then raw HTML)
# 2) Gathers that data into arrays.
# 3) Builds:
#    - build/index.html using templates/home.html (inserting placeholders)
#    - build/404.html
#    - build/books/<book>.html
#    - build/authors/<author>.html
#    - build/years/<year>.html
#    - build/chapters/<filename>.html
# 4) Avoids advanced Bash features so it runs in older shells (like macOS default).
# ─────────────────────────────────────────────────────────────────────────────

CHAPTERS_DIR="chapters"
IMAGES_DIR="images"
BUILD_DIR="build"
TEMPLATES_DIR="templates"

# Name that appears in <title> or page headings
SITE_TITLE="Meñique Audiovisual"

# The body class used for the home page
HOMEPAGE_BODYCLASS="home-page"

# The default extension used for book images
BOOK_IMG_EXT="png"

# 1) Ensure minimal folders exist or create them
if [ ! -d "$CHAPTERS_DIR" ]; then
  echo "No '$CHAPTERS_DIR' folder found. Creating it..."
  mkdir "$CHAPTERS_DIR"
  cat <<EOF > "$CHAPTERS_DIR/sample-chapter.txt"
Title: El viaje increíble
Author: Juana Lujan
Book: Monstruos
Published: 2022-05-15
Tags: fancy-chapter

<p>This is a <strong>sample chapter</strong> with a custom body class <code>fancy-chapter</code>.</p>
<p>Feel free to edit or remove this sample file.</p>
EOF
  echo "Created '$CHAPTERS_DIR/sample-chapter.txt' as an example."
fi

if [ ! -d "$IMAGES_DIR" ]; then
  echo "No '$IMAGES_DIR' folder found. Creating it..."
  mkdir "$IMAGES_DIR"
  echo "(Optional) Place your images in '$IMAGES_DIR'."
fi

mkdir -p "$BUILD_DIR" "$BUILD_DIR/books" "$BUILD_DIR/authors" "$BUILD_DIR/years" "$BUILD_DIR/chapters"

# 2) Global arrays for chapters
CHAPTER_COUNT=0
declare -a CHAPTER_FILENAMES
declare -a CHAPTER_TITLES
declare -a CHAPTER_AUTHORS
declare -a CHAPTER_BOOKS
declare -a CHAPTER_DATES
declare -a CHAPTER_TAGS
declare -a CHAPTER_CONTENTS

# Arrays for unique sets
declare -a UNIQUE_BOOKS
declare -a UNIQUE_AUTHORS
declare -a UNIQUE_YEARS

# 3) parse_chapter (reads metadata + HTML)
parse_chapter() {
  file="$1"

  cTitle="Untitled"
  cAuthor="Unknown"
  cBook="Misc"
  cDate="1900-01-01"
  cClass=""
  cContent=""

  # read lines until blank
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      break
    fi
    case "$line" in
      Title:*)
        cTitle="${line#Title:}"
        cTitle="$(echo "$cTitle" | xargs)"
        ;;
      Author:*)
        cAuthor="${line#Author:}"
        cAuthor="$(echo "$cAuthor" | xargs)"
        ;;
      Book:*)
        cBook="${line#Book:}"
        cBook="$(echo "$cBook" | xargs)"
        ;;
      Published:*)
        cDate="${line#Published:}"
        cDate="$(echo "$cDate" | xargs)"
        ;;
      Tags:*)
        cClass="${line#Tags:}"
        cClass="$(echo "$cClass" | xargs)"
        ;;
    esac
  done < "$file"

  # read rest as HTML
  htmlBuffer=""
  while IFS= read -r leftover; do
    htmlBuffer="$htmlBuffer$leftover
"
  done < <(tail -n +1 "$file" | sed '1,/^$/d')

  cContent="$htmlBuffer"

  # store
  CHAPTER_FILENAMES[$CHAPTER_COUNT]="$(basename "$file")"
  CHAPTER_TITLES[$CHAPTER_COUNT]="$cTitle"
  CHAPTER_AUTHORS[$CHAPTER_COUNT]="$cAuthor"
  CHAPTER_BOOKS[$CHAPTER_COUNT]="$cBook"
  CHAPTER_DATES[$CHAPTER_COUNT]="$cDate"
  CHAPTER_TAGS[$CHAPTER_COUNT]="$cClass"
  CHAPTER_CONTENTS[$CHAPTER_COUNT]="$cContent"

  CHAPTER_COUNT=$((CHAPTER_COUNT+1))
}

# 4) read all .txt
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

# 5) function: check if array contains item
contains_item() {
  item="$1"
  shift
  arrayToCheck=("$@")
  for x in "${arrayToCheck[@]}"; do
    if [ "$x" = "$item" ]; then
      return 0
    fi
  done
  return 1
}

# 6) fill unique arrays
i=0
while [ $i -lt $CHAPTER_COUNT ]; do
  bk="${CHAPTER_BOOKS[$i]}"
  au="${CHAPTER_AUTHORS[$i]}"
  dt="${CHAPTER_DATES[$i]}"
  yr="${dt:0:4}"

  contains_item "$bk" "${UNIQUE_BOOKS[@]}"
  if [ $? -ne 0 ]; then
    UNIQUE_BOOKS+=( "$bk" )
  fi

  contains_item "$au" "${UNIQUE_AUTHORS[@]}"
  if [ $? -ne 0 ]; then
    UNIQUE_AUTHORS+=( "$au" )
  fi

  contains_item "$yr" "${UNIQUE_YEARS[@]}"
  if [ $? -ne 0 ]; then
    UNIQUE_YEARS+=( "$yr" )
  fi

  i=$((i+1))
done

##############################################################################
# HOMEPAGE GENERATION using templates/home.html
##############################################################################
TEMPLATE_HOME="$TEMPLATES_DIR/home.html"
OUTPUT_HOME="$BUILD_DIR/index.html"

if [ ! -f "$TEMPLATE_HOME" ]; then
  echo "Error: $TEMPLATE_HOME not found. Create it with <!--AUTHORS_MENU--> and <!--FLOATING_BOOKS--> placeholders."
  exit 1
fi

# read template into a variable
homeHTML=""
while IFS= read -r line; do
  homeHTML="$homeHTML$line
"
done < "$TEMPLATE_HOME"

# Build authors menu
authorsMenu=""
for authorName in "${UNIQUE_AUTHORS[@]}"; do
  # slugify or just link
  safeAuthor="$(echo "$authorName" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
  authorsMenu="$authorsMenu<a href=\"authors/$safeAuthor.html\">$authorName</a>\n"
done

# Build floating books
posTop=20
posLeft=10
increment=15
floatingBooks=""
for bookName in "${UNIQUE_BOOKS[@]}"; do
  safeBook="$(echo "$bookName" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
  # We'll link to an image $safeBook.$BOOK_IMG_EXT
  # If you want them clickable, wrap in <a href="books/$safeBook.html">..</a>
  floatingBooks="$floatingBooks<div
  class=\"floating\"
  style=\"top: ${posTop}%; left: ${posLeft}%\"
  data-factor=\"0.02\"
>
    <img draggable=\"false\" src=\"$safeBook.$BOOK_IMG_EXT\" alt=\"$bookName\" />
</div>

"
  posTop=$((posTop+increment))
  posLeft=$((posLeft+increment))
  if [ $posTop -gt 80 ]; then
    posTop=20
  fi
  if [ $posLeft -gt 80 ]; then
    posLeft=10
  fi
done

# Replace placeholders
homeHTML="${homeHTML/<!--AUTHORS_MENU-->/$authorsMenu}"
homeHTML="${homeHTML/<!--FLOATING_BOOKS-->/$floatingBooks}"

# Write final homepage
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
# UTILS (slugify, etc.)
##############################################################################
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

##############################################################################
# GENERATE BOOK PAGES
##############################################################################
for bookName in "${UNIQUE_BOOKS[@]}"; do
  safeBook="$(slugify "$bookName")"
  outFile="$BUILD_DIR/books/$safeBook.html"

  cat <<EOF > "$outFile"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>$SITE_TITLE - Book: $bookName</title>
</head>
<body>
  <h1>Book: $bookName</h1>
  <p><a href="../index.html">Home</a></p>
  <hr/>
  <h2>Chapters in "$bookName"</h2>
  <ul>
EOF

  j=0
  while [ $j -lt $CHAPTER_COUNT ]; do
    if [ "${CHAPTER_BOOKS[$j]}" = "$bookName" ]; then
      chapterFile="${CHAPTER_FILENAMES[$j]}"
      chapterTitle="${CHAPTER_TITLES[$j]}"
      echo "    <li><a href=\"../chapters/$chapterFile.html\">$chapterTitle</a></li>" >> "$outFile"
    fi
    j=$((j+1))
  done

  cat <<EOF >> "$outFile"
  </ul>
</body>
</html>
EOF
done

##############################################################################
# GENERATE AUTHOR PAGES
##############################################################################
for authorName in "${UNIQUE_AUTHORS[@]}"; do
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

  j=0
  while [ $j -lt $CHAPTER_COUNT ]; do
    if [ "${CHAPTER_AUTHORS[$j]}" = "$authorName" ]; then
      chapterFile="${CHAPTER_FILENAMES[$j]}"
      chapterTitle="${CHAPTER_TITLES[$j]}"
      echo "    <li><a href=\"../chapters/$chapterFile.html\">$chapterTitle</a></li>" >> "$outFile"
    fi
    j=$((j+1))
  done

  cat <<EOF >> "$outFile"
  </ul>
</body>
</html>
EOF
done

##############################################################################
# SORT UNIQUE_YEARS
##############################################################################
i=0
while [ $i -lt ${#UNIQUE_YEARS[@]} ]; do
  k=$((i+1))
  while [ $k -lt ${#UNIQUE_YEARS[@]} ]; do
    if [ "${UNIQUE_YEARS[$k]}" \< "${UNIQUE_YEARS[$i]}" ]; then
      temp="${UNIQUE_YEARS[$i]}"
      UNIQUE_YEARS[$i]="${UNIQUE_YEARS[$k]}"
      UNIQUE_YEARS[$k]="$temp"
    fi
    k=$((k+1))
  done
  i=$((i+1))
done

##############################################################################
# GENERATE YEAR PAGES
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

for yearNumber in "${UNIQUE_YEARS[@]}"; do
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

  # list chapters
  for m in {01..12}; do
    foundCh=()
    idx=0
    while [ $idx -lt $CHAPTER_COUNT ]; do
      dd="${CHAPTER_DATES[$idx]}"
      yy="${dd:0:4}"
      mm="${dd:5:2}"
      if [ "$yy" = "$yearNumber" ] && [ "$mm" = "$m" ]; then
        foundCh+=( "$idx" )
      fi
      idx=$((idx+1))
    done

    if [ ${#foundCh[@]} -gt 0 ]; then
      echo "    <h2 id=\"month-$m\">Month $m</h2>" >> "$outFile"
      echo "    <ul>" >> "$outFile"
      for fc in "${foundCh[@]}"; do
        chFile="${CHAPTER_FILENAMES[$fc]}"
        chTitle="${CHAPTER_TITLES[$fc]}"
        echo "      <li><a href=\"../chapters/$chFile.html\">$chTitle</a></li>" >> "$outFile"
      done
      echo "    </ul>" >> "$outFile"
    fi
  done

  cat <<EOF >> "$outFile"
  </div>
</body>
</html>
EOF
done

##############################################################################
# GENERATE INDIVIDUAL CHAPTER PAGES
##############################################################################
i=0
while [ $i -lt $CHAPTER_COUNT ]; do
  filename="${CHAPTER_FILENAMES[$i]}"
  title="${CHAPTER_TITLES[$i]}"
  author="${CHAPTER_AUTHORS[$i]}"
  book="${CHAPTER_BOOKS[$i]}"
  date="${CHAPTER_DATES[$i]}"
  bodyClass="${CHAPTER_TAGS[$i]}"
  content="${CHAPTER_CONTENTS[$i]}"

  outFile="$BUILD_DIR/chapters/$filename.html"
  cat <<EOF > "$outFile"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>$SITE_TITLE - $title</title>
</head>
<body class="$bodyClass">
  <header>
    <a href="../index.html">Home</a> |
    <a href="../books/$(slugify "$book").html">Book: $book</a> |
    <a href="../authors/$(slugify "$author").html">Author: $author</a>
  </header>
  <hr/>
  <h1>$title</h1>
  <p><strong>Author:</strong> $author<br/>
     <strong>Book:</strong> $book<br/>
     <strong>Date:</strong> $date</p>
  <div>
$content
  </div>
</body>
</html>
EOF

  i=$((i+1))
done

echo "Done! The multi-page site is in '$BUILD_DIR/'."
echo "Open '$BUILD_DIR/index.html' in a browser to see your new homepage!"

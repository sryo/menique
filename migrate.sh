#!/usr/bin/env bash
#
# migrate_blogger.sh
#
# Reads a Blogger XML export, finds posts, extracts:
#   - title, published date
#   - tags: but sorts them into Author, Book, Volume, Location, or leftover "Other tags"
#   - cleans up HTML content
#
# Usage:
#   ./migrate.sh input.xml output_dir

set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 input.xml output_dir"
  exit 1
fi

XMLFILE="$1"
OUTDIR="$2"

mkdir -p "$OUTDIR"

#########################
# Define recognized tags
#########################
AUTHORS=("yoko mona" "monoman" "flash" "mateoso" "cronopio")
BOOKS=(
  "el vengador justicialista" "flash deformativo" "flash performativo"
  "desde cosquin rock" "semblanzas deportivas" "el libro de nietzsche" "el cine negro de los monos" "la mancha del quijote"
  "temporada de migrañas" "el alquimista de los sueños" "videoclub del oso panza"
  "cosas que pasaron" "misiva lasciva" "chubut santa rosa y despues"
  "mutantes" "evatest positivo" "catalogos"
)
VOLUMES=("sangre de monos" "abortos de monos" "llegando los monos" "monopolis")
LOCATIONS=("cordoba" "rio ceballos" "villa allende" "la calera")

inEntry=0        # Are we inside <entry>?
isPost=0         # Does this <entry> represent a real blog post?
title=""
published=""
content=""
contentOpen=0
tags=""
idx=1

while IFS= read -r line; do

  # Detect <entry> start
  if [[ "$line" =~ \<entry\> ]]; then
    inEntry=1
    isPost=0
    title=""
    published=""
    content=""
    contentOpen=0
    tags=""
    continue
  fi

  # If we're in an <entry>, examine its lines
  if [ $inEntry -eq 1 ]; then

    # Identify if this is a Blogger post
    if [[ "$line" =~ "http://schemas.google.com/blogger/2008/kind#post" ]]; then
      isPost=1
    fi

    # Collect tags: <category scheme='http://www.blogger.com/atom/ns#' term='something'/>
    if [[ "$line" =~ \<category[[:space:]]+scheme=\'http://www.blogger.com/atom/ns#\'[^\']*term=\'([^\']+)\' ]]; then
      foundTag="${BASH_REMATCH[1]}"
      # Append to comma-separated string
      if [ -z "$tags" ]; then
        tags="$foundTag"
      else
        tags="$tags, $foundTag"
      fi
    fi

    # Extract <title>one-line</title>
    if [[ "$line" =~ \<title[^\>]*\>(.*)\</title\> ]]; then
      title="${BASH_REMATCH[1]}"
    fi

    # Extract <published>one-line</published>
    if [[ "$line" =~ \<published[^\>]*\>(.*)\</published\> ]]; then
      published="${BASH_REMATCH[1]}"
    fi

    # Detect the start of <content ...> (may continue multiple lines)
    if [[ "$line" =~ \<content[^\>]*\>(.*) ]]; then
      contentOpen=1
      remainder="${BASH_REMATCH[1]}"

      # If the same line also has </content>
      if [[ "$remainder" =~ (.*)\</content\> ]]; then
        contentOpen=0
        content+="${BASH_REMATCH[1]}"
      else
        content+="${remainder}\n"
      fi
      continue
    fi

    # If we're inside <content> and haven't seen </content> yet, keep reading
    if [ $contentOpen -eq 1 ]; then
      if [[ "$line" =~ (.*)\</content\> ]]; then
        contentOpen=0
        content+="${BASH_REMATCH[1]}"
      else
        content+="${line}\n"
      fi
    fi

    # Detect </entry> => we finalize
    if [[ "$line" =~ \</entry\> ]]; then
      inEntry=0

      if [ $isPost -eq 1 ]; then
        ####################################
        # Make a safe filename from $title
        ####################################
        safeTitle="${title//[^[:alnum:]. _-]/}"
        safeTitle="$(echo "$safeTitle" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        safeTitle="${safeTitle// /_}"
        [ -z "$safeTitle" ] && safeTitle="post-$idx"

        outFile="$OUTDIR/$safeTitle.txt"

        ####################################
        # Clean up HTML in $content
        ####################################
        # (1) Turn <br> or <br /> into newlines
        cleanContent="$(echo -e "$content" \
          | sed -E 's#<[bB][rR]\s*/?>#\n#g')"

        # (2) Remove all other <...> tags
        cleanContent="$(echo -e "$cleanContent" \
          | sed -E 's/<[^>]+>//g')"

        # (3) Minimal decode of &lt;, &gt;, &amp;
        cleanContent="$(echo -e "$cleanContent" \
          | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')"

        # (4) Remove trailing spaces on each line
        cleanContent="$(echo -e "$cleanContent" \
          | sed -E 's/[[:space:]]+$//')"

        ####################################
        # Sort tags into categories
        ####################################
        # We'll store them in arrays, then join them for output
        authorsFound=()
        booksFound=()
        volumesFound=()
        locationsFound=()
        others=()

        # Turn "tag1, tag2, tag3" into lines
        IFS=',' read -ra tagArray <<< "$tags"
        for rawTag in "${tagArray[@]}"; do
          # Trim leading/trailing spaces
          t="$(echo "$rawTag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          # Compare with each known set
          # We'll do "case-insensitive" or "exact"? Let's do exact for now.
          # If you need case-insensitive matching, you can downcase everything.
          foundMatch=0

          # Author?
          for a in "${AUTHORS[@]}"; do
            if [ "$t" = "$a" ]; then
              authorsFound+=("$t")
              foundMatch=1
              break
            fi
          done
          if [ $foundMatch -eq 1 ]; then continue; fi

          # Book?
          for b in "${BOOKS[@]}"; do
            if [ "$t" = "$b" ]; then
              booksFound+=("$t")
              foundMatch=1
              break
            fi
          done
          if [ $foundMatch -eq 1 ]; then continue; fi

          # Volume?
          for v in "${VOLUMES[@]}"; do
            if [ "$t" = "$v" ]; then
              volumesFound+=("$t")
              foundMatch=1
              break
            fi
          done
          if [ $foundMatch -eq 1 ]; then continue; fi

          # Location?
          for l in "${LOCATIONS[@]}"; do
            if [ "$t" = "$l" ]; then
              locationsFound+=("$t")
              foundMatch=1
              break
            fi
          done
          if [ $foundMatch -eq 1 ]; then continue; fi

          # If none matched, it's "other"
          others+=("$t")
        done

        # Now join each array with comma + space
        join_arr () {
          local IFS=", "
          echo "${*:1}"
        }

        authorsJoined="$(join_arr "${authorsFound[@]}")"
        booksJoined="$(join_arr "${booksFound[@]}")"
        volumesJoined="$(join_arr "${volumesFound[@]}")"
        locationsJoined="$(join_arr "${locationsFound[@]}")"
        othersJoined="$(join_arr "${others[@]}")"

        ####################################
        # Write final text
        ####################################
        {
          echo "Title: $title"
          echo "Published: $published"

          # Only print lines if they have content
          [ -n "$authorsJoined" ] && echo "Author: $authorsJoined"
          [ -n "$booksJoined" ] && echo "Book: $booksJoined"
          [ -n "$volumesJoined" ] && echo "Volume: $volumesJoined"
          [ -n "$locationsJoined" ] && echo "Location: $locationsJoined"

          # Print leftover tags
          [ -n "$othersJoined" ] && echo "Tags: $othersJoined"

          echo
          echo "$cleanContent"
        } > "$outFile"

        echo "Created: $outFile"
        ((idx++))
      fi
    fi
  fi

done < "$XMLFILE"

echo "Done! Extracted posts into '$OUTDIR'."

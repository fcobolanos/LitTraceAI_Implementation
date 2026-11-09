# =============================================================================
# PURPOSE: Preprocess "Related Work" text columns before coreference resolution.
# Dots that are NOT sentence boundaries (abbreviations, decimals, initialisms,
# in-word dots) are converted to commas or removed so that downstream sentence
# tokenisers do not split incorrectly at those positions.
# =============================================================================

# --- Libraries ---------------------------------------------------------------
library(tidyverse)  # str_replace_all, mutate, pipe (%>%)
library(readxl)     # read_excel
library(tidytext)   # (loaded for potential tokenisation steps; not called directly here)


# --- Helper function ---------------------------------------------------------
# replace_dots_in_parens(x):
#   Finds every parenthesised block (...) in string x and replaces all dots
#   INSIDE that block with commas.
#   Example: "results (F=4.2, p=0.03)" -> "results (F=4,2, p=0,03)"
#   Why: inside parentheses, a dot is almost never a sentence boundary.
replace_dots_in_parens <- function(x) {
  stringr::str_replace_all(
    x,
    "\\([^)]*\\)",                            # match any (...) block (no nested parens)
    function(m) stringr::str_replace_all(m, fixed("."), ",")  # replace every dot inside with comma
  )
}


# --- Load data ---------------------------------------------------------------
# Excel file has (at least) two text columns:
#   Related_Work_Final  – gold/final version of the Related Work section
#   Related_Work_CR     – coreference-resolved version of the same section
data <- read_excel("data/Coreference/Test_CoreferenceResolution_Jodiv01.xlsx")


# --- Pre-compile regex patterns ----------------------------------------------
# Compiled once here for efficiency and readability; reused twice below
# (once per column).

# Pattern 1: dot sitting BETWEEN two single letters that are word boundaries.
#   Matches the dot in "U.S.", "U.K.", "E.U.", "U.A.E." etc.
#   Lookbehind: single alpha char at a word boundary.
#   Lookahead:  single alpha char at a word boundary.
#   Result when applied: "U.S." -> "U S."  (intermediate; trailing dot handled next)
dots_between_single_letters <- stringr::regex(
  "(?<=\\b[[:alpha:]])\\.(?=[[:alpha:]]\\b)",
  ignore_case = TRUE
)

# Pattern 2: trailing dot after a sequence of space-separated single letters.
#   After Pattern 1, "U.S." has become "U S." — this removes the remaining dot.
#   Lookahead ensures the dot is followed by whitespace, end-of-string, or
#   a closing punctuation character, confirming it is NOT starting a new word.
#   Result: "U S." -> "U S"
final_dot_after_initialisms <- stringr::regex(
  "\\b([[:alpha:]](?:\\s+[[:alpha:]]){1,})\\.(?=\\s|$|[)\\],;:])",
  ignore_case = TRUE
)

# Pattern 3: dot between two word characters (letters OR digits), e.g. "ver.di".
#   Lookahead/lookbehind are single-character (ICU-safe; no variable-length lookbehind).
#   Result: "ver.di" -> "ver,di"
inword_dot_to_comma <- stringr::regex("(?<=\\w)\\.(?=\\w)")


# --- Apply cleaning to both text columns -------------------------------------
temp <- data %>%
  mutate(

    # =========================================================================
    # Column 1: Related_Work_Final
    # =========================================================================
    Related_Work_Final = Related_Work_Final %>%

      # Step 1 – Fixed academic abbreviations
      # Each pattern on the left is replaced by the string on the right.
      #   "et al."  -> "et al"   (citation shorthand)
      #   "e.g."    -> "e g"     (Latin: exempli gratia)
      #   "e.  g."  -> "e  g"    (same, with extra internal space)
      #   "i.e."    -> "i,e,"    (Latin: id est; commas mark it as non-sentence-end)
      #   "vs."     -> "vs"      (versus)
      #   "p.123"   -> "p 123"   (page references; \\1 captures the digits)
      str_replace_all(c(
        "et al\\."      = "et al",
        "e\\.g\\."      = "e g",
        "e\\.  g\\."    = "e  g",
        "i\\.e\\."      = "i,e,",
        "vs\\."         = "vs",
        "p\\.(\\d+)"    = "p \\1"
      )) %>%

      # Step 2 – Section/heading numbers like "h1.", "h2." (e.g. HTML heading refs)
      #   "h1." -> "h1,"   prevents split after a heading label
      str_replace_all(stringr::regex("h(\\d+)\\."), "h\\1,") %>%

      # Step 3 – Initialisms: remove dots between single letters (U.S. -> U S.)
      str_replace_all(dots_between_single_letters, " ") %>%

      # Step 4 – Initialisms: remove the trailing dot left by Step 3 (U S. -> U S)
      str_replace_all(final_dot_after_initialisms, "\\1") %>%

      # Step 5 – Decimal numbers: digit.digit -> digit,digit
      #   "0.5"  -> "0,5"    standard decimal
      #   "4.0." -> "4,0."   decimal followed by a sentence-ending dot (dot kept)
      str_replace_all(stringr::regex("(?<=\\d)\\.(?=\\d)"), ",") %>%
      str_replace_all(stringr::regex("(?<=\\d)\\.(?=\\d\\.)"), ",") %>%

      # Step 6 – Dots inside parentheses -> commas  (uses helper defined above)
      #   "(p=0.03)" -> "(p=0,03)"
      replace_dots_in_parens() %>%

      # Step 7 – Any remaining in-word dot -> comma  (catch-all for words like ver.di)
      #   Applied last so it does not interfere with the more specific rules above.
      str_replace_all(inword_dot_to_comma, ","),


    # =========================================================================
    # Column 2: Related_Work_CR
    # Identical cleaning pipeline applied to the coreference-resolved column.
    # =========================================================================
    Related_Work_CR = Related_Work_CR %>%

      # Step 1 – Fixed academic abbreviations (same as above)
      str_replace_all(c(
        "et al\\."      = "et al",
        "e\\.g\\."      = "e g",
        "e\\.  g\\."    = "e  g",
        "i\\.e\\."      = "i,e,",
        "vs\\."         = "vs",
        "p\\.(\\d+)"    = "p \\1"
      )) %>%

      # Step 2 – Heading references like "h1.", "h2."
      str_replace_all(stringr::regex("h(\\d+)\\."), "h\\1,") %>%

      # Step 3 – Initialisms: dots between single letters -> spaces
      str_replace_all(dots_between_single_letters, " ") %>%

      # Step 4 – Initialisms: remove trailing dot after spaced single letters
      str_replace_all(final_dot_after_initialisms, "\\1") %>%

      # Step 5 – Decimal numbers: digit.digit -> digit,comma
      str_replace_all(stringr::regex("(?<=\\d)\\.(?=\\d)"), ",") %>%
      str_replace_all(stringr::regex("(?<=\\d)\\.(?=\\d\\.)"), ",") %>%

      # Step 6 – Dots inside parentheses -> commas
      replace_dots_in_parens() %>%

      # Step 7 – Remaining in-word dots -> commas
      str_replace_all(inword_dot_to_comma, ",")
  )


# --- Save cleaned data -------------------------------------------------------
# Writes the mutated dataframe (all original columns preserved, two columns cleaned)
# to a new Excel file so the original input is not overwritten.
writexl::write_xlsx(temp, "data/Coreference/Test_CoreferenceResolution_Cleaned_Jodiv01.xlsx")

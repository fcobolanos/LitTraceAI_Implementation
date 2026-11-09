# =============================================================================
# ReferenceCleaningPart3v03.R
# PURPOSE: Replace raw citation markers (e.g. @b123) in "Related Work" text
#          with standardized tags (e.g. @Citation5), then split abstracts and
#          related work into sentence-level rows, and export cleaned tables.
# INPUTS:  data/Test_Jodi_Overallv01_Temp.xlsx   -- one row per paper
#          data/Test_Jodi_Referencesv01_Temp.xlsx -- one row per cited reference
# OUTPUTS: data/Test_Jodi_Overallv01_Inter.xlsx   -- cleaned papers table
#          data/Test_Jodi_Referencesv01_Inter.xlsx -- cleaned references table
# =============================================================================

library(tidyverse)   # str_replace_all, mutate, joins, map_chr, etc.
library(readxl)      # read_excel
library(tidytext)    # unnest_tokens (sentence splitting)


# -----------------------------------------------------------------------------
# 1. LOAD DATA
# -----------------------------------------------------------------------------

# overall: one row per paper; must contain columns Title, Related_Work, Abstract
overall <- read_excel("data/Test_Jodi_Overallv01_Temp.xlsx")

# Lowercase Related_Work now so all citation-marker matching is case-insensitive
overall <- overall %>%
  mutate(Related_Work = str_to_lower(Related_Work))

# references: one row per citation; must contain Title, Citation_Id, Citation_Standard, Title_Reference
references <- read_excel("data/Test_Jodi_Referencesv01_Temp.xlsx")


# -----------------------------------------------------------------------------
# 2. REPLACE RAW CITATION MARKERS WITH STANDARDIZED TAGS
#    For each paper, find every "@bXXX" marker in its Related_Work text and
#    swap it for the corresponding Citation_Standard value (e.g. "@Citation5")
#    from the references table.
# -----------------------------------------------------------------------------

related_work_modified <- NULL   # will accumulate one row per paper

max_rows_df1 <- nrow(overall)

for (i in 1:max_rows_df1) {

  overall_temp <- overall[i, ]   # single paper row

  # Get only the references that belong to this paper (matched on Title),
  # and normalize Citation_Id: "@b" -> "_b" so it matches what we'll do to the text
  references_temp <- overall_temp %>%
    select(Title) %>%
    inner_join(references, by = "Title") %>%
    mutate(Citation_Id = str_replace_all(Citation_Id, "@b", "_b"))

  # Pull out the raw related-work string for this paper
  related_work <- overall_temp$Related_Work

  # Ensure a space before every "@b" token so word-boundary regex works reliably
  # e.g. "text@b12" -> "text @b12"
  related_work <- str_replace_all(related_work, "(?<!\\s)@b", " @b")

  # Normalize the marker prefix in the text to match what we did to Citation_Id above
  # "@b12" -> "_b12"
  related_work <- str_replace_all(related_work, "@b", "_b")

  # Loop over every reference for this paper and replace its Citation_Id with
  # the standardized tag (e.g. "_b12" -> "@Citation5")
  max_rows_df2 <- nrow(references_temp)
  for (j in 1:max_rows_df2) {
    raw_id        <- references_temp[j, ]$Citation_Id       # e.g. "_b12"
    standard_tag  <- references_temp[j, ]$Citation_Standard # e.g. "@Citation5"

    # Only replace if the exact token is present (word boundaries prevent partial matches)
    if (str_detect(related_work, paste0("\\b", raw_id, "\\b"))) {
      related_work <- str_replace_all(related_work, paste0("\\b", raw_id, "\\b"), standard_tag)
    }
  }

  # Accumulate results: initialise on first iteration, bind_rows thereafter
  if (i == 1) {
    related_work_modified <- data.frame(related_work)
  } else {
    related_work_modified <- related_work_modified %>%
      bind_rows(data.frame(related_work))
  }
}

# Rename column to make its role explicit
related_work_modified <- related_work_modified %>%
  rename(Related_Work_Final = related_work)

# Attach the cleaned Related_Work_Final column back to the main table
overall <- overall %>%
  bind_cols(related_work_modified)


# -----------------------------------------------------------------------------
# 3. BUILD A DEDUPLICATED LIST OF ALL @CitationN TAGS THAT APPEAR IN THE TEXT
#    This tells us which citations are actually cited (as opposed to just being
#    in the references table) and what numeric index each one carries.
# -----------------------------------------------------------------------------

df_citations <- overall %>%
  # Extract every "@Citation<number>" token from each Related_Work_Final cell
  mutate(Citation_Standard = str_extract_all(Related_Work_Final, "@Citation\\d+")) %>%
  unnest(Citation_Standard) %>%          # one row per token per paper
  select(Citation_Standard) %>%
  distinct() %>%                         # keep unique tags only
  # Parse the numeric index out of "@Citation5" -> 5
  mutate(Index = as.numeric(str_extract(Citation_Standard, "(?<=@Citation).*")))


# -----------------------------------------------------------------------------
# 4. FILTER REFERENCES TABLE TO ONLY CITED ENTRIES, ORDERED BY INDEX
# -----------------------------------------------------------------------------

references_final <- references %>%
  inner_join(df_citations, by = "Citation_Standard") %>%
  arrange(Index)


# -----------------------------------------------------------------------------
# 5. ASSIGN CITATION_STANDARD TO PAPERS THAT ARE THEMSELVES REFERENCES
#    Some papers in `overall` are also listed as references (their Title matches
#    a Title_Reference in the references table). Look up their standard tag.
# -----------------------------------------------------------------------------

# Unique mapping: reference title -> standard citation tag
temp_reference <- references %>%
  select(Title_Reference, Citation_Standard) %>%
  distinct()

# Papers whose title appears as a cited reference
temp_reference_equal <- overall %>%
  inner_join(temp_reference, by = c("Title" = "Title_Reference")) %>%
  select(Title, Citation_Standard)

# Merge the looked-up Citation_Standard into overall (full join keeps all papers)
overall <- overall %>%
  full_join(temp_reference_equal, by = "Title")


# -----------------------------------------------------------------------------
# 6. GENERATE NEW CITATION TAGS FOR PAPERS WITH NO MATCH IN THE REFERENCES TABLE
#    Papers that couldn't be matched above get Citation_Standard = NA.
#    Assign them a new sequential tag continuing from the highest existing index.
# -----------------------------------------------------------------------------

# Start the counter one above the highest index already in use
max_index <<- max(df_citations$Index, na.rm = TRUE)

# Each call returns the next "@Citation<N>" tag and increments the counter
getCitation <- function() {
  max_index <<- max_index + 1
  paste0("@Citation", max_index)
}

# Replace NA Citation_Standard values with freshly generated tags
overall <- overall %>%
  mutate(Citation_Standard = map_chr(Citation_Standard, ~ ifelse(is.na(.x), getCitation(), .x)))


# -----------------------------------------------------------------------------
# 7. ADD STUB ENTRIES TO references_final FOR PAPERS THAT HAD NO MATCH
#    These are papers that received a newly generated tag in step 6.
#    We create a minimal reference row so every Citation_Standard in `overall`
#    has a corresponding entry in references_final.
# -----------------------------------------------------------------------------

references_final_missing <- overall %>%
  # Keep only papers whose Citation_Standard is not yet in references_final
  anti_join(references_final %>% select(Citation_Standard), by = "Citation_Standard") %>%
  mutate(
    Citation_Id     = Citation_Standard,  # use the new tag as the raw ID too
    Year            = "0",                # year unknown
    Title_Reference = Title,              # paper title serves as reference title
    Source          = "",                 # no journal/venue info
    Frequency       = as.numeric(1),      # cited once (the paper itself)
    Index           = as.numeric(str_extract(Citation_Standard, "(?<=@Citation).*"))
  ) %>%
  select(Paper_Id, Title, Citation_Id, Authors, Year, Title_Reference,
         Source, Frequency, Citation_Standard, Index)

# Combine with existing references, sort by index, and uppercase + trim all strings
references_final <- references_final %>%
  bind_rows(references_final_missing) %>%
  arrange(Index) %>%
  mutate(across(where(is.character), ~ toupper(str_trim(.x))))

# Apply the same uppercase + trim standardisation to the overall table
overall <- overall %>%
  mutate(across(where(is.character), ~ toupper(str_trim(.x))))


# -----------------------------------------------------------------------------
# 8. BUILD A SENTENCE-LEVEL TABLE (final_detail)
#    Split both Abstract and Related_Work_Final into individual sentences.
#    Each sentence gets its own row with Paper_Id, Section, Sentence_Id,
#    SubSection_Id (paragraph index for Related Work), and Citation tags found.
# -----------------------------------------------------------------------------

# Working subset with only the columns we need for sentence splitting
overall_detail <- overall %>%
  select(Paper_Id, Title, Abstract, Related_Work_Final, Citation_Standard) %>%
  mutate(Abstract = str_to_upper(Abstract))

# --- 8a. ABSTRACT sentences ---
# Split on "." to get one sentence per row; every sentence in the abstract
# inherits the paper's own Citation_Standard as its citation marker.
temp_abstract <- overall_detail %>%
  select(-Related_Work_Final) %>%
  unnest_tokens(output = "Sentence", input = Abstract,
                token = "regex", pattern = "\\.") %>%
  mutate(
    Sentence     = str_trim(str_to_upper(Sentence)),
    Citation     = Citation_Standard,   # whole paper = single citation
    Section      = "Abstract",
    SubSection_Id = 1                   # abstracts have only one paragraph
  ) %>%
  group_by(Paper_Id) %>%
  mutate(Sentence_Id = row_number()) %>%   # number sentences within each paper
  ungroup() %>%
  select(Paper_Id, Sentence_Id, SubSection_Id, Title, Section, Sentence, Citation) %>%
  mutate(Citation = str_to_upper(Citation))

# --- 8b. RELATED WORK sentences ---
# Related Work can contain "[LINE BREAK]" markers that indicate paragraph breaks.
# We first split on those into paragraphs (SubSection_Id), then split each
# paragraph into sentences, and finally extract inline @CITATION tags per sentence.
temp_related_work <- overall_detail %>%
  select(-Abstract) %>%
  # Convert "[LINE BREAK]" to "###" as a safe paragraph delimiter
  mutate(Related_Work_Final = str_replace_all(Related_Work_Final, "\\[LINE BREAK\\]", "###")) %>%
  # One row per paragraph
  separate_rows(Related_Work_Final, sep = "###") %>%
  # Strip any leading "." left over from the split
  mutate(Related_Work_Final = str_trim(str_remove(Related_Work_Final, "^\\."))) %>%
  group_by(Paper_Id) %>%
  mutate(SubSection_Id = row_number()) %>%   # paragraph index within paper
  ungroup() %>%
  # Split each paragraph into sentences on "."
  unnest_tokens(output = "Sentence", input = Related_Work_Final,
                token = "regex", pattern = "\\.") %>%
  mutate(Sentence = str_trim(str_to_upper(Sentence))) %>%
  group_by(Paper_Id) %>%
  mutate(Sentence_Id = row_number()) %>%     # sentence index within paper
  ungroup() %>%
  # Extract all @CITATION tags that appear in this sentence (may be multiple)
  mutate(Citation = str_extract_all(Sentence, "@CITATION\\d+")) %>%
  # Collapse multiple tags into a comma-separated string: "@CITATION1, @CITATION3"
  mutate(Citation = map_chr(Citation, ~ paste(.x, collapse = ", "))) %>%
  mutate(Section = "Related Work") %>%
  select(Paper_Id, Sentence_Id, SubSection_Id, Title, Section, Sentence, Citation)

# Combine abstract and related-work sentence tables into one detail table
final_detail <- temp_abstract %>%
  bind_rows(temp_related_work) %>%
  arrange(Paper_Id, Section, Sentence_Id, SubSection_Id)


# -----------------------------------------------------------------------------
# 9. EXAMPLE / TEST SNIPPET (not executed in normal flow)
#    Illustrates what Related_Work_Final looks like after step 2 processing.
# -----------------------------------------------------------------------------
df <- tibble(
  Related_Work_Final = c(
    "THE TASK OF RWG IS PIONEERED BY @CITATION1, WHO DEVELOP ...",
    "THIS METHOD WAS ALSO MENTIONED IN @CITATION2 AND @CITATION3.",
    "NO CITATION HERE."
  )
)


# -----------------------------------------------------------------------------
# 10. CONVERT @CITATION TAGS TO NUMERIC BRACKET FORMAT AND LOWERCASE
#     Replace "@CITATION5" with "[5]" in Related_Work_Final and Citation_Standard,
#     then lowercase all character columns for final output consistency.
# -----------------------------------------------------------------------------

overall <- overall %>%
  mutate(
    # "@CITATION5" -> "[5]"  (capture group \\1 extracts the number)
    Related_Work_Final = str_replace_all(Related_Work_Final, "@CITATION(\\d+)", "[\\1]"),
    Citation_Standard  = str_replace_all(Citation_Standard,  "@CITATION(\\d+)", "[\\1]")
  ) %>%
  mutate(across(where(is.character), tolower))

references_final <- references_final %>%
  mutate(Citation_Standard = str_replace_all(Citation_Standard, "@CITATION(\\d+)", "[\\1]")) %>%
  mutate(across(where(is.character), tolower))


# -----------------------------------------------------------------------------
# 11. EXPORT RESULTS
# -----------------------------------------------------------------------------

writexl::write_xlsx(overall,          "data/Test_Jodi_Overallv01_Inter.xlsx")
writexl::write_xlsx(references_final, "data/Test_Jodi_Referencesv01_Inter.xlsx")

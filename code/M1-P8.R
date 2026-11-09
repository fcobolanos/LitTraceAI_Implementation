# ============================================================
# COREFERENCE RESOLUTION - PART 1
# Compares original Related Work sentences against GPT-4.1
# coreference-resolved versions, sentence by sentence.
# ============================================================


# --- LIBRARIES ----------------------------------------------

library(tidyverse)   # str_detect, mutate, filter, select, etc.
library(readxl)      # read_excel: reads .xlsx files
library(tidytext)    # unnest_tokens: splits text into sentences/tokens


# --- LOAD DATA ----------------------------------------------

# Load the cleaned coreference resolution dataset.
# Each row represents one paper processed by one model,
# and includes columns like Paper_Id, Title, Abstract,
# Related_Work_Final (original), Related_Work_CR (coreference-resolved),
# Model, and Citation_Standard.
data <- read_excel("data/Coreference/Test_CoreferenceResolution_Cleaned_Jodiv01.xlsx")


# --- NORMALIZE TEXT -----------------------------------------

# Strip leading/trailing whitespace and lowercase all character columns.
# This prevents mismatches later due to inconsistent casing or spacing
# (e.g., "GPT-4.1" vs "gpt-4.1", or " abstract " vs "abstract").
data <- data %>% 
  mutate(across(where(is.character), ~ str_trim(tolower(.))))


# --- EXTRACT ORIGINAL RELATED WORK --------------------------

# Keep only rows processed by GPT-4.1 (used as the reference model),
# and retain only the columns needed for the original text analysis:
# Paper_Id, Title, Abstract, Related_Work_Final, and Citation_Standard.
# Note: any model could be used here; GPT-4.1 is chosen as the baseline.
overall_original <- data %>% 
  filter(str_detect(Model, "gpt-4\\.1")) %>%
  select(Paper_Id, Title, Abstract, Related_Work_Final, Citation_Standard) %>% 
  mutate(Abstract = str_to_lower(Abstract))  # Ensure Abstract is lowercase (redundant after global normalization above, but explicit)


# --- FUNCTION: SPLIT RELATED WORK INTO SENTENCES ------------

# getRelatedWorkDetail()
# Splits a Related Work text column into individual sentences,
# assigns IDs, and extracts citation markers (e.g., [1], [2]).
#
# Arguments:
#   df      - data frame containing the Related Work text
#   field   - name of the output column that will hold each sentence
#             (e.g., "Sentence_Original" or "Sentence_GPT4_1")
#   section - either "Related Work" (original) or anything else (CR version)
#             determines which input column to process

getRelatedWorkDetail <- function(df, field, section) {
  
  # Select the correct input column based on whether we're processing
  # the original text (Related_Work_Final) or the coreference-resolved
  # text (Related_Work_CR).
  if (section == "Related Work") {
    temp_field = "Related_Work_Final"   # Original Related Work text
  } else {
    temp_field = "Related_Work_CR"      # GPT-4.1 coreference-resolved text
  }
  
  temp_related_work <- df %>% 
    
    # Abstract column is not needed for sentence-level analysis; drop it.
    select(-Abstract) %>%
    
    # The text uses "[line break]" as a custom paragraph/subsection separator.
    # Replace it with "###" so we can split on it with separate_rows().
    mutate(!!sym(temp_field) := str_replace_all(!!sym(temp_field), "\\[line break\\]", "###")) %>%
    
    # Split each row into multiple rows, one per subsection (paragraph),
    # using "###" as the delimiter.
    separate_rows(!!sym(temp_field), sep = "###") %>%
    
    # After splitting, some subsections may start with a stray period.
    # Remove it and trim any surrounding whitespace.
    mutate(!!sym(temp_field) := str_trim(str_remove(!!sym(temp_field), "^\\."))) %>%
    
    # Number each subsection (paragraph) within each paper, starting at 1.
    group_by(Paper_Id) %>%
    mutate(SubSection_Id = row_number()) %>%
    ungroup() %>%
    
    # Split each subsection into individual sentences, treating "." as the
    # sentence boundary. Each sentence becomes its own row, stored in `field`.
    unnest_tokens(output = !!sym(field), input = !!sym(temp_field), token = "regex", pattern = "\\.") %>%
    
    # Lowercase and trim each sentence for consistent comparisons.
    mutate(!!sym(field) := str_trim(str_to_lower(!!sym(field)))) %>%
    
    # Remove sentences that are empty strings after cleaning.
    filter(!!sym(field) != "") %>%
    
    # Number each sentence sequentially within each paper.
    # This Sentence_Id is used later to align original vs. CR sentences.
    group_by(Paper_Id) %>%
    filter(!is.na(!!sym(field)) | !!sym(field) != "") %>%  # Belt-and-suspenders NA check
    mutate(Sentence_Id = row_number()) %>%
    ungroup() %>%
    
    # Extract all citation markers of the form [N] (e.g., [1], [23])
    # from the sentence text into a list column.
    mutate(Citation = str_extract_all(!!sym(field), "\\[\\d+\\]")) %>%
    
    # Collapse multiple citations in a sentence into a single string
    # (e.g., "[1], [3], [7]") for readability in the output.
    mutate(Citation = map_chr(Citation, ~ paste(.x, collapse = ", "))) %>%
    
    # Tag all sentences with the section label "Related Work".
    mutate(Section = "Related Work") %>%
    
    # Keep only the relevant output columns in a clean order.
    select(Paper_Id, Sentence_Id, SubSection_Id, Title, Section, !!sym(field), Citation)
  
  return(temp_related_work)
}


# --- APPLY FUNCTION TO BOTH VERSIONS ------------------------

# Process the original Related Work text.
# Output column is named "Sentence_Original".
temp_related_work_orginal <- getRelatedWorkDetail(
  overall_original,
  "Sentence_Original",
  "Related Work"
)

# Process the GPT-4.1 coreference-resolved Related Work text.
# Only GPT-4.1 rows are passed in (same filter as above).
# Output column is named "Sentence_GPT4_1".
temp_related_work_coreference_resolution <- getRelatedWorkDetail(
  data %>% filter(str_detect(Model, "gpt-4\\.1")),
  "Sentence_GPT4_1",
  "Related_Work_CR"
)


# --- JOIN AND COMPARE SENTENCES -----------------------------

# Align original and CR sentences by Paper_Id + Sentence_Id + SubSection_Id.
# An inner join means only sentences that exist in BOTH versions are kept,
# ensuring a clean apples-to-apples comparison.
final_detail <- temp_related_work_orginal %>% 
  inner_join(
    # Only bring in the sentence text from the CR version; other columns
    # (Title, Section, Citation) are already present from the original.
    temp_related_work_coreference_resolution %>%
      select(Paper_Id, Sentence_Id, SubSection_Id, Sentence_GPT4_1),
    by = c("Paper_Id", "Sentence_Id", "SubSection_Id")
  ) %>%
  
  # Reorder columns so Sentence_GPT4_1 appears before Citation.
  select(1:6, 8, 7) %>%
  
  # Add three comparison columns:
  # - Equal_Original_GPT4_1: "YES" if CR sentence is identical to the original,
  #   "NO" if GPT-4.1 made changes (i.e., resolved a coreference).
  # - Sentence_Original_Length: character count of the original sentence.
  # - Sentence_GPT4_1_Length: character count of the CR sentence.
  #   Length differences can indicate where pronouns were replaced with full NPs.
  mutate(
    Equal_Original_GPT4_1    = if_else(Sentence_Original == Sentence_GPT4_1, "YES", "NO"),
    Sentence_Original_Length  = str_length(Sentence_Original),
    Sentence_GPT4_1_Length    = str_length(Sentence_GPT4_1)
  )


# --- EXPORT -------------------------------------------------

# Save the sentence-level comparison table to Excel for manual review
# or further analysis (e.g., checking where GPT-4.1 changed text).
writexl::write_xlsx(final_detail, "data/Coreference/Test_CoreferenceResolution_Jodi_Sentencesv01.xlsx")

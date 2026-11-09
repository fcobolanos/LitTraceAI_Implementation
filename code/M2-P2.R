# ============================================================
# Sentence Classification - Part 1
# Purpose: Merge sentence-level classifications from two sources
#          (Original fine-tuned model and GPT-4) and produce
#          a final annotated Excel file for analysis.
# ============================================================

# --- Dependencies ---
library(tidyverse)   # Core data manipulation: dplyr, tidyr, stringr, purrr, ggplot2
library(readxl)      # read_excel(): imports .xlsx files into tibbles
library(tidytext)    # Text-mining helpers (tokenisation, stop words); loaded for potential downstream use
library(writexl)     # write_xlsx(): exports tibbles/lists to .xlsx without Java dependency


# ============================================================
# DATA LOADING
# ============================================================
# Four input files are needed:
#   overall           – one row per sentence per paper, includes coreference-resolved text
#   original          – sentence labels produced by the fine-tuned (Original) model
#   gpt4              – sentence labels produced by GPT-4
#   citation_standard – lookup table: Paper_Id → formatted citation key, e.g. [Smith2020]
#
# Production paths are commented out; active paths point to a small Jodi test set.

#overall           <- read_excel("data/Coreference/CoreferenceResolutionRWg_LLMs_Sentencesv01.xlsx")
#original          <- read_csv("data/Coreference/RWG_LLMs_Sentence_Classificationv01_Original.csv")
#gpt4              <- read_csv("data/Coreference/RWG_LLMs_Sentence_Classificationv01_GPT4.csv")
#citation_standard <- read_excel("data/RWG_LLMs_Overallv03_Inter.xlsx")

overall           <- read_excel("data/Coreference/Test_CoreferenceResolution_Jodi_Sentencesv01.xlsx")
original          <- read_csv("data/Coreference/Test_Jodi_Sentencev01_Original.csv")
gpt4              <- read_csv("data/Coreference/Test_Jodi_Sentencev01_GPT4.csv")
citation_standard <- read_excel("data/Test_Jodi_Overallv01_Inter.xlsx")

# Slim down citation_standard to only the two columns used in the final join.
# All other columns (author names, year, etc.) are discarded here to avoid
# name collisions when merging with 'overall' later.
citation_standard <- citation_standard %>%
  select(Paper_Id, Citation_Standard)


# ============================================================
# PREPARE THE ORIGINAL-MODEL CLASSIFICATION TABLE
# ============================================================
# Goal: produce a clean, minimal table with one row per sentence and
#       a clearly named classification column (Classification_Original).
#
# Steps:
#   1. str_to_upper + str_trim  → normalise Sentence_Original text to
#      UPPER CASE with no leading/trailing whitespace; ensures text comparisons
#      later are case-insensitive.
#   2. select                   → keep only the five columns needed for the join
#      and downstream analysis; drop all others (raw sentence text, raw labels, etc.).
#   3. rename                   → Prediction_Finetune_Cleaned → Classification_Original
#      to make the source of the label unambiguous in the merged table.
original <- original %>%
  mutate(Sentence_Original = str_trim(str_to_upper(Sentence_Original))) %>%
  select(Paper_Id, Sentence_Id, SubSection_Id, Prediction_Finetune_Cleaned, Section) %>%
  rename(Classification_Original = Prediction_Finetune_Cleaned)


# ============================================================
# PREPARE THE GPT-4 CLASSIFICATION TABLE
# ============================================================
# Same logic as above for the GPT-4 classifier.
#
# NOTE on the mutate step: Sentence_GPT4 is created from Sentence_GPT4_1
# but is NOT listed in the following select(), so it is silently dropped.
# Only the normalisation side-effect (not the new column) is relevant here.
# The original raw column Sentence_GPT4_1 is preserved in 'overall' for
# final output formatting later.
#
# rename: Prediction_Finetune_Cleaned → Classification_GPT4_1
gpt4 <- gpt4 %>%
  mutate(Sentence_GPT4 = str_trim(str_to_upper(Sentence_GPT4_1))) %>%  # created but not kept
  select(Paper_Id, Sentence_Id, SubSection_Id, Prediction_Finetune_Cleaned, Section) %>%
  rename(Classification_GPT4_1 = Prediction_Finetune_Cleaned)


# ============================================================
# BUILD THE FINAL MERGED TABLE
# ============================================================
# Start from 'overall' (the authoritative sentence list with coreference info)
# and layer in: Original labels → GPT-4 labels → agreement flag → citation key → provenance tag.
# inner_join is used throughout, so only sentences that exist in ALL sources are kept.
overall <- overall %>%

  # 1. Attach Original-model label for each sentence.
  #    Join keys: Paper_Id + Sentence_Id + SubSection_Id + Section
  #    (four keys prevent false matches across papers or sections).
  inner_join(original, by = c("Paper_Id", "Sentence_Id", "SubSection_Id", "Section")) %>%

  # 2. Attach GPT-4 label using the same four-column key.
  inner_join(gpt4,     by = c("Paper_Id", "Sentence_Id", "SubSection_Id", "Section")) %>%

  # 3. Classifier agreement flag.
  #    "YES" if both models assigned the same label to this sentence; "NO" otherwise.
  #    Useful as a quick filter in the output Excel file.
  mutate(Classification_Equal = if_else(
    Classification_Original == Classification_GPT4_1, "YES", "NO"
  )) %>%

  # 4. Add the formatted citation key for each paper (e.g. [Smith2020]).
  inner_join(citation_standard, by = "Paper_Id") %>%

  # 5. Build a Provenance tag that uniquely identifies each sentence in publications.
  #    Format: (Smith2020,S03) — brackets stripped, paper citation + sentence ID.
  #    str_remove_all("\\[|\\]") removes the surrounding square brackets from Citation_Standard.
  mutate(Provenance = paste0(
    "(", str_remove_all(Citation_Standard, "\\[|\\]"), ",", Sentence_Id, ")"
  )) %>%

  # 6. Reorder columns for a clean, reviewer-friendly layout in the output file.
  #    Positional indexing (not names) is used because column positions are stable
  #    after the joins above. Adjust these indices if the source schemas change.
  #    Final order: cols 1-8 | 15-16 (citation/provenance) | 10-11 | 9 | 12-14
  select(1:8, 15:16, 10:11, 9, 12:14) %>%

  # 7. Normalise text capitalisation for human-readable output:
  #    - Title         → str_to_title:    "the impact of llms" → "The Impact Of Llms"
  #    - Sentence text → str_to_sentence: "THIS IS A SENTENCE" → "This is a sentence."
  #      A trailing period is appended because the text was upper-cased earlier.
  #    - Classification labels → str_to_sentence: "RELATED_WORK" → "Related_work"
  mutate(
    Title                    = str_to_title(Title),
    Sentence_Original        = paste0(str_to_sentence(Sentence_Original), "."),
    Sentence_GPT4_1          = paste0(str_to_sentence(Sentence_GPT4_1),  "."),
    Classification_Original  = str_to_sentence(Classification_Original),
    Classification_GPT4_1    = str_to_sentence(Classification_GPT4_1)
  )


# --- Export the complete merged classification table to Excel ---
# One sheet, one row per sentence, with both classifier labels and agreement flag.
write_xlsx(overall, "data/Coreference/Jodi_Finalv01.xlsx")


# ============================================================
# SECTION-TYPE CLASSIFICATION EXPORT (per-paper, per-subsection)
# Goal: Create a multi-sheet Excel file where each sheet = one paper,
#       rows show sentence-level classifications for Related Work only,
#       and blank rows separate subsections for easy manual review.
# ============================================================

temp <- overall %>%

  # Restrict to Related Work sentences only; drop all columns except the five needed.
  filter(Section == "Related Work") %>%
  select(Paper_Id, Sentence_Id, SubSection_Id, Classification_Original, Classification_GPT4_1) %>%

  # Group by paper AND subsection so the sentinel-row logic below operates per subsection block.
  group_by(Paper_Id, SubSection_Id) %>%

  # Collapse each (Paper_Id, SubSection_Id) group into a list-column called 'data'.
  # c(-Paper_Id, -SubSection_Id) means "nest everything except the grouping keys".
  nest(data = c(-Paper_Id, -SubSection_Id)) %>%

  # Append a blank sentinel row to the bottom of each subsection's data frame.
  # When the data is later unnested, these NA rows create a visible blank line
  # between consecutive subsections in the Excel sheet — improving manual readability.
  mutate(data = map(data, ~ bind_rows(.x, tibble(
    Sentence_Id             = NA,
    Classification_Original = NA,
    Classification_GPT4_1   = NA
  )))) %>%

  # Flatten the nested structure: all subsection rows (including sentinels) are
  # back in a flat table, still grouped by Paper_Id.
  unnest(data) %>%

  # Re-nest by Paper_Id only: one list element per paper, each containing all
  # its Related Work sentences (with blank separators between subsections).
  nest(data = -Paper_Id)


# Build a named list: name = Paper_Id string, value = the paper's tibble.
# write_xlsx uses list names as Excel sheet names, so each paper gets its own tab.
data_list <- map(set_names(temp$data, temp$Paper_Id), as_tibble)


# --- Export: one Excel sheet per paper, showing Related Work sentence classifications ---
write_xlsx(data_list, "data/Coreference/Jodi_Typev01.xlsx")

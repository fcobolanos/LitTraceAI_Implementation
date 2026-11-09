# === Libraries ===
library(tidyverse)  # Provides dplyr, stringr, and pipe operator used throughout
library(readxl)     # Reads .xlsx files into R data frames



# === Load the Excel files containing paper metadata and references ===

# 'overall' contains one row per reviewed paper, with columns including Paper_Id and Title
overall <- read_excel("data/Test_Jodi_Overall_Finalv01.xlsx")

# 'references' contains one row per reference cited by a paper, with a column called Title (the reference title)
# and a column called Paper (the title of the paper that cites it)
references <- read_excel("data/Test_Jodi_Referencesv01.xlsx")

# Rename 'Title' to 'Title_Reference' to distinguish reference titles from paper titles in later joins
references <- references %>% 
                          rename(Title_Reference = Title)



# === Filter and extract selected papers for analysis ===

# Keep only Paper_Id and Title from 'overall' — these two columns are sufficient to link papers to their references
# The two filter lines below are commented out but can be uncommented to restrict the analysis to a specific subset of papers
overall_temp <- overall %>% 
                          #filter(Paper_Id %in% c("paper1", "paper2", "paper3", "paper4", "paper5", "paper7", "paper7_1")) %>% 
                          #filter(Paper_Id %in% c("paper3", "paper4","paper6","paper7","paper9")) %>%                  
                          select(Paper_Id, Title)

# === Match references to their respective papers ===

# Join 'overall_temp' to 'references' on Title (paper title) = Paper (citing paper column in references)
# Result: one row per paper-reference pair, with both the Paper_Id and the Title_Reference present
# Normalise all text columns: trim leading/trailing whitespace and convert to uppercase for consistent matching
references_temp <- overall_temp %>% 
                          inner_join(references, by = c("Title" = "Paper")) %>% 
                          mutate(across(where(is.character), ~ str_to_upper(str_trim(.))))

# === Count frequency of each reference and create standard citation IDs ===

# Count how many times each unique reference title appears across all papers
# Exclude rows where Title_Reference is empty (missing reference titles)
# Assign a sequential standard citation key (@Citation1, @Citation2, ...) ordered by descending frequency
# so the most-cited reference gets @Citation1
titles <- references_temp %>% 
                      select(Title_Reference) %>% 
                      filter(Title_Reference != "") %>% 
                      count(Title_Reference) %>%           # produces column 'n' = number of papers citing this reference
                      rename(Frequency = n) %>% 
                      arrange(desc(Frequency)) %>% 
                      mutate(Citation_Standard = paste0("@Citation", seq_len(n())))  # seq_len(n()) = 1 to total unique references

# === Merge frequency and citation info back into reference data ===

# Bring Frequency and Citation_Standard back into the full reference table
# Lowercase Citation_Id (an existing column in references) to standardise its format
# Sort by most-cited references first; within the same frequency, sort by Title_Reference descending
references_final <- references_temp %>% 
                              inner_join(titles, by = "Title_Reference") %>% 
                              mutate(Citation_Id = str_to_lower(Citation_Id)) %>%  # e.g. "Author2020" -> "author2020"
                              arrange(desc(Frequency), desc(Title_Reference))

# === Final cleanup and export ===

# Apply the same text normalisation (uppercase + trim) to the full 'overall' dataset
# The filter lines are again commented out — uncomment to export only a subset of papers
overall_final <- overall %>% 
                          #filter(Paper_Id %in% c("paper1", "paper2", "paper3", "paper4", "paper5", "paper7", "paper7_1")) %>% 
                          #filter(Paper_Id %in% c("paper3", "paper4","paper6","paper7","paper9")) %>%                         
                          mutate(across(where(is.character), ~ str_to_upper(str_trim(.))))

# Write cleaned overall and reference datasets to new Excel files
# These _Temp files serve as inputs for the next stage of the cleaning pipeline
writexl::write_xlsx(overall_final, "data/Test_Jodi_Overallv01_Temp.xlsx")
writexl::write_xlsx(references_final, "data/Test_Jodi_Referencesv01_Temp.xlsx")

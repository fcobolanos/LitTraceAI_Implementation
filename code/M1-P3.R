# Load necessary libraries
library(tidyverse)    # Data manipulation and filtering (filter, group_by, summarise, etc.)
library(readxl)       # Reading Excel (.xlsx) files into R dataframes
library(tidytext)     # Text mining utilities (available for downstream text analysis)

# Load the two input datasets:
# - 'section': contains individual sections of each paper (columns: Title, Section, Content)
# - 'overall': contains one row per paper with overall metadata (e.g., Title, authors, year)
section <- read_excel("data/Test_Jodi_Sectionsv01.xlsx")  
overall <- read_excel("data/Test_Jodi_Overallv01.xlsx")  


# Extract and consolidate "Section 2: Related Work" content for each paper.
# Steps:
#   1. Filter rows where the Section column starts with "Section 2:" (case-insensitive)
#   2. Group by paper Title so each paper gets one row
#   3. Collapse all Content lines for that section into a single string,
#      separated by "[LINE BREAK]." to preserve original line boundaries
related_work_df <- section %>% 
                            filter(str_detect(Section, regex("Section 2:", ignore_case = TRUE))) %>%
                            group_by(Title) %>% 
                            summarise(Related_Work = paste(Content, collapse = "[LINE BREAK].")) %>%
                            ungroup()


# Merge the Related Work text into the overall dataset.
# Uses inner_join on 'Title', so only papers present in both datasets are retained.
# The result adds a 'Related_Work' column to the overall paper-level metadata.
overall_final <- overall %>% 
                        inner_join(related_work_df, by = 'Title')


# Export the merged dataset to a new Excel file for downstream analysis or sharing.
writexl::write_xlsx(overall_final, "data/Test_Jodi_Overall_Finalv01.xlsx")

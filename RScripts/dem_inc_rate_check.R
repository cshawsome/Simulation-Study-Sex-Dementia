#---- Package loading, options ----
if (!require("pacman")) 
  install.packages("pacman", repos='http://cran.us.r-project.org')

p_load("tidyverse", "here")

options(scipen = 999) #Standard Notation
options(digits = 6)   #Round to 6 decimal places
options(warn = -1)    #Suppress warnings

#---- Source files ----
source(here("RScripts", "variable_names.R"))
source(here("RScripts", "sex-dementia_sim_parA.R"))
source(here("RScripts", "sex-dementia_sim_data_gen.R"))

#---- Generate the data ----
data <- data_gen()

#---- Compute incidence rates ----
sim_rates <- matrix(ncol = 9, nrow = 1)
colnames(sim_rates) <- na.omit(variable_names$interval_ages)
rownames(sim_rates) <- c("")

for(slot in 1:num_tests){
  if(slot == 1){
    dem_last_wave <- paste0("dem", (slot - 1))
    dem_this_wave <- paste0("dem", (slot - 1), "-", slot)
    death_last_wave <- paste0("death", (slot - 1))
    death_this_wave <- paste0("death", (slot - 1), "-", slot)
    contributed <- paste0("contributed", (slot - 1), "-", slot)
  } else {
    dem_last_wave <- paste0("dem", (slot - 2), "-", (slot - 1))
    dem_this_wave <- paste0("dem", (slot - 1), "-", slot)
    death_last_wave <- paste0("death", (slot - 2), "-", (slot - 1))
    death_this_wave <- paste0("death", (slot - 1), "-", slot)
    contributed <- paste0("contributed", (slot - 1), "-", slot)
  }
  PY_data <- data %>% 
    dplyr::select(death_last_wave, death_this_wave, 
                  dem_last_wave, dem_this_wave, contributed) %>% 
    filter(!! as.name(death_last_wave) == 0 & 
             !! as.name(dem_last_wave) == 0) 
  
  sim_rates[1, slot] = round(1000*(sum(PY_data[, dem_this_wave], 
                                       na.rm = TRUE)/
                                     sum(PY_data[, contributed])), 3)
}
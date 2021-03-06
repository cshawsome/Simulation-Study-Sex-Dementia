#---- Package loading, options ----
if (!require("pacman")) 
  install.packages("pacman", repos='http://cran.us.r-project.org')

p_load("MASS", "here")

options(scipen = 999) #Standard Notation
options(digits = 6)   #Round to 6 decimal places
options(warn = -1)    #Suppress warnings

#---- Source files ----
source(here("RScripts", "var_names.R"))
source(here("RScripts", "create_ages.R"))
source(here("RScripts", "calc_coeff.R"))
source(here("RScripts", "compute_Ci.R"))
source(here("RScripts", "last_Ci.R"))
source(here("RScripts", "survival_times.R"))
source(here("RScripts", "random_timetodem.R"))
source(here("RScripts", "survival_censor.R"))
source(here("RScripts", "dementia_onset.R"))
source(here("RScripts", "compare_survtime_timetodem.R"))

#---- The data generation function ----
data_gen <- function(num_obs){
  #---- Create a blank dataset ----
  obs <- matrix(NA, nrow = num_obs, ncol = length(column_names)) 
  colnames(obs) <- column_names
  
  #---- Generating IDs, female, U ----
  obs[, "id"] <- seq(from = 1, to = num_obs, by = 1)
  obs[, "female"] <- rbinom(num_obs, size = 1, prob = pfemale)
  obs[, "U"] <- rnorm(num_obs, mean = 0, sd = 1)
  
  #---- Generating age data ----
  #Creating ages at each timepoint j
  ages = matrix(seq(50, 95, by = 5), nrow = 1)
  obs[, variable_names$age_varnames] <- create_ages(ages, num_obs)
  
  #---- Generating centered age data ----
  #Creating baseline-mean-centered ages at each timepoint j
  obs[, variable_names$agec_varnames] <- 
    obs[, variable_names$age_varnames] - mean(age0)
  
  #---- Generating "true" cognitive function Ci ----
  #Generating random terms for quadratic model
  
  #Defining the covariance matrix for intercept and linear term
  quad_coeff_cov <- matrix(c(ci_var0, ci_cov01, ci_cov02, 
                             ci_cov01, ci_var1, ci_cov12, 
                             ci_cov02, ci_cov12, ci_var2), 
                           nrow = 3, byrow = TRUE)
  
  #Generate random terms for each individual
  obs[, c("z_0i", "z_1i", "z_2i")] <- 
    mvrnorm(n = num_obs, mu = rep(0, 3), Sigma = quad_coeff_cov) 
  
  #Take the negative absolute value of the quadratic noise so that this is drawn
  #from a negative half normal distribution
  obs[, "z_2i"] <- -abs(obs[, "z_2i"])
  
  #Generating noise term (unexplained variance in Ci) 
  obs[, "eps_i"] <- rnorm(n = num_obs, mean = 0, sd = sqrt(ci_var3))
  
  #Calculating quadratic coefficients for each individual
  obs[, c("a0", "a1", "a2")] <- calc_coeff(obs)
  
  #Calculating Ci at each time point for each individual
  obs[, variable_names$Ci_varnames] <- compute_Ci(obs)
  
  #---- Check for dementia at baseline ----
  obs <- obs[obs[, "Ci0"] > dem_cut, ]
  
  #---- Generate survival time for each person ----
  
  #---- Generating uniform random variables ----
  #For Sij and random time to dementia models
  
  obs[, variable_names$r1ij_varnames[1:num_tests]] <- 
    replicate(num_tests, runif(nrow(obs), min = 0, max = 1))
  obs[, variable_names$r2ij_varnames[4:num_tests]] <- 
    replicate((num_tests - 3), runif(nrow(obs), min = 0, max = 1))
  
  obs[, "death0"] <- 0
  
  #---- Transpose the matrix for subsequent calculations ----
  obs = t(obs)
  
  #---- Calculating Sij and survival times for each individual ----
  obs[variable_names$Sij_varnames[1:num_tests], ] <- survival(obs)
  obs["survtime", ] <- colSums(obs[variable_names$Sij_varnames[1:num_tests], ], 
                               na.rm = TRUE)
  
  #---- Calculating random time to dementia for individuals ----
  obs[variable_names$random_timetodem_varnames[4:num_tests], ] <- 
    random_timetodem(obs)
  
  #---- Calculating death data for each individual ----
  #Indicator of 1 means the individual died in that interval
  #NAs mean the individual died in a prior interval
  obs[variable_names$deathij_varnames[1:num_tests], ] <- 
    (obs[variable_names$Sij_varnames[1:num_tests], ] < int_time)*1 
  
  obs["study_death", ] <- 
    colSums(obs[variable_names$deathij_varnames[1:num_tests], ], na.rm = TRUE) #Study death indicator
  
  obs["age_death", ] <- obs["age0", ] + obs["survtime", ]
  
  #---- Dementia indicators ----
  #Set all indicators to 0 first
  obs[variable_names$dem_varnames, ] <- 0
  
  #Based on Ci value
  for(i in 1:ncol(obs)){
    below_dem <- min(which(obs[variable_names$Ci_varnames, i] < dem_cut))
    if(is.finite(below_dem)){
      obs["dem_wave", i] <- (below_dem - 1)
      obs["dem", i] <- 1
      obs["dem_Ci", i] <- 1
    } else{
      obs["dem", i] <- 0
      obs["dem_Ci", i] <- 0
    }
  }
  
  #Calculate time to dementia
  obs["timetodem", ] <- dem_onset(obs, dem_cut)
  
  #Based on random/shock time to dementia model
  obs["dem_random", ] <- 0
  
  for(i in 1:ncol(obs)){
    random_dem <- 3 + min(which(
      obs[variable_names$random_timetodem_varnames[4:num_tests], i] <
        obs[variable_names$Sij_varnames[4:num_tests], i]))
    if(is.finite(random_dem)){
      timeto_random_dem <- 5*(random_dem - 1) +
        obs[variable_names$random_timetodem_varnames[random_dem], i]
      
      if(obs["dem", i] == 0){
        obs["dem_random", i] <- 1
        obs["dem", i] <- 1
        obs["dem_wave", i] <- random_dem
        obs["timetodem", i] <- timeto_random_dem
        
      } else if(timeto_random_dem <= obs["timetodem", i]){
        obs["dem_random", i] <- 1
        obs["timetodem", i] <- timeto_random_dem
        
        if(obs["dem_wave", i] != random_dem){
          obs["dem_Ci", i] <- 0
          obs["dem_wave", i] <- random_dem
        }
        
      }
    } 
  }
  
  #Fill in dementia indicator based on dem_wave
  for(i in 1:ncol(obs)){
    if(!is.na(obs["dem_wave", i])){
      obs[variable_names$dem_varnames[obs["dem_wave", i] + 1], i] <- 1
    }
  }
  
  #---- Dementia calculations ----
  obs <- compare_survtime_timetodem(obs)
  obs["ageatdem", ] <- obs["age0", ] + obs["timetodem", ] #Age at dementia diagnosis

  #---- Censor Ci and dem data ----
  obs <- survival_censor(obs)
  
  #---- Last Ci value ----
  obs["last_Ci", ] <- last_Ci(obs)
  
  #Dementia status at death
  for(i in 1:ncol(obs)){
     if(obs["dem", i] == 1 & obs["timetodem", i] <= obs["survtime", i]){
       obs["dem_death", i] <- 1
     } else if(obs["study_death", i] == 1 &
               (obs["dem", i] == 0 | (obs["dem", i] == 1 &
                                      obs["timetodem", i] >
                                     obs["survtime", i]))){
      obs["dem_death", i] <- 2
    } else {
      obs["dem_death", i] <- 0
    }
  }

  #Time to dem_death
  for(i in 1:ncol(obs)){
    if(obs["dem", i] == 0){
      obs["timetodem_death", i] <- obs["survtime", i]
    } else {
      obs["timetodem_death", i] <- min(obs["timetodem", i], obs["survtime", i])
    }
  }
  
  obs["ageatdem_death", ] <- obs["age0", ] + obs["timetodem_death", ]
  obs["dem_alive", obs["dem_death", ] == 1] <- 1
  obs["dem_alive", is.na(obs["dem_alive", ])] <- 0
  
  #---- Contributed time ----
  #Start with 0 contributed time for everyone
  obs[variable_names$contributed_varnames[1:9], ] <- 0
  
  #Fill in contributed time
  for(i in 1:ncol(obs)){
    #5-year bands
    last_full_slot <- floor(obs["timetodem_death", i]/5)
    full_slots <- variable_names$contributed_varnames[1:last_full_slot]
    obs[full_slots, i] <- 5
    if(last_full_slot != 9){
      partial_slot <- last_full_slot + 1
      obs[variable_names$contributed_varnames[partial_slot], i] <-
        obs["timetodem_death", i]%%5
    }
  }
  
  #---- Contributed time (1-year bands) ----
  #Start with 0 contributed time for everyone
  obs[variable_names_1year$contributed_varnames, ] <- 0
  
  #Fill in contributed time
  for(i in 1:ncol(obs)){
    for(j in 1:num_tests){
      contributed_var <- variable_names$contributed_varnames[j]
      contributed_vars_1year_block <-
        variable_names_1year$contributed_varnames[(5*(j-1) + 1):(5*j)]
      
      if(is.na(obs[contributed_var, i])){
        break
      } else if(obs[contributed_var, i] == int_time){
        obs[contributed_vars_1year_block, i] <- 1
      } else {
        last_full_slot <- floor(obs[contributed_var, i])
        if(last_full_slot == 0){
          obs[contributed_vars_1year_block[1], i] <- obs[contributed_var, i]
        } else {
          full_slots <-
            contributed_vars_1year_block[1:last_full_slot]
          obs[full_slots, i] <- 1
          partial_slot <- last_full_slot + 1
          obs[contributed_vars_1year_block[partial_slot], i] <-
            (obs[contributed_var, i] - last_full_slot)
        }
      }
    }
  }
  
  #---- Dementia indicators (1-year bands) ----
  #Start with 0 indicators for everybody
  obs[variable_names_1year$dem_varnames, ] <- 0
  
  for(i in 1:ncol(obs)){
    if(!is.na(obs["dem_wave", i])){
      index = ceiling(obs["timetodem", i])
      obs[variable_names_1year$dem_varnames[index], i] <- 1
    }
  }
  
  #---- Values to return ----
  return(as.data.frame(t(obs)))
}



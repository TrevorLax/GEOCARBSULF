##==============================================================================
## getData.R
##
## Read CO2 proxy data, including skew-normal/normal fits for CO2 uncertainty
## distributions (previously fit using processData_[something].R).
##
## Assumes that `filename.data` will have been set in the calling routine.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

data_calib_all <- read.csv(filename.data, fill=TRUE, header=TRUE)

ind_data    <- which(data_to_assim[2,]==TRUE)
n_data_sets <- length(ind_data)
ind_assim   <- vector("list",n_data_sets)
for (i in 1:n_data_sets) {
  ind_assim[[i]] <- which(as.character(data_calib_all$proxy_type) == data_to_assim[1,ind_data[i]])
}
data_calib <- data_calib_all[unlist(ind_assim),]

# assumption of steady state in-between model time steps permits figuring out
# which model time steps each data point should be compared against in advance.
# doing this each calibration iteration would be outrageous!
# This assumes the model time step is 10 million years, seq(570,0,by=-10). The
# model will choke later (in calibration) if this is not consistent with what is
# set within the actual GEOCARB physical model.
tstep <- 10
age_tmp <- seq(570,0,by=-tstep)
ind_mod2obs <- rep(NA, length(data_calib$age))
for (ii in 1:length(age_tmp)) {
  idx <- which( (data_calib$age < age_tmp[ii]+.5*tstep) &
                (data_calib$age >= age_tmp[ii]-.5*tstep) )
  ind_mod2obs[idx] <- ii
}

##==============================================================================
## End
##==============================================================================

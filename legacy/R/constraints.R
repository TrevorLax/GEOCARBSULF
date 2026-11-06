##==============================================================================
## constraints.R
##
## void function. Returns an object `windows` that is ntime x 2, where the two
## columns are a lower and upper bound for windows at each time slice. The
## precalibration will only permit simulations that pass through all of these
## windows (or some minimum number of the windows). Temperature and CO2.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================


windows <- vector('list', 2)
names(windows) <- c("co2", "temp")
for (nn in names(windows)) {
  windows[[nn]] <- mat.or.vec(n_time, 2)
  colnames(windows[[nn]]) <- c("low","high")
}
nsig <- 1 # number of standard deviations +/- to extend the window


##==============================================================================
## CO2 constraints
##================

## for each time period, pool the observations from that 10 Myr slice

for (tt in 1:n_time) {
    # start each window at 0 to 50000 ppmv range
    windows$co2[tt,"low"] <- 0
    windows$co2[tt,"high"] <- 50000
    idx <- which((data_calib$age < (time[tt]+5)) & (data_calib$age >= (time[tt]-5)))
    if (length(idx) > 0) {
        sigmas <- log10(data_calib$co2_high[idx]/data_calib$co2[idx])
        centers <- log10(data_calib$co2[idx])
        tops <- centers + nsig*sigmas
        bots <- centers - nsig*sigmas
        tops_max <- 10^(max(tops))
        bots_min <- 10^(min(bots))
        windows$co2[tt,"low"] <- max(c(bots_min,windows$co2[tt,"low"]))
        windows$co2[tt,"high"] <- min(c(tops_max,windows$co2[tt,"high"]))
    }
}
##==============================================================================


##==============================================================================
## Temperature constraints
##========================

if (!exists("filename.temperature")) {filename.temperature <- "../input_data/Mills_GR_2019_temp_co2.csv"}
data_temps <- read.csv(filename.temperature, col.names=c('time','co2_max','co2_min','T_max','T_min','T_avg'))

# comparisons of temperatures - all relative to "present" (t=0)
# For the Mills et al, upper and lower are the average +/- 1 sigma.
# We want nsig (from `constraints.R`), so take as bounds:
#    upper |--> average + nsig*(upper - average)
#    lower |--> average - nsig*(average - lower)

temp_upper <- data_temps[,"T_avg"] + nsig*(data_temps[,"T_max"]-data_temps[,"T_avg"])
temp_lower <- data_temps[,"T_avg"] - nsig*(data_temps[,"T_avg"]-data_temps[,"T_min"])

# normalize relative to "present"  -- don't do, and use Berner 2004's T0 = 15 deg C
##subtract <- data_temps[1,"T_avg"]
##temp_upper <- temp_upper - subtract
##temp_lower <- temp_lower - subtract

windows_temp <- cbind(temp_lower, temp_upper)
idx_temp <- match(-age, data_temps[,"time"])
windows_temp <- windows_temp[idx_temp,]
windows$temp[,c("low","high")] <- windows_temp
windows$temp_sol <- windows$temp + array(rep(7.4*time/570,2), dim=c(58,2))
windows$temp_sol_geog <- windows$temp + array(rep(par_time_center[,"GEOG"],2), dim=c(58,2))

# So, `windows$temp` has the solar luminosity contribution included, but
# `windows$temp_sol` has it removed.
# The `lhs_sampling.R` precalibration includes solar luminosity:
# -->       prcout_temp[ii] <- percout(model_temp_this_chunk[,ii], windows$temp)
# But for plotting, we'll want to (edit 21 Dec 2020) add back in the paleogeography component too
##==============================================================================


##==============================================================================
## End
##==============================================================================

##==============================================================================
## lhs_supp.R
##
## Set up the Latin hypercube analyses for the supplemental experiments.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

# calibration parameters and input data
filename.data <- '../input_data/CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv'
filename.calibinput <- '../input_data/GEOCARB_input_summaries_calib_all.csv'

# create output file names
data_appen <- ""
if (use_co2) {data_appen <- paste(data_appen,"c",sep="")}
if (use_temperature) {data_appen <- paste(data_appen,"t",sep="")}
if (!exists("appen")) {appen <- ""}
filename.covarout <- paste('../output/lhs_covar_',data_appen,'_out',prcout_threshold*100,'_',appen,'.RData',sep='')
filename.paramout <- paste('../output/lhs_param_',data_appen,'_out',prcout_threshold*100,'_',appen,'.RData',sep='')

source("model_setup.R")
source('run_geocarb_suppF.R')
source('model_run_supp.R')
n_parameters <- length(parnames_const_calib)
n_parameters_time <- length(parnames_time_calib)

## preliminary simulation to get the length
model_out <- model_run_supp(par_calib=par_calib0,
                            par_time=par_time_center,
                            par_fixed=par_fixed0,
                            parnames_calib=parnames_const_calib,
                            parnames_fixed=parnames_const_fixed,
                            parnames_time=parnames_time_calib,
                            age=age,
                            ageN=ageN,
                            ind_const_calib=ind_const_calib,
                            ind_time_calib=ind_time_calib,
                            ind_const_fixed=ind_const_fixed,
                            ind_time_fixed=ind_time_fixed,
                            ind_expected_time=ind_expected_time,
                            ind_expected_const=ind_expected_const,
                            iteration_threshold=iteration_threshold)
n_time <- length(model_out[,"co2"])
time <- model_out[,1]
source('percent_outbound.R')
source('constraints.R')

##==============================================================================



##==============================================================================
## Establish upper and lower bounds for each parameter
## (NA if none (inf))
##====================================================

bounds <- mat.or.vec(nr=length(ind_const_calib), nc=2)
colnames(bounds) <- c("lower","upper")
rownames(bounds) <- parnames_const_calib
for (ii in 1:nrow(bounds)) {
  row_num <- match(parnames_const_calib[ii],input$parameter)
  if (as.vector(input[row_num,"lower_limit"]) != "_inf") {
    # there is a lower bound
    bounds[ii,"lower"] <- as.numeric(as.vector(input[row_num,"lower_limit"]))
  } else {
    # no lower bound
    bounds[ii,"lower"] <- NA
  }
  if (is.finite(input[row_num,"upper_limit"])) {
    # there is an upper bound
    bounds[ii,"upper"] <- input[row_num,"upper_limit"]
  } else {
    # no upper bound
    bounds[ii,"upper"] <- NA
  }
}

##==============================================================================



##==============================================================================
## Do the actual sampling
##========================

source("lhs_sampling_supp.R")

##==============================================================================



##==============================================================================
## Save
##========================

save(list=c("par_covar_save"), file=filename.covarout)
save(list=c("par_calib_save","par_time_save"), file=filename.paramout)

##==============================================================================



##==============================================================================
## End
##==============================================================================

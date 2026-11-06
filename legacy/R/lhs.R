##==============================================================================
## lhs.R
##
## Set up Latin hypercube sampling with the GEOCARB model, for the main text
## model experiments of Wong et al. 2021.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

# calibration parameters and input data
# (defaults below are used unless the calling script, e.g. run_experiment.R,
# has already defined them)
if (!exists("filename.data")) {filename.data <- '../input_data/CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv'}
filename.calibinput <- '../input_data/GEOCARB_input_summaries_calib_all.csv'
if (!exists("output_dir")) {output_dir <- '../output/'}

# create output file names
data_appen <- ""
if (use_co2) {data_appen <- paste(data_appen,"c",sep="")}
if (use_temperature) {data_appen <- paste(data_appen,"t",sep="")}
filename.covarout <- paste(output_dir,'lhs_covar_',data_appen,'_out',prcout_threshold*100,'.RData',sep='')
filename.paramout <- paste(output_dir,'lhs_param_',data_appen,'_out',prcout_threshold*100,'.RData',sep='')
filename.modelout <- paste(output_dir,'lhs_model_',data_appen,'_out',prcout_threshold*100,'.RData',sep='')

source("model_setup.R")
n_parameters <- length(parnames_const_calib)
n_parameters_time <- length(parnames_time_calib)

## preliminary simulation to get the length
model_out <- model_run( par_calib=par_calib0,
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

source("lhs_sampling.R")

##==============================================================================



##==============================================================================
## Save
##========================

save(list=c("par_covar_save"), file=filename.covarout)
save(list=c("par_calib_save","par_time_save"), file=filename.paramout)
# run_geocarb output for the saved simulations (columns match par_calib_save rows);
# temp_save includes the +15 deg C offset but NOT solar luminosity or GEOG (see lhs_sampling.R)
save(list=c("time","co2_save","temp_save","o2_save","prcout_co2_save","prcout_temp_save","n_simulated"),
     file=filename.modelout)

##==============================================================================



##==============================================================================
## End
##==============================================================================

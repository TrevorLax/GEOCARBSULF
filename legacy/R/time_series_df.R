##==============================================================================
## time_series_df.R
##
## Figure out what the degrees of freedom should be for each time series
## parameter's covariance matrix inverse Wishart prior distribution.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

# par_time_center and par_time_stdev are the guys

f_var_red <- matrix( c(0,0.82,0.80,0.84,0.20,0.55,0.55,0.60,0,0.75,0.65,0.55), 12, 1)
rownames(f_var_red) <- colnames(par_time_stdev)

# pick degrees of freedom for each parameter so the variance matches the
# reduced variance (improved model failure rate) experiments of Royer et al 2014
df <- matrix(rep(NA,12),12,1)
rownames(df) <- colnames(par_time_stdev)
for (pp in 1:12) {
  df[pp] <- n_time + 3 + ceil(2*max(par_time_stdev[,pp]^2)/(1-f_var_red[pp]))
}

##==============================================================================
## End
##==============================================================================

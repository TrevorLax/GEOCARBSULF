##==============================================================================
## percent_outbound.R
##
## Compute the proportion of model simulation points from `time_series`
## that lie outside the given `windows`.
##
## In GEOCARB, many model simulations using naive parameters (sampled from
## the prior distributions, for example) will lead to model failure in the
## sense that some of the timesteps have infinities or NANs. In those cases
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

percout <- function(time_series, windows) {
  if (any(is.infinite(time_series))) {return(1)} else {
    p_out <- sum(time_series < windows[,1] | time_series > windows[,2]) / length(time_series)
    return(p_out)
  }
}

##==============================================================================
## End
##==============================================================================

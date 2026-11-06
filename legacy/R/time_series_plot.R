##==============================================================================
## time_series_plot.R
##
## Plot of the time series parameters' prior distributions and precalibrated
## distributions.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

time_series_labels <- c(expression(bold('a')),expression(bold('b')),expression(bold('c')),expression(bold('d')),
                        expression(bold('e')),expression(bold('f')),expression(bold('g')),expression(bold('h')),
                        expression(bold('i')),expression(bold('j')),expression(bold('k')),expression(bold('l')))

time_series_plot <- function() {

  bb <- "30"
  dd <- "ct"

  plot(-time, time_series_from_priors_quantiles[,"0.5",pp], type='l', xlim=c(-450,0), ylim=ylims, xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n')
  grid()
  polygon(-c(time,rev(time)), c(time_series_from_priors_quantiles[,"0.025",pp],rev(time_series_from_priors_quantiles[,"0.975",pp])), col=rgb(.5,.5,.5,.4), border=NA)
  lines(-time, time_series_from_priors_quantiles[,"0.5",pp], lwd=1, lty=1, col=rgb(.5,.5,.5))
  polygon(-c(time,rev(time)), c(par_time_quantiles[[bb]][[dd]][,"0.025",pp],rev(par_time_quantiles[[bb]][[dd]][,"0.975",pp])), col=rgb(.6,0,0,.25), border=NA)
  lines(-time, par_time_quantiles[[bb]][[dd]][,"0.5",pp], lwd=1, lty=1, col=rgb(.6,0,0))
  mtext('Time [Myr ago]', side=1, line=2.8)
  #mtext(expression("        Global average\nsurface temperature ["*degree*"C]"), side=2, line=2.2)
  mtext(paste(parnames_time[pp],units), side=2, line=3.2)
  axis(1, at=seq(-400,0,100), labels=c('400','300','200','100','0'))
  ticks=seq(from=ylims[1], to=ylims[2], by=dy)
  axis(2, at=ticks, labels=ticks, las=1)
  mtext(side=3, text=time_series_labels[pp], line=0, cex=1, adj=0)

}

##==============================================================================
## End
##==============================================================================

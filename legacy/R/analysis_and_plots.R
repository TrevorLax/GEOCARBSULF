##==============================================================================
## analysis_and_plots.R
##
## Read results from the Latin Hypercube Sampling experiments.
## Generate figures for manuscript and supplemental material.
## Calculate numbers for analysis and comparison among experiments and previous
## works.
##
## Questions? Tony Wong (aewsma@rit.edu)
##==============================================================================

rm(list=ls())

library(abind)
library(Hmisc)

if(Sys.info()['user']=='tony') {
  # Tony's local machine (if you aren't me, you almost certainly need to change this...)
  machine <- 'local'
  setwd('/Users/tony/codes/GEOCARB-precalibration/R')
} else if(Sys.info()['user']=='aewsma') {
  machine <- 'office'
  setwd('/Users/aewsma/codes/GEOCARB-precalibration/R')
} else {
  # assume on another cluster of some kind...
  machine <- 'remote'
  setwd('~/work/codes/GEOCARB-precalibration/R')
}

##
## read and save quantiles of all the parameters for the experiments
## when computing the quantiles, sample down to only 10000 from each experiment
## (so number of samples does not bias results)
##

## model setup
param_choice <- 'all'   # Calibrate all 68 parameters? ("all") or only the 6 from Park and Royer 2011 ("PR2011")
data_choice <- 'F2017'    # Which data set?  PR2011 = Park and Royer (2011), or F2017 = Foster et al (2017)
fSR_choice <- 'DT2019'     # Which fSR time series? ("PR2011", "LENTON", "DT2019")
filename.data <- '../input_data/CO2_Proxy_Foster2017_calib_SN-co2_25Sep2018.csv'
source("model_setup.R")
source("percent_outbound.R")
source("constraints.R")

num_samples <- 10000
quantiles_i_want <- c(0, 0.025, 0.05, 0.25, 0.5, 0.75, 0.95, 0.975, 1)
prc_outbound <- as.character(c(30,35,40,45,50))
data_sets <- c("c","t","ct")
par_calib <- par_quantiles <- par_time <- par_time_quantiles <- idx_sample <- vector("list", length(prc_outbound))
names(par_calib) <- names(par_quantiles) <- names(par_time) <- names(par_time_quantiles) <- names(idx_sample) <- prc_outbound

for (bb in prc_outbound) {
    par_calib[[bb]] <- par_quantiles[[bb]] <- par_time[[bb]] <- par_time_quantiles[[bb]] <- vector("list", length(data_sets))
    names(par_calib[[bb]]) <- names(par_quantiles[[bb]]) <- names(par_time[[bb]]) <- names(par_time_quantiles[[bb]]) <- data_sets
    for (dd in data_sets) {
        if ((bb!="30") | (dd!="ct")) {
            load(paste("../output/lhs_param_",dd,"_out",bb,".RData", sep=""))
            par_calib[[bb]][[dd]] <- cbind(par_calib_save, rep(0,nrow(par_calib_save)))
            colnames(par_calib[[bb]][[dd]]) <- c(colnames(par_calib_save), "deltaT2Xglac")
            par_time[[bb]][[dd]] <- par_time_save
        } else {
            ## need to read the parameters for the 30% outbound and carbon+temperature data
            ## experiment separately because the success rate is quite low
            # first simulation set, with seed=1234*ii=13574 (ii=11 is this simulation set)
            load(paste("../output/lhs_param_ct_out30_seed13574.RData", sep=""))
            par_calib[[bb]][[dd]] <- cbind(par_calib_save, rep(0,nrow(par_calib_save)))
            colnames(par_calib[[bb]][[dd]]) <- c(colnames(par_calib_save), "deltaT2Xglac")
            par_time[[bb]][[dd]] <- par_time_save
            # second simulation set, with seed=ii=11
            load(paste("../output/lhs_param_ct_out30_seed11.RData", sep=""))
            par_calib[[bb]][[dd]] <- rbind(par_calib[[bb]][[dd]], cbind(par_calib_save, rep(0,nrow(par_calib_save))))
            par_time[[bb]][[dd]] <- abind(par_time[[bb]][[dd]], par_time_save, along=2)
            # third simulation set, with seed=2020
            load(paste("../output/lhs_param_ct_out30_seed2020.RData", sep=""))
            par_calib[[bb]][[dd]] <- rbind(par_calib[[bb]][[dd]], cbind(par_calib_save, rep(0,nrow(par_calib_save))))
            par_time[[bb]][[dd]] <- abind(par_time[[bb]][[dd]], par_time_save, along=2)
            # trim down to 10,000 (or whatever num_samples is above) to match the other simulations
        }
        ## quantiles for the constant parameters
        par_quantiles[[bb]][[dd]] <- mat.or.vec(nr=ncol(par_calib[[bb]][[dd]])+1, nc=length(quantiles_i_want))
        rownames(par_quantiles[[bb]][[dd]]) <- c(colnames(par_calib[[bb]][[dd]]), "deltaT2Xglac")
        colnames(par_quantiles[[bb]][[dd]]) <- as.character(quantiles_i_want)
        if(nrow(par_calib[[bb]][[dd]]) >= num_samples) {
            idx_sample[[bb]][[dd]] <- sample(1:nrow(par_calib[[bb]][[dd]]), size=num_samples, replace=FALSE)
        } else {
            idx_sample[[bb]][[dd]] <- sample(1:nrow(par_calib[[bb]][[dd]]), size=num_samples, replace=TRUE)
        }
        for (pp in 1:ncol(par_calib[[bb]][[dd]])) {
            par_quantiles[[bb]][[dd]][pp,] <- quantile(par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]],pp], quantiles_i_want)
        }
        par_calib[[bb]][[dd]][,"deltaT2Xglac"] <- par_calib[[bb]][[dd]][,"deltaT2X"]*par_calib[[bb]][[dd]][,"GLAC"]
        par_quantiles[[bb]][[dd]]["deltaT2Xglac",] <- quantile(par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]],"deltaT2Xglac"], quantiles_i_want)
        ## quantiles for the time-varying parameters
        par_time_quantiles[[bb]][[dd]] <- array(NA, dim=c(dim(par_time[[bb]][[dd]])[1],length(quantiles_i_want),dim(par_time[[bb]][[dd]])[3]), dimnames=list(1:n_time, quantiles_i_want, parnames_time))
        for (pp in 1:dim(par_time[[bb]][[dd]])[3]) {
            for (tt in 1:dim(par_time[[bb]][[dd]])[1]) {
                par_time_quantiles[[bb]][[dd]][tt,,pp] <- quantile(par_time[[bb]][[dd]][tt,,pp], quantiles_i_want)
            }
        }
    }
}

##
## run ensemble with the 30-both parameters
##

## run hindcasts

model_hindcast <- prcout <- vector("list", length(prc_outbound))
names(model_hindcast) <- names(prcout) <- prc_outbound

for (bb in prc_outbound) {
    model_hindcast[[bb]] <- prcout[[bb]] <- vector("list", length(data_sets))
    names(model_hindcast[[bb]]) <- names(prcout[[bb]]) <- data_sets
    for (dd in data_sets) {
        model_hindcast[[bb]][[dd]] <- vector('list', 2)
        names(model_hindcast[[bb]][[dd]]) <- c("co2","temp")
        prcout[[bb]][[dd]] <- mat.or.vec(nr=num_samples, nc=2)
        colnames(prcout[[bb]][[dd]]) <- c("co2","temp")
        model_hindcast[[bb]][[dd]]$co2 <- model_hindcast[[bb]][[dd]]$temp <- mat.or.vec(nr=58, nc=num_samples)
        for (ii in 1:num_samples) {
            model_out <- model_run(par_calib=par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]][ii],],
                                   par_time=par_time[[bb]][[dd]][,idx_sample[[bb]][[dd]][ii],],
                                   par_fixed=par_const_fixed0,
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
            prcout[[bb]][[dd]][ii,"co2"] <- percout(model_out[,"co2"], windows$co2)
            prcout[[bb]][[dd]][ii,"temp"] <- percout(model_out[,"temp"] + 15, windows$temp)
            model_hindcast[[bb]][[dd]]$co2[,ii] <- model_out[,"co2"]
            model_hindcast[[bb]][[dd]]$temp[,ii] <- model_out[,"temp"] + par_time[[bb]][[dd]][, idx_sample[[bb]][[dd]][ii], match("GEOG",parnames_time)] + 15 # as in Berner 2004
            # ^-- temperatures in model output already include the Ws solar luminosity term to be akin to Mills et al windows. Just need GEOG.
#            model_hindcast[[bb]][[dd]]$temp[,ii] <- model_out[,"temp"] + par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]][ii],"Ws"]*model_out[,1]/570 + 15 # as in Berner 2004
        }
    }
}

## compute model quantiles for plotting against proxy data, for each experiment
model_quantiles <- vector("list", length(prc_outbound))
names(model_quantiles) <- prc_outbound
for (bb in prc_outbound) {
		model_quantiles[[bb]] <- vector("list", length(data_sets))
    names(model_quantiles[[bb]]) <- data_sets
    for (dd in data_sets) {
    		model_quantiles[[bb]][[dd]] <- vector("list", 2)
        names(model_quantiles[[bb]][[dd]]) <- c("co2","temp")
        for (oo in c("co2", "temp")) {
        		model_quantiles[[bb]][[dd]][[oo]] <- mat.or.vec(nr=58, nc=length(quantiles_i_want))
            for (tt in 1:58) {
            		model_quantiles[[bb]][[dd]][[oo]][tt,] <- quantile(model_hindcast[[bb]][[dd]][[oo]][tt,], quantiles_i_want)
            }
            colnames(model_quantiles[[bb]][[dd]][[oo]]) <- as.character(quantiles_i_want)
        }
    }
}



##==============================================================================
##
## make a plot of the hindcasts relative to proxy data
##

# pick which simulation set to display
bb <- "30"
dd <- "ct"

# don't want to plot proxy windows for time periods without data
idx_no_data <- which(windows$co2[,"low"]==0 | windows$co2[,"high"]==50000)
idx_data <- setdiff(1:n_time, idx_no_data)
ifirst <- idx_data[1]
idx_data <- c(ifirst-1, idx_data) # start time series 1 earlier for continuity in the figure


pdf('../figures/model_vs_proxy.pdf',width=4,height=6,colormodel='cmyk', pointsize=11)

par(mfrow=c(2,1), mai=c(0.6,.9,.18,.15))
plot(-time, log10(model_quantiles[[bb]][[dd]]$co2[,"0.5"]), type='l', xlim=c(-425,0), ylim=c(-0.3,log10(40000)), xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n')
grid()
polygon(-c(time[idx_data],rev(time[idx_data])), log10(c(windows$co2[idx_data,"high"],rev(windows$co2[idx_data,"low"]))), col=rgb(.5,.5,.5,.5), border=1, lty=1)
igood <- which(is.finite(model_quantiles[[bb]]$t$co2[,"0.025"])); lines(-time[igood], log10(model_quantiles[[bb]]$t$co2[igood,"0.025"]), lwd=1, lty=5)
igood <- which(is.finite(model_quantiles[[bb]]$t$co2[,"0.975"])); lines(-time[igood], log10(model_quantiles[[bb]]$t$co2[igood,"0.975"]), lwd=1, lty=5)
polygon(-c(time,rev(time)), log10(c(model_quantiles[[bb]][[dd]]$co2[,"0.025"],rev(model_quantiles[[bb]][[dd]]$co2[,"0.975"]))), col=rgb(0,.15,.7,.25), border=NA)
polygon(-c(time,rev(time)), log10(c(model_quantiles[[bb]][[dd]]$co2[,"0.05"],rev(model_quantiles[[bb]][[dd]]$co2[,"0.95"]))), col=rgb(0,.15,.7,.45), border=NA)
polygon(-c(time,rev(time)), log10(c(model_quantiles[[bb]][[dd]]$co2[,"0.25"],rev(model_quantiles[[bb]][[dd]]$co2[,"0.75"]))), col=rgb(0,.15,.7,.65), border=NA)
#polygon(-c(time,rev(time)), log10(c(windows$co2[,"high"],rev(windows$co2[,"low"]))), col=rgb(.5,.5,.5,.5), border=NA)
lines(-time, log10(model_quantiles[[bb]][[dd]]$co2[,"0.5"]), lwd=1, lty=1, col=rgb(0,.15,.7))
mtext('Time (Myr ago)', side=1, line=2.1)
mtext(expression('CO'[2]*' concentration (ppmv)'), side=2, line=3.5)
axis(1, at=seq(-400,0,100), labels=c('400','300','200','100','0'))
ticks=log10(c(seq(1,10,1),seq(10,100,10),seq(200,1000,100),seq(2000,10000,1000),seq(20000,100000,10000)))
axis(2, at=ticks, labels=rep('',length(ticks)))
axis(2, at=log10(c(1,10,100,1000,10000)), labels=c('1','10','100','1000','10000'), las=1)
#axis(2, at=log10(c(3,10,30,100,300,1000,3000,10000)), labels=c('3','10','30','100','300','1000','3000','10000'), las=1)
legend(-420, 0.6, c('This work (median and 50%, 90% and 95% ranges)',expression('95% range without CO'[2]*' data'),'Data from Foster et al. (2017)'), pch=c(15,NA,15), lty=c(NA,5,NA), col=c(rgb(0,0,.6,.5),'black',rgb(.5,.5,.5,.5)), pt.cex=1.2, cex=.6, bty='n', y.intersp=1)
legend(-420, 0.6, c('This work (median and 50%, 90% and 95% ranges)',expression('95% range without CO'[2]*' data'),'Data from Foster et al. (2017)'), pch=c('-','',''), lty=c(NA,5,NA), col=c(rgb(0,0,.6,.5),'black',rgb(.5,.5,.5,.5)), cex=.6, bty='n', y.intersp=1)
mtext(side=3, text=expression(bold('   a')), line=0, cex=1, adj=-0.24);

plot(-time, model_quantiles[[bb]][[dd]]$temp[,"0.5"], type='l', xlim=c(-425,0), ylim=c(5,56), xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n')
grid()
igood <- which(is.finite(model_quantiles[[bb]]$c$temp[,"0.025"])); lines(-time[igood], model_quantiles[[bb]]$c$temp[igood,"0.025"], lwd=1, lty=5)
igood <- which(is.finite(model_quantiles[[bb]]$c$temp[,"0.975"])); lines(-time[igood], model_quantiles[[bb]]$c$temp[igood,"0.975"], lwd=1, lty=5)
polygon(-c(time,rev(time)), c(windows$temp_sol_geog[,"high"],rev(windows$temp_sol_geog[,"low"])), col=rgb(.5,.5,.5,.5), border=1, lty=1)
polygon(-c(time,rev(time)), c(model_quantiles[[bb]][[dd]]$temp[,"0.025"],rev(model_quantiles[[bb]][[dd]]$temp[,"0.975"])), col=rgb(.6,0,0,.25), border=NA)
polygon(-c(time,rev(time)), c(model_quantiles[[bb]][[dd]]$temp[,"0.05"],rev(model_quantiles[[bb]][[dd]]$temp[,"0.95"])), col=rgb(.6,0,0,.45), border=NA)
polygon(-c(time,rev(time)), c(model_quantiles[[bb]][[dd]]$temp[,"0.25"],rev(model_quantiles[[bb]][[dd]]$temp[,"0.75"])), col=rgb(.6,0,0,.65), border=NA)
lines(-time, model_quantiles[[bb]][[dd]]$temp[,"0.5"], lwd=1, lty=1, col=rgb(.6,0,0))
mtext('Time (Myr ago)', side=1, line=2.1)
mtext(expression("        Global average\nsurface temperature ("*degree*"C)"), side=2, line=2.2)
axis(1, at=seq(-400,0,100), labels=c('400','300','200','100','0'))
ticks=seq(from=0, to=60, by=5)
axis(2, at=ticks, labels=rep('',length(ticks)))
axis(2, at=seq(from=0, to=60, by=10), las=1)
legend(-420, 56, c('This work (median and 50%, 90% and 95% ranges)','95% range without temperature data','Data from Mills et al. (2019)'), pch=c(15,NA,15), lty=c(NA,5,NA), col=c(rgb(.6,0,0,.5),'black',rgb(.5,.5,.5,.5)), pt.cex=1.2, cex=.6, bty='n', y.intersp=1)
legend(-420, 56, c('This work (median and 50%, 90% and 95% ranges)','95% range without temperature data','Data from Mills et al. (2019)'), pch=c('-','',''), lty=c(NA,5,NA), col=c(rgb(.6,0,0,.5),'black',rgb(.5,.5,.5,.5)), cex=.6, bty='n', y.intersp=1)
mtext(side=3, text=expression(bold('   b')), line=0, cex=1, adj=-0.24);

dev.off()

##==============================================================================



##==============================================================================
##
## compute uncertainty ranges for ESS for each experiment
##

# density estimates for the distributions of deltaT2X

# experiment you want
bb <- "30"
dd <- "ct"

# density of deltaT2X from this work
parnames_calib <- colnames(par_calib[[bb]][[dd]])
ics <- match('deltaT2X', parnames_calib)
deltaT2X_density <- density(par_calib[[bb]][[dd]][,ics], from=0, to=10)

iglac <- match('GLAC', parnames_calib)
glac_density <- density(par_calib[[bb]][[dd]][,iglac], from=1, to=5)

icsg <- match('deltaT2Xglac', parnames_calib)
deltaT2Xglac_density <- density(par_calib[[bb]][[dd]][,icsg], from=0, to=25)

# compare against deltaT2X from previous work
pr2011_dat <- read.csv('../input_data/ParkRoyer2011_Fig3_85varred.csv')
pr2011_cdf <- approxfun(pr2011_dat[,1], pr2011_dat[,4])
pr2011_icdf <- approxfun(pr2011_dat[,4], pr2011_dat[,1])
pr2011_pdf <- approxfun(pr2011_dat[,1], pr2011_dat[,3])

deltaT2X_density_pr2011 <- vector('list', 2); names(deltaT2X_density_pr2011) <- c('x','y')
deltaT2X_density_pr2011$x <- deltaT2X_density$x
deltaT2X_density_pr2011$y <- pr2011_pdf(deltaT2X_density_pr2011$x)

# Park and Royer 2011 have about 16% probability above deltaT2X = 6 deg C
print(1-pr2011_cdf(6))
print(1-pr2011_cdf(7))

# get priors too
row_num <- match('deltaT2X',input$parameter)
x_cs <- seq(from=0, to=10, by=0.1)
f_cs <- dlnorm(x=x_cs, meanlog=log(input[row_num,"mean"]), sdlog=log(0.5*input[row_num,"two_sigma"]))
row_num <- match('GLAC',input$parameter)
x_gl <- seq(from=0, to=10, by=0.1)
f_gl <- dnorm(x=x_gl, mean=input[row_num,"mean"], sd=(0.5*input[row_num,"two_sigma"]))

# Royer et al 2007:  1.5 and 6.2 deg C (5–95% range), 2.8 best fit
x_5_95_royer2007 <- c(1.6, 2.8, 5.5)
# Park and Royer 2011 from CSV/Excel table
x_5_95_pr2011 <- pr2011_icdf(c(.05,.5,.95))
x_5_95_thisstudy <- quantile(par_calib[[bb]][[dd]][,ics], c(.05,.5,.95))  #
x_5_95_glac <- quantile(par_calib[[bb]][[dd]][,ics]*par_calib[[bb]][[dd]][,iglac], c(.05,.5,.95))  #
x_ktc2017 <- c(3.7, 5.6, 7.5)

# deltaT2X quantiles from the prior distribution: P = Pr(dT2X <= Q)
# --> P = int_0^Q f(x) dx, where f(x) is the truncated log-normal


##
## figure comparing the 30%-outbound ct experiment
##

offset <- 0.1

pdf('../figures/deltaT2X_distributions.pdf',width=4,height=3, colormodel='cmyk', pointsize=11)
par(mfrow=c(1,1), mai=c(.7,.3,.13,.15))
plot(deltaT2X_density$x, deltaT2X_density$y + offset, type='l', lwd=1.7, xlim=c(0.85,10.1), ylim=c(0,.9+offset),
     xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n', axes=FALSE, col="steelblue")
lines(deltaT2X_density_pr2011$x, deltaT2X_density_pr2011$y + offset, lwd=1.7, lty=2)
lines(x_cs, f_cs + offset, lwd=1.7, lty=3, col="steelblue")
mtext(expression(Delta*"T"['2x']*" ("*degree*"C)"), side=1, line=2.3)
mtext('Density', side=2, line=0.3)
arrows(1, 0, 1, .85+offset, length=0.08, angle=30, code=2)
axis(1, at=seq(0,10))
minor.tick(nx=4, ny=0, tick.ratio=0.5)
y0 <- 0.7*offset; arrows(x_5_95_thisstudy[1], y0, x_5_95_thisstudy[3], y0, lwd=1.5, length=0.04, angle=90, code=3, col="steelblue"); points(x_5_95_thisstudy[2], y0, pch=16, col="steelblue")
y1 <- 0.3*offset; arrows(x_5_95_pr2011[1], y1, x_5_95_pr2011[3], y1, lwd=1.5, length=0.04, angle=90, code=3); points(x_5_95_pr2011[2], y1, pch=15)
xlegend <- c(5.2,5.85); ylegend <- 0.94; arrows(xlegend[1], ylegend, xlegend[2], ylegend, lwd=1.5, length=0.04, angle=90, code=3, col="black"); points(mean(xlegend), ylegend, pch=15, col="black", cex=0.85)
xlegend <- c(5.2,5.85); ylegend <- 0.79; arrows(xlegend[1], ylegend, xlegend[2], ylegend, lwd=1.5, length=0.04, angle=90, code=3, col="steelblue"); points(mean(xlegend), ylegend, pch=16, col="steelblue", cex=0.85)
legend(4.9,1.02, c('5-95% range, PR2011','PR2011','5-95% range, this study','a posteriori, this study','a priori, both studies'), lty=c(NA,2,NA,1,3), col=c("black","black","steelblue","steelblue","steelblue"), bty='n', lwd=1.7, cex=0.9)
dev.off()

##==============================================================================



##==============================================================================
##
## figure comparing the quantiles across the different experiments
##

y0 <- 0
ylims <- c(0,10)
width <- 0.5
offset <- 0.15
colors <- vector("list", 3); names(colors) <- data_sets
alphas <- c(0.45, 0.65)
colors$c <- c(rgb(0,.1,0.6,alphas[1]), rgb(0,.15,0.75,alphas[2]))
colors$t <- c(rgb(0.5,0,0,alphas[1]), rgb(0.8,0,0,alphas[2]))
colors$ct <- c(rgb(0.5,0,0.5,alphas[1]), rgb(0.85,0,0.85,alphas[2]))

bb <- "30"
pdf('../figures/deltaT2X_experiments.pdf',width=3,height=4, colormodel='cmyk', pointsize=11)
par(mfrow=c(1,1), mai=c(.7,.3,.13,.15))
plot(-10,-10, xlim=c(1.5,5.5), ylim=c(0+0.5*offset,10+0.5*offset), yaxt='n', ylab='', xlab='')
for (xx in seq(0,10)) {lines(rep(xx,2), 2*ylims, col=rgb(.65,.65,.65,1), lty=3, lwd=0.5)}
for (dd in rev(data_sets)) {
    for (bb in prc_outbound) {
        tmp <- par_quantiles[[bb]][[dd]]["deltaT2X",c("0.25","0.75","0.05","0.95","0.5")]
        polygon(c(tmp[3:4], rev(tmp[3:4])), c(rep(y0,2),rep(y0+width,2)), lwd=1, col=colors[[dd]][1])
        polygon(c(tmp[1:2], rev(tmp[1:2])), c(rep(y0,2),rep(y0+width,2)), lwd=1, col=colors[[dd]][2])
        lines(c(tmp[5],tmp[5]), c(y0,y0+width), type='l', lwd=2)
        if(dd=="ct") {text(5.3,y0+0.5*width,paste(bb,"%",sep=""))}
        y0 <- y0+width+offset
    }
    y0 <- y0+2*offset
}
#mtext(expression(Delta*"T(2x) ["*degree*"C]"), side=1, line=2.3)
mtext(expression(Delta*"T"['2x']*" ("*degree*"C)"), side=1, line=2.3)
minor.tick(ny=0)
mtext(expression('CO'[2]), side=2, line=.3, adj=0.87)
mtext("T", side=2, line=.5, adj=0.5)
mtext(expression("CO"[2]*" & T"), side=2, line=.3, adj=0.1)
dev.off()

##==============================================================================



##==============================================================================
##
## figure comparing the quantiles as sample size increases
##

y0 <- 0
ylims <- c(0,8.5)
width <- 0.7
offset <- 0.2
alphas <- c(0.45, 0.65)

bb <- "30"
dd <- "ct"
pdf('../figures/deltaT2X_samplesize.pdf',width=3,height=3, colormodel='cmyk', pointsize=11)
par(mfrow=c(1,1), mai=c(.7, .85, .15, .15))
plot(-10,-10, xlim=c(1.5,5.5), ylim=c(ylims[1]+1.0*offset,ylims[2]+0.5*offset), yaxt='n', ylab='', xlab='')
for (xx in seq(0,10)) {lines(rep(xx,2), 2*ylims, col=rgb(.65,.65,.65,1), lty=3, lwd=0.5)}
nn_test <- seq(1000,10000,1000)
yvals <- c()
for (nn in nn_test) {
    tmp_sample <- par_calib[[bb]][[dd]][1:nn,"deltaT2X"]
    tmp <- quantile(tmp_sample, c(0.25,0.75,0.025,0.975,0.5))
    polygon(c(tmp[3:4], rev(tmp[3:4])), c(rep(y0,2),rep(y0+width,2)), lwd=1, col=rgb(.5,.5,.5,alphas[1]))
    polygon(c(tmp[1:2], rev(tmp[1:2])), c(rep(y0,2),rep(y0+width,2)), lwd=1, col=rgb(.5,.5,.5,alphas[2]))
    lines(c(tmp[5],tmp[5]), c(y0,y0+width), type='l', lwd=2)
    yvals <- c(yvals, y0+0.5*width)
    y0 <- y0+width+offset
}
mtext(expression(Delta*"T"['2x']*" ("*degree*"C)"), side=1, line=2.3)
mtext("Sample size", side=2, line=3.3)
axis(side=2, at=yvals, labels=nn_test[1:length(yvals)], las=1)
minor.tick(ny=0)
dev.off()

##==============================================================================



##==============================================================================
##
## time series plots - priors vs posteriors
##

library(CholWishart)
library(MASS)

# get quantiles for the time series parameters
# generate samples from multivariate normal sampling with diagonal covariance

n_parameters_time <- dim(par_time[[bb]][[dd]])[3]
time_series_from_priors <- array(dim=c(n_time,num_samples,n_parameters_time), dimnames=list(1:n_time, 1:num_samples, parnames_time))
time_series_from_priors_quantiles <- array(dim=c(n_time,length(quantiles_i_want),n_parameters_time), dimnames=list(1:n_time, quantiles_i_want, parnames_time))
#covariance_from_priors <- array(dim=c(n_time,n_time,num_samples,n_parameters_time))
covariance_from_priors <- array(dim=c(n_time, n_time))
source("time_series_df.R")

for (pp in 1:n_parameters_time) {
  # these degrees of freedom give variances in line with the reduced variances
  # of Royer et al (2014, AJS), and set the sampled mean covariance on the
  # diagonal matrix of variances (df-(n_time+1))
  #covariance_from_priors[,,,pp] <- rInvWishart(num_samples, df[pp], (df[pp]-(n_time+1))*diag(par_time_stdev[,pp]^2))
  # now draw the actual time series
  for (ii in 1:num_samples) {
    # draw the covariance matrices JIT
    covariance_from_priors <- rInvWishart(1, df[pp], (df[pp]-(n_time+1))*diag(par_time_stdev[,pp]^2))
    #time_series_from_priors[,ii,pp] <- mvrnorm(n=1, mu=par_time_center[,pp], Sigma=covariance_from_priors[,,ii,pp])
    time_series_from_priors[,ii,pp] <- mvrnorm(n=1, mu=par_time_center[,pp], Sigma=covariance_from_priors[,,1])
    # normalize the ones that must be normalized (first batch with 1 as present, second with 0 as present)
    if (colnames(par_time_center)[pp] %in% c("fR", "fL", "fA", "fAw_fA", "fC")) {
      time_series_from_priors[,ii,pp] <- time_series_from_priors[,ii,pp]/time_series_from_priors[n_time,ii,pp]
    } else if (colnames(par_time_center)[pp] %in% c("GEOG")) {
      time_series_from_priors[,ii,pp] <- time_series_from_priors[,ii,pp] - time_series_from_priors[n_time,ii,pp]
    }
  }
  for (tt in 1:n_time) {
    time_series_from_priors_quantiles[tt,,pp] <- quantile(time_series_from_priors[tt,,pp], quantiles_i_want)
  }
}

source("time_series_plot.R")

pdf('../figures/time_series_parameters.pdf',width=6,height=8,colormodel='cmyk', pointsize=11)
par(mfrow=c(4,3), mai=c(0.6,.65,.15,.15))

pp <- 1; ylims <- c(60,103); dy <- 5; units <- "[0.70XX]"; time_series_plot()
legend(-450, 105, c("a priori","a posteriori"), pch=c(15,15), col=c(rgb(.5,.5,.5,.5), rgb(.6,0,0,.5)), pt.cex=1.2, cex=1.1, bty='n')
pp <- 2; ylims <- c(-2,6); dy <- 1; units <- "[per mil]"; time_series_plot()
pp <- 3; ylims <- c(10,35); dy <- 5; units <- "[per mil]"; time_series_plot()
pp <- 4; ylims <- c(0,1.5); dy <- 0.25; units <- "[unitless]"; time_series_plot()
pp <- 5; ylims <- c(0,3); dy <- 0.5; units <- "[unitless]"; time_series_plot()
pp <- 6; ylims <- c(0,2); dy <- 0.5; units <- "[unitless]"; time_series_plot()
pp <- 7; ylims <- c(0,2); dy <- 0.5; units <- "[unitless]"; time_series_plot()
pp <- 8; ylims <- c(0,2); dy <- 0.5; units <- "[unitless]"; time_series_plot()
pp <- 9; ylims <- c(0,.12); dy <- 0.02; units <- "[1/K]"; time_series_plot()
pp <- 10; ylims <- c(-6,8); dy <- 2; units <- "[deg C]"; time_series_plot()
pp <- 11; ylims <- c(0,4); dy <- 1; units <- "[unitless]"; time_series_plot()
pp <- 12; ylims <- c(0,2); dy <- 0.5; units <- "[unitless]"; time_series_plot()

dev.off()

##==============================================================================



##==============================================================================
##
## report numbers for the manuscript
##

## deltaT2X in "control" experiment
range <- round(par_quantiles$`30`$ct["deltaT2X",c("0.05","0.95","0.5")],4)
print(paste("50% (5-95%) range for deltaT2X is:",range[3], range[1], range[2]))

## Pr(deltaT2X >= 6 deg C)
pr <- length(which(par_calib$`30`$ct[,"deltaT2X"] >= 6))/nrow(par_calib$`30`$ct)
print(paste("Pr(deltaT2X >= 6) =",round(pr,4)))

## GLAC in "control" experiment
range <- round(par_quantiles$`30`$ct["GLAC",c("0.05","0.95","0.5")],4)
print(paste("50% (5-95%) range for GLAC is:",range[3], range[1], range[2]))

## deltaT2X*GLAC in "control" experiment
range <- round(par_quantiles$`30`$ct["deltaT2Xglac",c("0.05","0.95","0.5")],4)
print(paste("50% (5-95%) range for deltaT2X is:",range[3], range[1], range[2]))

## prior and posterior 5-95% ranges and means/medians
som_parameters_table <- mat.or.vec(nr=56, nc=6)
colnames(som_parameters_table) <- c("prior mean", "prior 5th percentile", "prior 95th percentile",
                                    "posterior median", "posterior 5th percentile", "posterior 95th percentile")
rownames(som_parameters_table) <- parnames_calib[1:56]
for (pp in rownames(som_parameters_table)) {
  # priors
  idx_match <- match(pp,input[,"parameter"])
  som_parameters_table[pp,"prior mean"] <- input[idx_match,"mean"]
  if (input[idx_match,"distribution_type"] == "gaussian") {
    if (is.infinite(input[idx_match,"upper_limit"])) {
      if (input[idx_match,"lower_limit"]=="_inf") {
        # Gaussian business as usual
        p05 <- qnorm(p=0.05, mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
        p95 <- qnorm(p=0.95, mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
      } else {
        # lower bound some number alpha, upper bound infinity, so pdf is pdf/(1-cdf(alpha))
        cdf <- pnorm(as.numeric(as.vector(input[idx_match,"lower_limit"])), mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
        p05 <- qnorm(0.05+(1-0.05)*cdf, mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
        p95 <- qnorm(0.95+(1-0.95)*cdf, mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
      }
    } else {
      # must have a finite upper bound...
      if (input[idx_match,"lower_limit"]=="_inf") {
        # infinite lower bound
        # --> this case doesn't happen, but put an error message here just in case
        print("ERROR: half-infinite support case not supported")
      } else {
        # finite bounds
        cdf_low <- pnorm(as.numeric(as.vector(input[idx_match,"lower_limit"])), mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
        cdf_high <- pnorm(as.numeric(as.vector(input[idx_match,"upper_limit"])), mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
        p05 <- qnorm(0.05*cdf_high+(1-0.05)*cdf_low, mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
        p95 <- qnorm(0.95*cdf_high+(1-0.95)*cdf_low, mean=input[idx_match,"mean"], sd=(0.5*input[idx_match,"two_sigma"]))
      }
    }
  } else if (input[idx_match,"distribution_type"] == "lognormal") {
    if (is.infinite(input[idx_match,"upper_limit"])) {
      # only case is deltaT2X
      # lower bound some number alpha, upper bound infinity, so pdf is pdf/(1-cdf(alpha))
      cdf <- plnorm(as.numeric(as.vector(input[idx_match,"lower_limit"])), meanlog=log(input[idx_match,"mean"]), sdlog=log(0.5*input[idx_match,"two_sigma"]))
      p05 <- qlnorm(0.05+(1-0.05)*cdf, meanlog=log(input[idx_match,"mean"]), sdlog=log(0.5*input[idx_match,"two_sigma"]))
      p95 <- qlnorm(0.95+(1-0.95)*cdf, meanlog=log(input[idx_match,"mean"]), sdlog=log(0.5*input[idx_match,"two_sigma"]))
    } else {
      # --> this case doesn't happen, but put an error message here just in case
      print("ERROR: finite upper bound log-normal case not supported")
    }
  } else {print("ERROR: unknown distribution type")}
  som_parameters_table[pp,c("prior 5th percentile", "prior 95th percentile")] <- round(c(p05,p95), 4)
  # posteriors
  som_parameters_table[pp,c("posterior median", "posterior 5th percentile", "posterior 95th percentile")] <- round(par_quantiles$`30`$ct[pp,c("0.5","0.05","0.95")],4)
}
# write to CSV
write.csv(x=som_parameters_table, file="../output/som_parameters_table.csv")

## %outbound percentages below different thresholds, to measure
## marginal value of information

print(paste("Temp-only for CO2:",round(length(which(prcout$`30`$t[,"co2"] < 0.25))/num_samples,4), "of samples below 25%outbound"))
print(paste("Temp+CO2 for CO2:",round(length(which(prcout$`30`$ct[,"co2"] < 0.25))/num_samples,4), "of samples below 25%outbound"))

print(paste("CO2-only for temp:",round(length(which(prcout$`30`$c[,"temp"] < 0.25))/num_samples,4), "of samples below 25%outbound"))
print(paste("Temp+CO2 for temp:",round(length(which(prcout$`30`$ct[,"temp"] < 0.25))/num_samples,4), "of samples below 25%outbound"))


##==============================================================================



##==============================================================================
##
## what variables are correlated to temperature at age = 100 Myr (or thereabouts)
##

age_of_interest <- seq(90,140,by=10)
idx_of_interest <- match(age_of_interest, time)
bb <- "50"
dd <- "c"
temp_of_interest <- apply(model_hindcast[[bb]][[dd]]$temp[idx_of_interest,], MARGIN=2, FUN=mean)

## correlations with the constant parameters
mat <- cbind(par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]],], temp_of_interest)
cor_spearman <- cor_pearson <- rep(NA, length(parnames_calib))
for (pp in 1:length(parnames_calib)) {
    cor_spearman[pp] <- cor(mat[,pp], temp_of_interest,  method = "spearman")
    cor_pearson[pp] <- cor(mat[,pp], temp_of_interest,  method = "pearson")
}
cor_mat <- cbind(1:57, cor_spearman, cor_pearson)

# only printing the correlations >= 0.10
# ... yeah, "high correlation" in the variable name is pretty generous maybe
#  but should catch anything we would want to look at more closely...
idx_high_corr <- which( (abs(cor_spearman) >= 0.10) | (abs(cor_pearson) >= 0.10) )
print(cor_mat[idx_high_corr[rev(order(abs(cor_spearman[idx_high_corr])))],])
print(parnames_calib[idx_high_corr[rev(order(abs(cor_spearman[idx_high_corr])))]])


## correlations with the time series parameters
bb <- "50"
dd <- "c"
mat_time <- t(par_time[[bb]][[dd]][,,1])
for (pp in 2:n_parameters_time) {
  mat_time <- cbind(mat_time, t(par_time[[bb]][[dd]][,,pp]))
}
cor_spearman_time <- cor_pearson_time <- rep(NA, n_parameters_time*n_time)
for (pp in 1:(n_parameters_time*n_time)) {
    cor_spearman_time[pp] <- cor(mat_time[,pp], temp_of_interest,  method = "spearman")
    cor_pearson_time[pp] <- cor(mat_time[,pp], temp_of_interest,  method = "pearson")
}
cor_mat_time <- cbind(1:(n_parameters_time*n_time), cor_spearman_time, cor_pearson_time)

# only printing the 10 highest correlations of them
tmp <- cor_mat_time[rev(order(abs(cor_spearman_time))),]
print(tmp[1:10,])

## find none of the time series quantities correlated with high temperatures
## with pearson or spearman corr higher than about 0.03-0.04

##==============================================================================



##==============================================================================
##
## what variables are correlated to deltaT2X?
##

bb <- "30"
dd <- "ct"

## correlations with the constant parameters
deltaT2X <- par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]], match("deltaT2X",parnames_calib)]
mat <- par_calib[[bb]][[dd]][idx_sample[[bb]][[dd]],]
cor_spearman <- cor_pearson <- rep(NA, length(parnames_calib))
for (pp in 1:length(parnames_calib)) {
    cor_spearman[pp] <- cor(mat[,pp], deltaT2X,  method = "spearman")
    cor_pearson[pp] <- cor(mat[,pp], deltaT2X,  method = "pearson")
}
cor_mat <- cbind(1:57, cor_spearman, cor_pearson)

# only printing the correlations >= 0.10
# ... yeah, "high correlation" in the variable name is pretty generous maybe
#  but should catch anything we would want to look at more closely...
idx_high_corr <- which( (abs(cor_spearman) >= 0.10) | (abs(cor_pearson) >= 0.10) )
print(cor_mat[idx_high_corr[rev(order(abs(cor_spearman[idx_high_corr])))],])
print(parnames_calib[idx_high_corr[rev(order(abs(cor_spearman[idx_high_corr])))]])


## correlations with the time series parameters
bb <- "30"
dd <- "ct"
mat_time <- t(par_time[[bb]][[dd]][,idx_sample[[bb]][[dd]],1])
for (pp in 2:n_parameters_time) {
  mat_time <- cbind(mat_time, t(par_time[[bb]][[dd]][,idx_sample[[bb]][[dd]],pp]))
}
cor_spearman_time <- cor_pearson_time <- rep(NA, n_parameters_time*n_time)
for (pp in 1:(n_parameters_time*n_time)) {
    cor_spearman_time[pp] <- cor(mat_time[,pp], deltaT2X,  method = "spearman")
    cor_pearson_time[pp] <- cor(mat_time[,pp], deltaT2X,  method = "pearson")
}
cor_mat_time <- cbind(1:(n_parameters_time*n_time), cor_spearman_time, cor_pearson_time)

# only printing the 10 highest correlations of them
tmp <- cor_mat_time[rev(order(abs(cor_spearman_time))),]
print(tmp[1:10,])

## find no correlations higher than about 0.05

## highest magnitude correlation is with idx = 583, which is the 3rd timestep
## of the 11th time series (fSR, seafloor spreading rate/degassing). There is no
## data at that time, so this correlation seems spurious

##==============================================================================



##==============================================================================
##
## time series parameters' autocorrelations, and uncertainties in ACF
##

bb <- "30"
dd <- "ct"
mat_time <- par_time[[bb]][[dd]][,idx_sample[[bb]][[dd]],]

lag_max <- 20
acf_time_full <- array(NA, dim = c(lag_max+1, num_samples, n_parameters_time))
acf_time_quantiles <- array(NA, dim=c(lag_max+1, length(quantiles_i_want), n_parameters_time))

for (pp in 1:n_parameters_time) {
  for (ii in 1:num_samples) {
    acf_time_full[,ii,pp] <- acf(mat_time[, ii, pp], plot=FALSE, lag.max=lag_max)$acf
  }
  # get quantiles
  for (ll in 1:(lag_max+1)) {
    acf_time_quantiles[ll,,pp] <- quantile(acf_time_full[ll,,pp], quantiles_i_want)
  }
}

## make a plot

lags <- 0:20

plot_acf_time <- function() {
    plot(lags, acf_time_quantiles[,5,pp], type='l', lwd=1.5, xlim=c(0,lag_max), ylim=c(-0.1,1), xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n')
    polygon(c(lags,rev(lags)), c(acf_time_quantiles[,match("0.025", quantiles_i_want),pp], rev(acf_time_quantiles[,match("0.975", quantiles_i_want),pp])), col=rgb(.5,.5,.5,.5), border=1, lty=1)
    lines(c(0,lag_max),c(0,0), lty=5)
    grid()
    mtext('Lag [# time steps]', side=1, line=2.5)
    mtext('ACF', side=2, line=2.8)
    axis(1, at=0:lag_max, labels=rep("",length=(lag_max+1)))
    axis(1, at=c(1,5,10,15,20))
    axis(2, at=seq(-0.1,1,by=0.1), las=1)
    #text(0.25*lag_max, 0.8, parnames_time[pp], cex=1.1)
    mtext(side=3, text=time_series_labels[pp], line=0, cex=1, adj=0)
    mtext(side=3, text=parnames_time[pp], line=0, cex=1, adj=0.5)
}

pdf('../figures/time_series_autocorrelations.pdf',width=6,height=8,colormodel='cmyk', pointsize=11)
par(mfrow=c(4,3), mai=c(0.45,.65,.25,.15))
for (pp in 1:n_parameters_time) {
    plot_acf_time()
}
dev.off()

##==============================================================================



##==============================================================================
##
## CO2 windows and proxy data points
##

# don't want to plot proxy windows for time periods without data
idx_no_data <- which(windows$co2[,"low"]==0 | windows$co2[,"high"]==50000)
idx_data <- setdiff(1:n_time, idx_no_data)
ifirst <- idx_data[1]
idx_data <- c(ifirst-1, idx_data) # start time series 1 earlier for continuity in the figure

pdf('../figures/co2_windows_and_proxies.pdf',width=4,height=3,colormodel='cmyk', pointsize=11)

par(mfrow=c(1,1), mai=c(0.6,.9,.18,.15))
plot(-data_calib$age, log10(data_calib$co2), pch='x', cex=0.65, xlim=c(-425,0), ylim=c(-0.3,log10(40000)), xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n')
grid()
polygon(-c(time[idx_data],rev(time[idx_data])), log10(c(windows$co2[idx_data,"high"],rev(windows$co2[idx_data,"low"]))), col=rgb(.5,.5,.5,.5), border=1, lty=1)
points(-data_calib$age, log10(data_calib$co2), pch='x', cex=0.65)
mtext('Time [Myr ago]', side=1, line=2.1)
mtext(expression('CO'[2]*' concentration [ppmv]'), side=2, line=3.5)
axis(1, at=seq(-400,0,100), labels=c('400','300','200','100','0'))
ticks=log10(c(seq(1,10,1),seq(10,100,10),seq(200,1000,100),seq(2000,10000,1000),seq(20000,100000,10000)))
axis(2, at=ticks, labels=rep('',length(ticks)))
axis(2, at=log10(c(1,10,100,1000,10000)), labels=c('1','10','100','1000','10000'), las=1)
#axis(2, at=log10(c(3,10,30,100,300,1000,3000,10000)), labels=c('3','10','30','100','300','1000','3000','10000'), las=1)
legend(-420, 0.4, c('Fitted precalibration windows','Data points from Foster et al [2017]'), pch=c(15,4), col=c(rgb(.5,.5,.5,.5),'black'), pt.cex=1.2, cex=.6, bty='n', y.intersp=1)

dev.off()

##==============================================================================



##==============================================================================
##
## CO2 concentration vs uncertainty range
##

pdf('../figures/co2_and_uncertainties.pdf',width=4,height=3.8,colormodel='cmyk', pointsize=11)
par(mfrow=c(1,1), mai=c(0.7,.9,.25,.25))
plot(data_calib$co2, data_calib$co2_high-data_calib$co2_low, pch=16, cex=0.65, xlim=c(0,4000), ylim=c(0,6000), xlab='', ylab='', xaxs='i', yaxs='i')
grid()
mtext(expression('CO'[2]*' concentration [ppmv]'), side=1, line=2.5)
mtext(expression('width of +/-1'*sigma*' CO'[2]*' range [ppmv]'), side=2, line=2.5)
dev.off()

##==============================================================================


## now, run the supplemental/sensitivity experiment analysis

source("analysis_supplemental_experiments.R")


##==============================================================================
##
## supp figure for deltaT2X distributions, extended to include the glacial
## periods and the sensitivity experiment
##

# experiment you want
bb <- "30"  # to match the sensitivity experiment
dd <- "ct"

# density of deltaT2X from this work
parnames_calib <- colnames(par_calib[[bb]][[dd]])
ics <- match('deltaT2X', parnames_calib)
deltaT2X_density <- density(par_calib[[bb]][[dd]][,ics], from=0, to=10)

iglac <- match('GLAC', parnames_calib)
glac_density <- density(par_calib[[bb]][[dd]][,iglac], from=1, to=5)

icsg <- match('deltaT2Xglac', parnames_calib)
deltaT2Xglac_density <- density(par_calib[[bb]][[dd]][,icsg], from=0, to=25)

# get the densities for the cretaceous experiments
# yields: pdf_cret and pdf_cret_glac
load("../output/pdf_cret.RData")

offset <- 0.08


pdf('../figures/deltaT2X_distributions_withGlac.pdf',width=6,height=4, colormodel='cmyk', pointsize=11)
par(mfrow=c(1,1), mai=c(.7,.3,.13,.15))
plot(deltaT2X_density$x, deltaT2X_density$y + offset, type='l', lwd=1.7, xlim=c(0.8,15), ylim=c(0,.82+offset),
     xlab='', ylab='', xaxs='i', yaxs='i', xaxt='n', yaxt='n', axes=FALSE, col='steelblue')
lines(pdf_cret$x, pdf_cret$y + offset, lwd=1.7, lty=5, col='seagreen3')
lines(c(10,20), c(offset,offset), lty=1, lwd=1.7)
lines(deltaT2Xglac_density$x, offset+deltaT2Xglac_density$y, lwd=1.7, lty=4, col='salmon3')
lines(pdf_cret_glac$x, pdf_cret_glac$y + offset, lwd=1.7, lty=4, col='seagreen3')
mtext(expression(Delta*"T"['2x']*" ("*degree*"C)"), side=1, line=2.3)
mtext('Density', side=2, line=0.3)
arrows(1, 0, 1, .72+offset, length=0.08, angle=30, code=2)
axis(1, at=seq(0,20,1), labels=rep('',21), col='gray')
axis(1, at=seq(0,20,5), labels=c('0','5','10','15','20'), cex.axis=1)
y0 <- 0.2*offset; arrows(x_5_95_thisstudy[1], y0, x_5_95_thisstudy[3], y0, length=0.05, angle=90, code=3, lwd=1.5, col='steelblue'); points(x_5_95_thisstudy[2], y0, pch=16, col='steelblue')
y3 <- 0.8*offset; arrows(x_5_95_glac[1], y3, x_5_95_glac[3], y3, length=0.05, angle=90, code=3, lwd=1.5, lty=4, col='salmon3'); points(x_5_95_glac[2], y3, pch=1, col='salmon3')
y2 <- 0.5*offset; arrows(x_ktc2017[1], y2, x_ktc2017[3], y2, length=0.05, angle=90, lwd=1.5, code=3); points(x_ktc2017[2], y2, pch=17)
legend(5.6,0.82, c('5-95% range, Krissansen-Totton & Catling (2017)','5-95% range, this study',
                   '5-95% range (glacial), this study', 'Posterior, this study','Posterior (Cretaceous-matching), this study',
                   'Posterior (glacial), this study', 'Posterior (glacial, Cretaceous-matching), this study'), pch=c(17,16,1,NA,NA,NA,NA), lty=c(1,1,3,1,5,4,4), cex=.9, bty='n', lwd=1.5,
       col=c('black','steelblue','salmon3','steelblue','seagreen3','salmon3','seagreen3'))
dev.off()

##==============================================================================



##==============================================================================
## GYM experiment modification
##============================

ii <- 1
idx_life <- match("LIFE",parnames_calib); idx_gym <- match("GYM",parnames_calib)
GYM <- 0.875; LIFE <- 0.25
#GYM <- par_calib$`30`$ct[ii,idx_gym]; LIFE <- par_calib$`30`$ct[ii,idx_life]

ages_gym <- c(570 , 380 , 350, 130, 80, 0)
fE <-       c(LIFE, LIFE, GYM, GYM, 1 , 1)
ages_gym_mod <- c(570 , 380 , 350, 110, 110     , 60, 60, 0)
fE_mod <-       c(LIFE, LIFE, GYM, GYM, 0.25*GYM,  1,  1, 1)

pdf('../figures/gym_modification.pdf',width=4,height=3, colormodel='cmyk', pointsize=11)
par(mfrow=c(1,1), mai=c(.7,.8,.13,.15))
plot(-ages_gym, fE, type='l', xlim=c(-570, 0), ylim=c(0,1.1), xaxt='n', yaxt='n', xlab='', ylab='', xaxs='i', yaxs='i')
grid()
lines(-ages_gym_mod, fE_mod, col="firebrick", lty=5)
lines(-ages_gym, fE, col="black", lty=1)
axis(1, at=seq(-500,0,100), labels=c(500,400,300,200,100,0))
axis(2, at=seq(from=0, to=1, by=0.25), labels=c("0","0.25","0.5","0.75","1"), las=1)
mtext("Age [Myr ago]", side=1, line=2.4)
mtext("fE [unitless]", side=2, line=3)
legend(-570,1.12, c('Original default values', '0.25*GYM+timing'), lty=c(1,5),
       cex=.9, bty='n', lwd=1.5, col=c('black','firebrick'))
dev.off()

##==============================================================================



##==============================================================================
## End
##==============================================================================

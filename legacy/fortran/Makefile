# Define "all"
all: run_geocarb.so run_geocarb_supp.so

# Fortran compiler:
F90 = /usr/local/bin/gfortran
#F90 = /usr/bin/gfortran

# Directories: objpath, srcpath
OP = ./obj
SP = ./src

# Compiler flags:
Optimization = -O3
SOFlags = -fPIC
#Modpath = -module $(OP)
#Flags = ${SOFlags} ${Optimization} -fno-range-check #$(Modpath)
Flags = ${SOFlags} -fno-range-check #$(Modpath)

# Preprocessor options:
#CPP = cpp
#CPPFLAGS = -DMOC_NOISE

# ==============================================================
## The main programs/subroutines ##
# ==============================================================

run_geocarb.so: $(OP)/run_geocarb.o
	$(F90) -o $@ $(Flags) -shared $(Incl) $^

run_geocarb_supp.so: $(OP)/run_geocarb_supp.o
	$(F90) -o $@ $(Flags) -shared $(Incl) $^

# ==============================================================
## Main Object files ##
# ==============================================================

## GEOCARB ##
$(OP)/run_geocarb.o: $(SP)/run_geocarb.f90
	$(F90) -c $(Flags) $(Incl) $(SP)/run_geocarb.f90 -o $@

$(OP)/run_geocarb_supp.o: $(SP)/run_geocarb_supp.f90
	$(F90) -c $(Flags) $(Incl) $(SP)/run_geocarb_supp.f90 -o $@

.PHONY: clean

#Cleaning up
clean:
	rm -f $(OP)/*.o $(OP)/*.mod $(OP)/*.F90

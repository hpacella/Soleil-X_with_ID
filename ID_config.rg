import "regent"
local c = regentlib.c
local cmath = terralib.includec("math.h")

local PI = 3.1415926535898

--Terra struct that contains all necessary information about the problem setup
struct Config {


  --inputs required for interpolative decomposition
  ID_rel_tol : double,  --stopping tolerance
  subsampling_x1 : int, --spacing used for subsampling of subregions
  subsampling_x2 : int,
  subsampling_x3 : int,

  --target rank for initial ID stages (as a % of total time steps)
  rank_multiplier : double,

  --number of time step intervals that ID is applied to (as a % of total time steps)
  no_tstep_intervals : int,

  --options to reconstruct time step solutions from ID
  save_interval : int

}

terra Config:initialize()

  self.ID_rel_tol = 1e-3
  self.subsampling_x1 = 1
  self.subsampling_x2 = 1
  self.subsampling_x3 = 1

  self.rank_multiplier = 0.1

  self.no_tstep_intervals = 0.2

  self.save_interval = 1000

end
  

end


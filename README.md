# Global Ocean Simulation

Global ocean simulation with code split into modules instead of one giant file. 

> [!CAUTION]
> This modular version is untested and may not work right now

## Directory tree

```
├── LICENSE
├── LocalPreferences.toml <-- cluster preferences so MPI works
├── main.jl               <-- this sets up the entire simulation
├── Project.toml          <-- configuration file
├── README.md             <-- top level documentation
├── src/                  <-- folder with modules to build the simulation 
└── submit_mpi.sh         <-- script to submit job to slurm cluster 
```

## Running the simulation

use the `submit_mpi.sh` script to run the simulation on [Bouchet](https://docs.ycrc.yale.edu/clusters/bouchet/)

```sh
sbatch submit_mpi.sh
```
> [!NOTE]
> You may need to change some of the SLURM directives

if you are testing new features you may want to run like this: `julia --project=. ./main.jl 2>&1 | tee -a output.txt`

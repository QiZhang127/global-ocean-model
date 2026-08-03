# Global Ocean Simulation

Global ocean simulation with code split into modules instead of one giant file. 

## Getting started

1. Clone this repo
2. Make any ncessary changes you want to the simulation.
3. Augment the SLURM directives in `submit_mpi.sh`.
4. Submit the job to the queue: `sbatch submit_mpi.sh`
5. Thats it!  

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

use the `submit_mpi.sh` script to run the simulation on [Bouchet](https://docs.ycrc.yale.edu/clusters/bouchet/). I also include `submit_cpu.sh` if you want to run on a CPU. The latter is useful if you downloading data. 

```sh
sbatch submit_mpi.sh
```
> [!NOTE]
> You may need to change some of the SLURM directives

### Testing
if you are testing new features and not using a submit script, then you may want to use the following to output to the terminal and save the log to a file: 

```sh
julia --project=. ./main.jl 2>&1 | tee -a output.txt
```

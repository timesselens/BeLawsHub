#!/bin/bash
for i in `cat docuids_seed.txt`; do
	 echo "grabbing $i";
	 curl http://localhost:5001/api/internal/fetch/staatsblad.json?docuid=$i >> fetch.log
	 echo >> fetch.log
	 sleep 5
done

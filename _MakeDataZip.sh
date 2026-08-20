#!/bin/bash

set -exo

mkdir Bioinformatics_Workshop 
cp -r data Bioinformatics_Workshop/.
zip -r Bioinformatics_Workshop.zip Bioinformatics_Workshop
rm -rf Bioinformatics_Workshop
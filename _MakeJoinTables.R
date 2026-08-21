#!/usr/bin/env Rscript

# Creates the small toy tables used to illustrate the dplyr join functions in
# session 6. These are deliberately tiny so that every row of every join can be
# inspected by eye.

library(tidyverse)

# animals found in Ugandan national parks
animals <- tibble(
    animal = c("lion", "elephant", "crocodile"),
    park   = c("Kidepo Valley", "Murchison Falls", "Murchison Falls")
)

# what each animal eats - note this table covers a different set of animals
animal_diets <- tibble(
    animal = c("elephant", "crocodile", "hippo"),
    eats   = c("plants", "meat", "plants")
)

# a version of animal_diets in which the column used for joining has a
# different name, used to illustrate join_by(animal == species)
animal_diets2 <- rename(animal_diets, species = animal)

# versions of the two tables in which the animals are identified by their
# scientific name, i.e. by a genus and a species, used to illustrate joining on
# more than one column. The lion and the leopard share the genus Panthera, so
# the genus alone is not enough to identify an animal.
animal_species <- tibble(
    genus   = c("Panthera", "Loxodonta", "Crocodylus", "Panthera"),
    species = c("leo", "africana", "niloticus", "pardus"),
    park    = c("Kidepo Valley", "Murchison Falls", "Murchison Falls",
                "Kidepo Valley")
)

species_diets <- tibble(
    genus   = c("Loxodonta", "Crocodylus", "Hippopotamus", "Panthera"),
    species = c("africana", "niloticus", "amphibius", "pardus"),
    eats    = c("plants", "meat", "plants", "meat")
)

# versions of the two tables that each come from a different survey and so each
# carry their own survey_year column, used to illustrate what happens when the
# two tables share a column that isn't being used for joining
animal_survey <- animals |>
    mutate(survey_year = c(2019, 2021, 2021))

diet_survey <- animal_diets |>
    mutate(survey_year = c(2020, 2020, 2018))

write_rds(animals, "data/animals.rds")
write_rds(animal_diets, "data/animal_diets.rds")
write_rds(animal_diets2, "data/animal_diets2.rds")
write_rds(animal_species, "data/animal_species.rds")
write_rds(species_diets, "data/species_diets.rds")
write_rds(animal_survey, "data/animal_survey.rds")
write_rds(diet_survey, "data/diet_survey.rds")

##################################################
## Project: FRONTIER
## Script purpose: Use the PAMES algorithm to calculate purity for samples of interest
## Date: June 14, 2018
## Author: Floris Barthel
##################################################

library(PAMES)

setwd("~/projects/FRONTIER")
load('results/FRONTIER.QC.filtered.normalized.anno.final.Rdata')

test  = getBeta(all_data)[,all_data$Dataset != "DKFZ"]
train = getBeta(all_data)[,all_data$Dataset == "DKFZ"]

auc_data = compute_AUC(test, train)
sites_data = select_informative_islands(test, auc_data, max_sites = 20)
purity = compute_purity(test, sites_data)

write.csv(data.frame(Sentrix_Accession = names(purity), purity = purity, stringsAsFactors = F, row.names = NULL), file = 'results/purity/PAMES.purity.csv', row.names = F)
plot(density(purity))

###

test  = getBeta(all_data)[,all_data$Dataset != "DKFZ"]
idx = which(all_data$Sample_Type == "Cortex" | all_data$Sample_Type == "Granulation")
train = getBeta(all_data)[,idx]

auc_data = compute_AUC(test, train)
sites_data = select_informative_islands(test, auc_data, max_sites = 20)
purity = compute_purity(test, sites_data)

write.csv(data.frame(Sentrix_Accession = names(purity), purity = purity, stringsAsFactors = F, row.names = NULL), file = 'results/purity/PAMES.cortex_granulation.csv', row.names = F)
plot(density(purity))

###

test  = getBeta(all_data)[,all_data$Dataset != "DKFZ"]
idx = which(all_data$Sample_Type == "Cortex")
train = getBeta(all_data)[,idx]

auc_data = compute_AUC(test, train)
sites_data = select_informative_islands(test, auc_data, max_sites = 20)
purity = compute_purity(test, sites_data)

write.csv(data.frame(Sentrix_Accession = names(purity), purity = purity, stringsAsFactors = F, row.names = NULL), file = 'results/purity/PAMES.DKFZ_cortex.csv', row.names = F)
plot(density(purity))
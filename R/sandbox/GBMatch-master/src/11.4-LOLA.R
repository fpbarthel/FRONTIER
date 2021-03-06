library(project.init)
library(pheatmap)
project.init2("GBMatch")

preProcessing <- "RAW_5"
use.tiles <- TRUE
equalize.hits <- FALSE
qCutoff <- 0.05


out1 = paste0('11.3-DiffMeth_groups/',preProcessing, "/")
stopifnot(dir.exists(dirout(out1)))
out <- paste0(out1, "LOLA_SMALL/")
if(use.tiles){
  out <- paste0(out1, "LOLA_SMALL_TILES/")
}
if(equalize.hits){
  if(use.tiles){
    out <- paste0(out1, "LOLA_SMALL_TILES_EQUALIZED/")
  } else {
    out <- paste0(out1, "LOLA_SMALL_EQUALIZED/")    
  }
}
dir.create(dirout(out))


# DATA --------------------------------------------------------------------
load(dirout(out1, "Matrix.RData"))


# TILES -------------------------------------------------------------------
tiles <- fread(paste0(Sys.getenv("RESOURCES"), "regions/genome_tiles/tiles1000.hg38.bed"))
colnames(tiles)[1:3] <- c("chr", "start", "end")
LOLA_tiles <- as(tiles, "GRanges")
# Function to map this:
cpgs.to.tiles <- function(gr, minHits){
  return(unique(as(tiles[data.table(data.frame(findOverlaps(gr, LOLA_tiles)))[,.N, by="subjectHits"][N >= minHits]$subjectHits], "GRanges")))
}

# FILTER REPEATS ----------------------------------------------------------
res <- fread(dirout(out1,"Pvalues.tsv"))

# LONG DT -----------------------------------------------------------------
resLONG <- melt(res, id.vars="cpg")
resLONG$qval <- p.adjust(abs(resLONG$value), method="BH") * sign(resLONG$value)
pDat <- resLONG[abs(qval) < qCutoff][,.N, by="variable"]
pDat$variable <- factor(as.character(pDat$variable), levels=sort(as.character(pDat$variable)))
tail(sort(table(substr(resLONG[variable == "subgroup_Mesenchymal_Classical" & qval > -qCutoff & qval < 0]$cpg, 0, 12))))
resLONG[variable == "subgroup_Mesenchymal_Classical"][qval > -qCutoff & qval < 0][grepl("chr20_262082", cpg)]


# PLOT A HIT --------------------------------------------------------------
factorOfInterest <- "WHO2016_classification"
plotHits <- resLONG[abs(qval) < qCutoff][order(abs(qval))][grepl(gsub("_","",factorOfInterest), variable)]
annotation=fread(paste0(dirout(),"01.1-combined_annotation/","annotation_combined_final.tsv"))
aDat <- annotation[!is.na(get(factorOfInterest)),c(factorOfInterest, "N_number_seq"), with=F]
if(factorOfInterest == "sub_group"){
  aDat <- annotation[!is.na(get(factorOfInterest))][sub_group_prob >= 0.8][,c(factorOfInterest, "N_number_seq"), with=F]
}
for(i in c(1:3, (nrow(plotHits)-3):nrow(plotHits))){
  mDat2 <- data.table(N_number_seq = colnames(meth_data_mat), val=meth_data_mat[paste0(plotHits[i]$cpg, "_"),])
  pDat <- merge(aDat, mDat2)
  ggplot(pDat, aes_string(x=factorOfInterest, y="val")) + geom_boxplot() + geom_jitter() +
      ggtitle(paste(
      plotHits[i]$variable, 
      "\n", plotHits[i]$cpg, "qval =",round(plotHits[i]$qval, 3)
      ))
  ggsave(dirout(out, "Example", i,".pdf"))
}


# Convert to granges --------------------------------------------------------------------
regions <- data.table(do.call(rbind, strsplit(res$cpg, "_")))
regions$V2 <- as.numeric(regions$V2)
regions[,V3 := V2]
colnames(regions) <- c("chr", "start", "end")
gregions <- as(regions, "GRanges")
userSets <- list()
for(col in colnames(res)){
  if(col != "cpg"){
    ss <- strsplit(col, "_")[[1]]
    
    p <- resLONG[variable == col][match(res$cpg, resLONG$cpg)]$qval
    cutoff.up <- qCutoff
    cutoff.down <- -qCutoff
    
    if(equalize.hits){
      min.hits <- min(sum(p < qCutoff & p > 0, na.rm=T), sum(p > -qCutoff & p < 0, na.rm=T))
      cutoff.up <- sort(p[!is.na(p) & p > 0])[min.hits]
      cutoff.down <- sort(p[!is.na(p) & p < 0], decreasing=TRUE)[min.hits]
    }
    bg.gr = gregions[!is.na(p) & (p < cutoff.up & p > cutoff.down)]
    
    userSets[[col]] <- list(
      query = gregions[!is.na(p) & (p < cutoff.up & p > 0)],
      bg = bg.gr)
    userSets[[paste(ss[1], ss[3],ss[2], sep="_")]] <- list(
      query = gregions[!is.na(p) & (p > cutoff.down & p < 0)],
      bg = bg.gr)
  }
}
userSets <- userSets[sapply(userSets, function(x) length(x$query) > 0)]

# Plot how many hits we have
ggplot(data.table(melt(sapply(lapply(userSets, function(x)x$query), length)), keep.rownames=TRUE), 
       aes(y=value, x=rn)) + 
  geom_bar(stat="identity") + coord_flip()+theme_bw(24)
ggsave(dirout(out, "Hit_counts_beforeTiles.pdf"), height=20, width=15)

# To tiles
if(use.tiles){
  for(userSet.x in names(userSets)){
    list.x <- userSets[[userSet.x]]
    userSets[[userSet.x]] <- list(
      query = cpgs.to.tiles(list.x$query, 1),
      bg = cpgs.to.tiles(list.x$bg, 1)
    )
  }
}
  
# Plot how many hits we have
ggplot(data.table(melt(sapply(lapply(userSets, function(x)x$query), length)), keep.rownames=TRUE), 
       aes(y=value, x=rn)) + 
  geom_bar(stat="identity") + coord_flip()+theme_bw(24)
ggsave(dirout(out, "Hit_counts_afterTiles.pdf"), height=20, width=15)

library(LOLA)

# LOLA --------------------------------------------------------------------
if(!file.exists(dirout(out, "LOLA_FULL.tsv"))){
  LOLA_regionDB = loadRegionDB(paste0(Sys.getenv("RESOURCES"), "/regions/LOLACore/hg38/"))
  cellType_conversions=fread(file.path(getOption("PROJECT.DIR"),"metadata/LOLA_annot/CellTypes.tsv"),drop="collection")
  resLOLA <- data.table()
  xnam <- names(userSets)[1]
  for(xnam in names(userSets)){
    tryCatch({
      res.x <- runLOLA(userSets=userSets[[xnam]]$query, userUniverse=userSets[[xnam]]$bg, regionDB=LOLA_regionDB)
      res.x$userSet <- rep(xnam, nrow(res.x))
      resLOLA <- rbind(resLOLA, res.x)
    }, error = function(e){
      print(paste(xnam, ":", e))
    })
  }
  
  # SIGNFICANCE ------------------------------------------------------------
  collections=c("codex","encode_tfbs")
  resLOLA[,BY:=p.adjust(exp(-pValueLog),method="BY")]
  resLOLA[,BH:=p.adjust(exp(-pValueLog),method="BH")]
  
  # How many results?
  resLOLA[BH < qCutoff][, .N , by="userSet"]
  resLOLA[BY < qCutoff][, .N , by="userSet"]
  resLOLA[collection%in%collections & BH < qCutoff][, .N , by="userSet"]
  resLOLA[collection%in%collections & BY < qCutoff][, .N , by="userSet"]
  
  # GET RESULTS -------------------------------------------------------------
  resLOLA[,mlog10p.adjust:=-log10(BY),]
  resLOLA[cellType==""|is.na(cellType),cellType:="Not defined",]
  resLOLA=merge(resLOLA,cellType_conversions,by="cellType",all=TRUE)
  resLOLA[is.na(cellType_corr),cellType_corr:="Not defined"]
  resLOLA=resLOLA[!is.na(userSet)]
  resLOLA[,target:=toupper(sub("-","",unlist(lapply(antibody,function(x){spl=unlist(strsplit(x,"_|eGFP-"));spl[spl!=""][1]})))),]
  
  # SAFE FULL TABLE
  write.table(resLOLA, file=dirout(out, "LOLA_FULL.tsv"), sep="\t", quote=F, row.names=F)
  write.table(resLOLA[BY < qCutoff], file=dirout(out, "LOLA_HITS.tsv"), sep="\t", quote=F, row.names=F)
}
resLOLA <- fread(dirout(out, "LOLA_FULL.tsv"))

resLOLA <- resLOLA[cellType_corr %in% c("Astrocyte", "ESC")]
resLOLA[,BY:=p.adjust(exp(-pValueLog),method="BY")]
write.table(resLOLA[BY < qCutoff], file=dirout(out, "LOLA_HITS_AstroOrESC.tsv"), sep="\t", quote=F, row.names=F)

# MAKE PLOTS OF HITS
# LOLA HEATMAP -----------------------------------------------------------------
pDat1 <- dcast.data.table(resLOLA[!is.na(target)], target ~ userSet, fun.aggregate=max, value.var="mlog10p.adjust")
pDat2 <- as.matrix(pDat1[,-"target", with=F])
row.names(pDat2) <- pDat1$target
pDat2[pDat2 == -Inf] <- 0
pDat2[pDat2 > 10] <- 10
pDat2 <- pDat2[apply(pDat2, 1, max) > -log10(qCutoff),]
pDat2 <- pDat2[,apply(pDat2, 2, max) > -log10(qCutoff)]
if(nrow(pDat2) > 2 & ncol(pDat2) > 2){
  pdf(dirout(out, "LOLA_HM.pdf"), height=20, width=20)
  pheatmap(pDat2)
  dev.off()
}





# LOLA RESULTS IN SMALL DOTPLOT

LOLA_res=fread(dirout(out,"LOLA_HITS_AstroOrESC.tsv"))

pdf(dirout(out, "LOLA_res_subgroup.pdf"),height=3.5,width=5)
ggplot(LOLA_res[grepl("subgroup",userSet)&collection%in%c("codex","encode_tfbs")&cellState!="Malignant"],aes(x=target,y=-log10(BY),fill=cellType_corr))+geom_point(position=position_jitter(height=0,width=0.1),shape=21,size=3,alpha=0.6,stroke=0.6)+geom_hline(yintercept=-log10(0.05),lty=20,col="grey")+theme(axis.text.x=element_text(angle = 90, hjust=1,vjust = 0.5))+facet_wrap(~userSet,ncol=1)+scale_fill_manual(values=c("Astrocyte"="#a6cee3","ESC"="#b2df8a"))+scale_color_manual(values=c("FALSE"="grey","TRUE"="black"))

dev.off()






# HIT CPGS HEATMAP ----------------------------------------------------------------

data.nas <-apply(is.na(meth_data_mat), 1, sum)
quantile(data.nas)
cpgs.keep <- which(data.nas < 100)

nsel=500
comps=c("subgroup_Mesenchymal_Proneural","subgroup_Proneural_Classical","subgroup_Mesenchymal_Classical")
cpgs=vector()
row_annots=vector()
for (comp in comps){
  sub_cpgs=res[[comp]][cpgs.keep]
  names(sub_cpgs)=paste0(res$cpg[cpgs.keep],"_")
  sel=sub_cpgs[order(abs(sub_cpgs))][1:nsel]
  sel_annot=ifelse(sel>0,paste0(comp,"_+"),paste0(comp,"_-"))
  cpgs=c(cpgs,sel)
  row_annots=c(row_annots,sel_annot)
}



# PREPARE SAMPLE ANNOTATION ------------------------------------------------------
factorOfInterest <- "sub_group"
annotation=fread(paste0(dirout(),"01.1-combined_annotation/","annotation_combined_final.tsv"))
annotation <- annotation[category == "GBMatch" & IDH == "wt"]
aDat <- annotation[!is.na(get(factorOfInterest))]
# only those samples in the top percentile
aDat=aDat[sub_group_prob>0.8&auc>0.8]


# Heatmap annotation ------------------------------------------------------
str(row_annot <- data.frame(direction=row_annots[unique(names(cpgs))]))
str(col_annot <- data.frame(
  auc = aDat[["auc"]],
  #Mesencymal = aDat[["Mesenchymal"]],
  #Proneural = aDat[["Proneural"]],
  #Classical = aDat[["Classical"]],
  sub_group = aDat[[factorOfInterest]],
  row.names = aDat$N_number_seq))
hmMT <- meth_data_mat[unique(names(cpgs)),]
hmMT <- hmMT[,aDat$N_number_seq]



# Order by group ----------------------------------------------------------
str(row_annot <- row_annot[rownames(hmMT),,drop=FALSE])
row_annot$direction=sub("subgroup_","",row_annot$direction)

# PLOT --------------------------------------------------------------------

colors=list(sub_group=c("Mesenchymal"="#00BA38","Classical"="#F8766D","Proneural"="#619CFF"),direction=c("Mesenchymal_Classical_-"="#fb9a99","Mesenchymal_Classical_+"="#e31a1c","Mesenchymal_Proneural_-"="#a6cee3","Mesenchymal_Proneural_+"="#1f78b4","Proneural_Classical_-"="#b2df8a","Proneural_Classical_+"="#33a02c"))


pdf(dirout(out, "subgroup_HM_Clustered.pdf"),height=5,width=6)
pheatmap(border_color=NA,hmMT[order(row_annot$direction),order(col_annot$sub_group)], show_rownames=FALSE,show_colnames=FALSE,
         annotation_col=col_annot,
         annotation_row=row_annot,
         cluster_rows=F, cluster_cols=F,
         annotation_colors=colors,
         color=colorRampPalette(c("blue","red"))(20))
dev.off()
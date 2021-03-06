library(project.init)
project.init2("GBMatch")
library(survival)
library(broom)
library("survminer")
require(bit64)

##set directories
out_dir=file.path(getOption("PROCESSED.PROJECT"),"results_analysis/13.1-survival/")
dir.create(out_dir)
setwd(out_dir)

#function binarize
binarize=function(vector,quantile){
  ret=ifelse(vector<quantile(vector,quantile,na.rm=TRUE),"low","high")
  return(as.character(ret))
}

binarize2=function(vector,low,high){
  ret=ifelse(vector<=quantile(vector,low,na.rm=TRUE),"low",ifelse(vector>=quantile(vector,high,na.rm=TRUE),"high",NA))
  return(as.character(ret))
}


##function for survival plotting
plot_surv=function(data,type="surv"){
  pl=list()
  pl2=list()
  ret=data.table()
  #function for p-value calculation
  get_pval=function (fit) 
  {
    if (length(levels(summary(fit)$strata)) == 0) 
      return(NULL)
    sdiff <- survival::survdiff(eval(fit$call$formula), data = eval(fit$call$data))
    pvalue <- stats::pchisq(sdiff$chisq, length(sdiff$n) - 1,lower.tail = FALSE)
    return(pvalue)
  }
  
  categories=grep("patID|event|follow_up",names(data),invert=TRUE,value=TRUE)
  
  for (category in categories){
    print(category)
    sub=na.omit(data[,grepl(paste0("patID|event|follow_up|",category),names(data)),with=FALSE])
    if (length(unique(unlist(sub[,category,with=FALSE])))<2){
      print("Too fiew categories!")
      next
    }
    survfit_1=survfit(Surv(time = follow_up, event = event) ~ get(category), data=sub)
    pvalue=round(get_pval(survfit_1),4)
    print(pvalue)
    
    if (type=="surv"){ylab="Survival probability"}else if (type=="rel"){ylab="Relapse-free survival probability"}
    pl[category]=ggsurvplot(fit=survfit_1,conf.int=TRUE,main=paste0(category,"\np.value=",pvalue),palette="Set2",font.main=c(10, "plain", "black"),ylab = ylab,xlab="Months")
    ret=rbindlist(list(ret,data.table(category=category,p.value=pvalue)))
    
  }
  return(list(pl,ret))
}

plot_dots=function(data){
  data_long=melt(data,id.vars=c("event", "follow_up","patID","category"))
  pl=list()
  for(sub in unique(data_long$variable)){
    if(sum(!is.na(data_long[variable==sub]$value))==0){next}
  dotplot=ggplot(data_long[variable==sub&!is.na(value)],aes(x=value,y=follow_up))+geom_point(shape=21,size=2.5,aes(fill=value),alpha=0.6,position=position_jitter(width=0.2))+geom_boxplot(fill="transparent",outlier.size=NA)+ylab("Months")+scale_fill_brewer(palette="Set2")+xlab(sub)
  pl[[sub]]=dotplot
  }
  return(pl)
}

##get annotation
annotation=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/01.1-combined_annotation/annotation_combined_final.tsv"))
load(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/01.1-combined_annotation/column_annotation_combined.RData"))

annot_ASC=annotation[IDH=="wt",list(cycles.1=enrichmentCycles[surgery==1][1],cycles.2=enrichmentCycles[surgery==2][1],Age=min(Age),Sex=unique(Sex),category="survival"),by=patID]

annot_surv=annotation[surgery%in%c(1)&IDH=="wt"&category=="GBMatch",list(event=unique(VitalStatus),follow_up=unique(`Follow-up_years`)*12,category="survival"),by=patID]
annot_surv[,event:=ifelse(event=="dead",1,0)]

annot_relapse=annotation[surgery%in%c(1,2)&IDH=="wt"&category=="GBMatch",list(event=1,follow_up=(unique(timeToFirstProg)/365)*12,category="relapse"),by=patID]

combi=rbindlist(list(annot_surv,annot_relapse),use.names=TRUE)
combi[,long_surv:=ifelse(follow_up[category=="survival"]>=36,TRUE,FALSE),by="patID"]

surv_stats=combi[,round(median(follow_up,na.rm=TRUE),2),by=category]

#survival distribution
pdf("follow_up_overview.pdf",height=4,width=4)
ggplot(combi,aes(x=category,y=follow_up))+geom_point(size=2.5,shape=21,alpha=0.6,aes(fill=long_surv),position=position_jitter(width=0.3))+geom_boxplot(outlier.size=NA,fill="transparent")+annotate(geom="text",x=1.5,y=114,label=paste0("Median survival: ",surv_stats[category=="survival"]$V1,"\n","Median time to relapse: ",surv_stats[category=="relapse"]$V1))+scale_fill_manual(values=c("FALSE"="grey","TRUE"="red"))+scale_y_continuous(breaks=seq(from=0,to=125,by=6))+xlab("")+ylab("months")
dev.off()

all_tests=data.table()

################################
##prom diff-meth stratification
################################
prom_diff=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/11.2-diffMeth_single/sel_recurring_trend_pat.tsv"))
prom_diff_enrichr_term=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/11.2-diffMeth_single/promoter_diff_meth_enrichr_term.tsv"))

prom_diff_combined=merge(prom_diff[Ngenes>0],prom_diff_enrichr_term,by="patID",all=TRUE)

prom_diff_bin=prom_diff_combined[,list(patID=patID,dist_bin=binarize2(diff_trend_dist_norm,0.2,0.8),trend_thres=ifelse(diff_trend_dist_norm<=0.7,"trend",ifelse(diff_trend_dist_norm>=1.15,"anti-trend",NA)),trend_thres_3=ifelse(diff_trend_dist_norm<=0.7,"trend",ifelse(diff_trend_dist_norm>=1.15,"anti-trend","moderate")),trend_split=ifelse(diff_trend_dist_norm<1,"trend",ifelse(diff_trend_dist_norm>=1,"anti-trend",NA)),mean_diffmeth.Development=binarize2(mean_diffmeth.Development,0.3,0.7),`mean_diffmeth.Apoptosis`=binarize2(`mean_diffmeth.Apoptosis`,0.3,0.7),`mean_diffmeth.Wnt signalling`=binarize2(`mean_diffmeth.Wnt signalling`,0.3,0.7),`mean_diffmeth.Immune response`=binarize2(`mean_diffmeth.Immune response`,0.3,0.7)),]

prom_diff_bin[,`mean_diffmeth.Wnt signalling`:=factor(`mean_diffmeth.Wnt signalling`,levels=c("low","high")),]

prom_diff_surv=merge(prom_diff_bin,annot_surv,by="patID")
prom_diff_relapse=merge(prom_diff_bin,annot_relapse,by="patID")


pdf("prom_diff_annotation_surv.pdf",height=4,width=3)
print(plot_surv(prom_diff_surv)[[1]])
dev.off()

pdf("prom_diff_annotation_surv_dp.pdf",height=4,width=3)
print(plot_dots(prom_diff_surv))
dev.off()

pdf("prom_diff_annotation_relapse.pdf",height=4,width=3)
print(plot_surv(prom_diff_relapse,type="rel")[[1]])
dev.off()

pdf("prom_diff_annotation_relapse_dp.pdf",height=4,width=3)
print(plot_dots(prom_diff_relapse))
dev.off()



################################
##methclone stratification
################################
methclone=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/06-methclone/summary_minReads60/EPM_1vs2.tsv"))
methclone=methclone[category=="GBMatch"&IDH=="wt"]
setnames(methclone,"patient","patID")

#for 1vs2
methclone[cycles.1>=16|cycles.1<=12,entropy.1:=NA,]
methclone[cycles.2>=16|cycles.2<=12,entropy.2:=NA,]
methclone[cycles.2>=16|cycles.2<=12|cycles.1>=16|cycles.1==12,mean_dentropy:=NA,]
methclone[cycles.2>=16|cycles.2<=12|cycles.1>=16|cycles.1==12,EPM:=NA,]

entropy=methclone[,list(patID=patID,entropy_1=binarize2(mean_entropy1,0.2,0.8),entropy_2=binarize2(mean_entropy2,0.2,0.8),d_entropy=binarize2(mean_dentropy,0.5,0.5),EPM= binarize2(EPM,0.5,0.5)),]

entropy_surv=merge(entropy,annot_surv,by="patID")
entropy_relapse=merge(entropy,annot_relapse,by="patID")


pdf("methclone_annotation_surv.pdf",height=3.5,width=3.0)
print(plot_surv(entropy_surv)[[1]])
dev.off()

pdf("methclone_annotation_surv_dp.pdf",height=2,width=2)
print(plot_dots(entropy_surv))
dev.off()

pdf("methclone_annotation_relapse.pdf",height=3.5,width=3.0)
print(plot_surv(entropy_relapse,type="rel")[[1]])
dev.off()

pdf("methclone_annotation_relapse_dp.pdf",height=2,width=2)
print(plot_dots(entropy_relapse))
dev.off()



########################################
#combined heterogeineity stratification
########################################
simpleCache("combined_heterogeneity",assignToVariable="combined_heterogeneity")
setnames(combined_heterogeneity,"id","N_number_seq")

het_annot=merge(combined_heterogeneity,annotation[,c("category","N_number_seq","patID","surgery","IDH","enrichmentCycles"),with=FALSE],by="N_number_seq")
het_annot=het_annot[category=="GBMatch"&surgery%in%c(1,2)&IDH=="wt"]

het_annot[enrichmentCycles>=16|enrichmentCycles<=12,mean_entropy:=NA,]
het_annot[enrichmentCycles>=16|enrichmentCycles<=12,mean_pdr:=NA,]
het_annot[enrichmentCycles>=16|enrichmentCycles<=12,enrichmentCycles:=NA,]

het_bin=het_annot[,list(patID=patID,cycles=binarize2(enrichmentCycles,0.2,0.8),mean_entropy=binarize2(mean_entropy,0.2,0.8),mean_pdr=binarize2(mean_pdr,0.2,0.8)),by="surgery"]

het_wide=reshape(het_bin,idvar=c("patID"),timevar="surgery",direction="wide")


het_surv=merge(het_wide,annot_surv,by="patID")
het_relapse=merge(het_wide,annot_relapse,by="patID")

pdf("heterogeneity_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(het_surv)[[1]])
dev.off()

pdf("heterogeneity_annotation_surv_dp.pdf",height=4,width=3)
print(plot_dots(het_surv))
dev.off()

pdf("heterogeneity_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(het_relapse,type="rel")[[1]])
dev.off()

pdf("heterogeneity_annotation_relapse_dp.pdf",height=4,width=3)
print(plot_dots(het_relapse))
dev.off()

###########################
##bissnp stratification
###########################
bissnp=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/04-bissnp/bissnp_var_pat.tsv"))
bissnp_norm=bissnp[surgery%in%c(1,2),list(patID=patID,surgery=surgery,all_count=all_count/bg_calls*1000000,H_count=H_count/bg_calls*1000000,M_count=M_count/bg_calls*1000000),]

bissnp_bin=bissnp_norm[patID%in%annotation[category=="GBMatch"&IDH=="wt"]$patID,list(patID=patID,surgery=surgery,all_count=binarize2(all_count,0.2,0.8),H_count=binarize2(H_count,0.2,0.8),M_count=binarize2(M_count,0.2,0.8)),by="surgery"]


bissnp_wide=reshape(bissnp_bin[surgery%in%c(1,2)],timevar="surgery",idvar="patID",direction="wide")
bissnp_wide[,switch:=ifelse(H_count.1==H_count.2|(is.na(H_count.1)&is.na(H_count.2)),FALSE,TRUE),]
bissnp_wide[,toHigh:=ifelse((H_count.1!="high"|is.na(H_count.1))&H_count.2=="high",TRUE,FALSE),]
bissnp_wide[,toLow:=ifelse((H_count.1!="low"|is.na(H_count.1))&H_count.2=="low",TRUE,FALSE),]



bissnp_surv=merge(bissnp_wide,annot_surv,by="patID")
bissnp_relapse=merge(bissnp_wide,annot_relapse,by="patID")

pdf("bissnp_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(bissnp_surv)[[1]])
dev.off()

pdf("bissnp_annotation_surv_dp.pdf",height=2,width=2)
print(plot_dots(bissnp_surv))
dev.off()


pdf("bissnp_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(bissnp_relapse,type="rel")[[1]])
dev.off()

pdf("bissnp_annotation_relapse_dp.pdf",height=2,width=2)
print(plot_dots(bissnp_relapse))
dev.off()


###########################
##transcriptional subtype stratification
###########################
subtypes=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/08.1-GBM_classifier/class_probs_annot_27_noNeural_predRRBS.tsv"))
subtypes=subtypes[!is.na(sub_group)]
subtypes[,sub_type_prob:=get(sub_group),by=1:nrow(subtypes)]
subtypes[,isMesenchymal:=ifelse(sub_group=="Mesenchymal",TRUE,FALSE),]
subtypes[,isClassical:=ifelse(sub_group=="Classical",TRUE,FALSE),]
subtypes[,isProneural:=ifelse(sub_group=="Proneural",TRUE,FALSE),]

subtypes_wide=reshape(subtypes[order(auc,decreasing=TRUE)][category=="GBMatch"&IDH=="wt"&surgery.x%in%c(1,2)&auc>0.8,c("surgery.x","patID","sub_group","isMesenchymal","isClassical","isProneural"),with=FALSE],timevar="surgery.x",idvar="patID",direction="wide")
subtypes_wide[,switch:=ifelse(sub_group.1==sub_group.2,FALSE,TRUE),]
subtypes_wide[,toMesenchymal:=ifelse(sub_group.1!="Mesenchymal"&sub_group.2=="Mesenchymal",TRUE,FALSE),]
subtypes_wide[,toProneural:=ifelse(sub_group.1!="Proneural"&sub_group.2=="Proneural",TRUE,FALSE),]
subtypes_wide[,toClassical:=ifelse(sub_group.1!="Classical"&sub_group.2=="Classical",TRUE,FALSE),]


subtypes_surv=merge(subtypes_wide,annot_surv,by="patID")
subtypes_relapse=merge(subtypes_wide,annot_relapse,by="patID")

pdf("subtype_annotation_surv.pdf",height=4,width=4)
print(plot_surv(subtypes_surv,type="surv")[[1]])
dev.off()

pdf("subtype_annotation_surv_dp.pdf",height=4,width=4)
print(plot_dots(subtypes_surv))
dev.off()

pdf("subtype_annotation_relapse.pdf",height=4,width=4)
print(plot_surv(subtypes_relapse,type="rel")[[1]])
dev.off()

pdf("subtype_annotation_relapse_dp.pdf",height=4,width=4)
print(plot_dots(subtypes_relapse))
dev.off()


##############################################
#stratification from copywriteR separate date
##############################################

copywriter=fread(file.path(getOption("PROCESSED.PROJECT"),"results_analysis/03-CopywriteR/results/CNAprofiles_single_100kb/summary/CNA_Chromosome.tsv"))
setnames(copywriter,"sample","N_number_seq")

copywriter=merge(copywriter,unique(annotation[,c("N_number_seq","patID"),with=FALSE]),by="N_number_seq")
copywriter=copywriter[category=="GBMatch"&IDH=="wt"&surgery%in%c(1,2)]

#now convert info about lenth of deletions/ amplifications into mere presence (1) absence (0) information
temp_patID=copywriter$patID
temp_surgery=copywriter$surgery

copywriter[,N_number_seq:=NULL,]
copywriter[,date:=NULL,]
copywriter[,surgery:=NULL,]
copywriter[,category:=NULL,]
copywriter[,IDH:=NULL,]

copywriter[copywriter!=0]=1

copywriter[,patID:=temp_patID,]
copywriter[,surgery:=temp_surgery,]


copywriter[,all_del:=binarize(as.integer(rowSums(copywriter[,grep("deletion",names(copywriter)),with=FALSE])),0.5),]
copywriter[,all_ampl:=binarize(as.integer(rowSums(copywriter[,grep("amplification",names(copywriter)),with=FALSE])),0.5),]
copywriter[,all_CNV:=binarize(as.integer(rowSums(copywriter[,grep("deletion|amplification",names(copywriter)),with=FALSE])),0.5),]

copywriter_wide=reshape(copywriter,timevar="surgery",idvar="patID",direction="wide")

copywriter_date_surv=merge(copywriter_wide,annot_surv,by="patID")
copywriter_date_relapse=merge(copywriter_wide,annot_relapse,by="patID")

#chr10q deletion overview
chr10q_del_surv=copywriter_date_surv[,list(N=.N,mean_follow_up=mean(follow_up),sd_follow_up=sd(follow_up)),by=c("10_q_deletion.1","10_q_deletion.2")]
chr10q_del_rel=copywriter_date_relapse[,list(N=.N,mean_follow_up=mean(follow_up),sd_follow_up=sd(follow_up)),by=c("10_q_deletion.1","10_q_deletion.2")]
write.table(chr10q_del_surv,"chr10q_del_surv.tsv",quote=FALSE,sep="\t",row.names=FALSE)
write.table(chr10q_del_rel,"chr10q_del_rel.tsv",quote=FALSE,sep="\t",row.names=FALSE)
mat=matrix(c(38, 33, 16, 24),nrow = 2, dimnames = list(first = c("nodel", "del"),second = c("nodel", "del")))
fisher.test(mat,alternative="two.sided")

pdf("copywriter_date_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(copywriter_date_surv)[[1]])
dev.off()

pdf("copywriter_date_annotation_surv_dp.pdf",height=4,width=3)
print(plot_dots(copywriter_date_surv))
dev.off()

pdf("copywriter_date_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(copywriter_date_relapse,type="rel")[[1]])
dev.off()

pdf("copywriter_date_annotation_relapse_dp.pdf",height=4,width=3)
print(plot_dots(copywriter_date_relapse))
dev.off()


####################################
##stratification from annotation
####################################
annotation[,ShiftPhenotype:=TumorPhenotype,]
annotation[Shape_shift=="stable",ShiftPhenotype:="stable",]
annotation[ShiftPhenotype=="other",ShiftPhenotype:=NA,]
annot_pat=annotation[,list(Bevacizumab=any(Bevacizumab!="no"),position_1=unique(position[which(surgery==1)]),border_1=unique(border[which(surgery==1)]),border_2=unique(border[which(surgery==2)]),contrast_1=unique(contrast[which(surgery==1)]),contrast_2=unique(contrast[which(surgery==2)]),age=min(age),sex=unique(sex),StuppComplete=unique(StuppComplete),center=unique(Center),vasc_fibrosis=unique(`Vascular fibrosis`[which(surgery==2)]),pseudopal_necrosis=unique(`Pseudopalisading necrosis`[which(surgery==2)]),rad_necrosis=unique(`Radiation necrosis`[which(surgery==2)]),ShiftPhenotype=ShiftPhenotype[surgery==1],Shape_shift=Shape_shift[surgery==1],Shape_shift_type=Shape_shift_type[surgery==1],TumorPhenotype=TumorPhenotype[surgery==1]),by=patID]

annot_pat[,NoStupp:=ifelse(StuppComplete=="not applicable/other treatment",1,0),]
annot_pat[,StuppComplete:=ifelse(StuppComplete=="yes",1,0),]
annot_pat[,age:=ifelse(age<50,"young","old"),]
annot_pat[,contrast_1:=gsub("mixed solid.*","solid",contrast_1),]
annot_pat[,contrast_1:=gsub("mixed necrotic.*","necrotic",contrast_1),]
annot_pat[,contrast_2:=gsub("mixed solid.*","solid",contrast_2),]
annot_pat[,contrast_2:=gsub("mixed necrotic.*","necrotic",contrast_2),]
annot_pat[,vasc_fibrosis_red:=ifelse(vasc_fibrosis=="Abundant","Present",vasc_fibrosis),]


annot_pat_surv=merge(annot_pat,annot_surv,by="patID")
annot_pat_relapse=merge(annot_pat,annot_relapse,by="patID")

pdf("general_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_surv)[[1]])
dev.off()

pdf("general_annotation_surv_dp.pdf",height=4,width=4)
print(plot_dots(annot_pat_surv))
dev.off()

pdf("general_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_relapse,type="rel")[[1]])
dev.off()

pdf("general_annotation_relapse_dp.pdf",height=4,width=4)
print(plot_dots(annot_pat_relapse))
dev.off()

##############################################
##stratification from annotation segmentation
##############################################
segmentation_cols=column_annotation_combined_clean$histo_segmentation[]
segmentation_cols=segmentation_cols[segmentation_cols!="FileName"]


sub=melt(annotation[surgery%in%c(1,2)&category=="GBMatch"&IDH=="wt",c(segmentation_cols,"patID","surgery"),with=FALSE],id.vars=c("patID","surgery"),)
sub[,category:=binarize(value,0.5),by=c("surgery","variable")]
sub[,variable:=gsub("|-|/|\\+|\\[|\\|\\]|#|\xb2","",variable),]
sub=unique(sub)


annot_pat=reshape(sub,idvar=c("patID","surgery"),timevar="variable",direction="wide",drop="value")
annot_pat=reshape(annot_pat,idvar="patID",timevar="surgery",direction="wide")
setnames(annot_pat,names(annot_pat),gsub("category.","",names(annot_pat)))


annot_pat_surv=merge(annot_pat,annot_surv,by="patID")
annot_pat_relapse=merge(annot_pat,annot_relapse,by="patID")

pdf("segmentation_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_surv)[[1]])
dev.off()

pdf("segmentation_annotation_surv_dp.pdf",height=4,width=3)
print(plot_dots(annot_pat_surv))
dev.off()


pdf("segmentation_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_relapse,type="rel")[[1]])
dev.off()

pdf("segmentation_annotation_relapse_dp.pdf",height=4,width=3)
print(plot_dots(annot_pat_relapse))
dev.off()

#######################################
##MGMT priomoter meth stratification###
#######################################

mgmt_cols=column_annotation_combined_clean$mgmt_status
mgmt_cols=mgmt_cols[!mgmt_cols%in%c("mgmt_methyl","meth_max","meth_min" , "mgmt_readCount", "mgmt_CpGcount")]

sub=annotation[surgery%in%c(1,2)&category=="GBMatch"&IDH=="wt"&!is.na(mgmt_conf4),c(mgmt_cols,"patID","surgery"),with=FALSE]
sub=unique(sub)

annot_pat=reshape(sub,idvar="patID",timevar="surgery",direction="wide")

annot_pat_surv=merge(annot_pat,annot_surv,by="patID")
annot_pat_relapse=merge(annot_pat,annot_relapse,by="patID")

pdf("mgmt_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_surv)[[1]])
dev.off()

pdf("mgmt_annotation_surv_dp.pdf",height=4,width=3)
print(plot_dots(annot_pat_surv))
dev.off()


pdf("mgmt_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_relapse,type="rel")[[1]])
dev.off()

pdf("mgmt_annotation_relapse_dp.pdf",height=4,width=3)
print(plot_dots(annot_pat_relapse))
dev.off()

##############################################
##stratification from annotation immune cells
##############################################
histo_cols=c("CD163","CD3","CD34","CD45ro","CD68","CD8","CD80","FOXP3","Galectin","HLA-DR","MIB","PD1","Tim3","cell")

sub=melt(annotation[surgery%in%c(1,2)&category=="GBMatch"&IDH=="wt",c(histo_cols,"patID","surgery"),with=FALSE],id.vars=c("patID","surgery"),)
sub[,category:=binarize(value,0.5),by=c("surgery","variable")]

annot_pat=reshape(sub,idvar=c("patID","surgery"),timevar="variable",direction="wide",drop="value")
annot_pat=reshape(annot_pat,idvar="patID",timevar="surgery",direction="wide")
setnames(annot_pat,names(annot_pat),gsub("category.","",names(annot_pat)))


annot_pat_surv=merge(annot_pat,annot_surv,by="patID")
annot_pat_relapse=merge(annot_pat,annot_relapse,by="patID")

pdf("immune_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_surv)[[1]])
dev.off()

pdf("immune_annotation_surv_dp.pdf",height=4,width=3)
print(plot_dots(annot_pat_surv))
dev.off()

pdf("immune_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_relapse,type="rel")[[1]])
dev.off()

pdf("immune_annotation_relapse_dp.pdf",height=4,width=3)
print(plot_dots(annot_pat_relapse))
dev.off()

##############################################
##stratification from annotation immaging
##############################################
annotation[,progression_types:=ifelse(`T2 diffus`==1,"T2 diffus",ifelse(`classic T1`==1,"classic T1",ifelse(`cT1 flare up`==1,"cT1 flare up",ifelse(`T2 circumscribed`==1,"T2 circumscribed",NA)))),]

img_cols=c("location","position","border","contrast","Numberoflesions","Siteofsurgery","Side","Extentofresection","classic T1","cT1 flare up","T2 diffus","T2 circumscribed","primary nonresponder","progression_types")
img_cols_cont=c("Necrotic  (mm3)","Edema  (mm3)","Non Enhancing (mm3)","Enhancing (mm3)","Total (mm3)","Proportion Necrotic (%)","VASARI F7","Proportion Edema (%)","VASARI F14","Proportion Non Enhancing (%)","VASARI F5","Proportion Enhancing (%)","VASARI F6")

sub=melt(annotation[surgery%in%c(1,2)&category=="GBMatch"&IDH=="wt",c(img_cols,"patID","surgery"),with=FALSE],id.vars=c("patID","surgery"),)
setnames(sub,"value","category")

sub_cont=melt(annotation[surgery%in%c(1,2)&category=="GBMatch"&IDH=="wt",c(img_cols_cont,"patID","surgery"),with=FALSE],id.vars=c("patID","surgery"),)
sub_cont[,category:=binarize(value,0.5),by=c("surgery","variable")]

sub=rbindlist(list(sub,sub_cont),use.names=TRUE,fill=TRUE)
sub[,variable:=gsub("|-|/|\\+|\\[|\\|\\]|#|\\(|\\)|%","",variable),]
sub=unique(sub)

annot_pat=reshape(sub,idvar=c("patID","surgery"),timevar="variable",direction="wide",drop="value")
annot_pat=reshape(annot_pat,idvar="patID",timevar="surgery",direction="wide")
setnames(annot_pat,names(annot_pat),gsub("category.","",names(annot_pat)))


annot_pat_surv=merge(annot_pat,annot_surv,by="patID")
annot_pat_relapse=merge(annot_pat,annot_relapse,by="patID")

pdf("imaging_annotation_surv.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_surv)[[1]])
dev.off()

pdf("imaging_annotation_surv_dp.pdf",height=4,width=4)
print(plot_dots(annot_pat_surv))
dev.off()

pdf("imaging_annotation_relapse.pdf",height=3.5,width=3)
print(plot_surv(annot_pat_relapse,type="rel")[[1]])
dev.off()

pdf("imaging_annotation_relapse_dp.pdf",height=4,width=4)
print(plot_dots(annot_pat_relapse))
dev.off()

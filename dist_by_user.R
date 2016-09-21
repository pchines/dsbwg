#!/usr/bin/env Rscript
args=commandArgs(trailingOnly = T)
section=ifelse(length(args)>0, paste0(".",args[1]), "")
isilons=c("centaur","ketu","spock","wyvern")
k=data.frame(user=character(0))
for (n in isilons) {
    i=read.table(paste0(n,section,".csv"), header=F, sep=",", col.names=c("user","x",paste0(n,section)), stringsAsFactors=F, colClasses=c("character","NULL","numeric"))
    i$user=gsub("^NIH\\\\","",i$user)
    j=aggregate(.~user,i,sum)
    k=merge(k,j,all=T)
}
for (n in c(2,3,4,5)) {
    k[ is.na(k[,n]), n] = 0
}
k[,paste0("total",section)]=apply(k,1,function(x){sum(as.numeric(x[2:5]))})
k$status=ifelse(grepl("^(NIH|UID|SID):",k$user,perl=T),"Unknown","Known")
k$status[k$user=="TOTAL" | k$user=="Unknown"] = ""
x=k[k$user!="TOTAL" & k$user!="Unknown",]
table(x$status)

k$user[k$user=="TOTAL"]="TOTAL of all users"
k$user[k$user=="Unknown"]="TOTAL of unknown users"
if (section != "" & file.exists("all.totals.csv")) {
    tot=read.table("all.totals.csv", header=T, sep=",")
    j=tot[,c("user","total")]
    k=merge(k,j,all.x=T)
    k[,paste0("frac",section)]=apply(k,1,function(x){as.numeric(x[paste0("total",section)]) / as.numeric(x["total"])})
}
write.csv(k,file=paste0("all", section, ".totals.csv"),quote=F,row.names=F)

library(ggplot2)
#library(reshape2)
#y=melt(x)
#ggplot(data=y)+geom_histogram(aes(x=value,fill=status))+facet_wrap(~variable,ncol=3)+scale_x_log10()+labs(x="Total storage used (log scale)",y="Number of Users",title="Distribution of storage by User")+theme_bw()

pdf(paste0("storage_by_user", section, ".pdf"))
cols=sapply(c("total",isilons), function(x){ paste0(x,section) })
for (i in cols) {
    print(ggplot(data=x)+geom_histogram(aes_string(x=i,fill="status"))+scale_x_log10(limits=c(1,1e15))+labs(x="Total storage used (log scale)",y="Number of Users",title=paste("Distribution of",i,"storage by User"))+theme_bw())
}
dev.off()
q()

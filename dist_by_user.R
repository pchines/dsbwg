#!/usr/bin/env Rscript
args=commandArgs(trailingOnly = T)
section=ifelse(length(args)>0, paste0(".",args[1]), "")
isilons=c("bo","centaur","ketu","spock","wyvern")
k=data.frame(user=character(0))
u=data.frame(user=character(0), fullname=character(0))
for (n in isilons) {
    nm=paste0(n,section)
    i=read.table(paste0(nm,".csv"), header=F, sep=",",
            col.names=c("user","fullname",nm), stringsAsFactors=F, colClasses=c("character","character","numeric"))
    i$user=gsub("^NIH\\\\","",i$user)
    j=aggregate(.~user,i[,c("user",nm)],sum)
    k=merge(k,j,all=T)
    u=rbind(u, i[,c("user","fullname")])
}
end=length(isilons)+1
for (n in c(2:end)) {
    k[ is.na(k[,n]), n] = 0
}
k[,paste0("total",section)]=apply(k,1,function(x){sum(as.numeric(x[2:end]))})
k$status=ifelse(grepl("^(NIH|UID|SID):",k$user,perl=T),"Unknown","Known")
k$status[k$user=="TOTAL" | k$user=="Unknown"] = ""
x=k[k$user!="TOTAL" & k$user!="Unknown",]
table(x$status)

k=merge(k, unique(u))
k$fullname[k$user=="TOTAL"]="TOTAL of all users"
k$fullname[k$user=="Unknown"]="TOTAL of unknown users"
if (section != "" & file.exists("all.totals.csv")) {
    tot=read.table("all.totals.csv", header=T, sep=",")
    j=tot[,c("user","total")]
    k=merge(k,j,all.x=T)
    k[,paste0("frac",section)]=apply(k,1,function(x){as.numeric(x[paste0("total",section)]) / as.numeric(x["total"])})
}
write.csv(k[order(k[,paste0("total",section)], decreasing=T),],file=paste0("all", section, ".totals.csv"),quote=F,row.names=F)

library(ggplot2)

pdf(paste0("storage_by_user", section, ".pdf"))
cols=sapply(c("total",isilons), function(x){ paste0(x,section) })
for (i in cols) {
    print(ggplot(data=x)+geom_histogram(aes_string(x=i,fill="status"))+scale_x_log10(limits=c(1,1e15),breaks=sapply(seq(3,15,3),function(x){10^x}))+labs(x="Total storage used (log scale)",y="Number of Users",title=paste("Distribution of",i,"storage by User"))+theme_bw())
}
dev.off()
q()

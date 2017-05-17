#!/usr/bin/env Rscript
args=commandArgs(trailingOnly = T)
if ( length(args) < 2 ) {
    stop("Usage: ./change_by_user.R YYMMDD(from) YYMMDD(to)")
}
then_date=args[1]
now_date=args[2]
section=ifelse(length(args)>2, paste0(".",args[3]), "")

now=read.table(paste0(now_date,"/all.",now_date,section,".totals.csv"),sep=",",header=T,quote=NULL)
then=read.table(paste0(then_date,"/all.",then_date,section,".totals.csv"),sep=",",header=T,quote=NULL)
nt=merge(now,then,by="user", all=T)

na.zero=function(x){x[is.na(x)]=0;return(x)}
isilons=c("bo","centaur","ketu","spock","wyvern")
for (i in isilons) {
    nt[,paste0(i,section,".diff")] =
        na.zero(nt[,paste0(i,".",now_date,section)]) -
        na.zero(nt[,paste0(i,".",then_date,section)])
}
nt$status.y=NULL
nt$fullname.y=NULL
names(nt) = sub("\\.x$","",names(nt))
write.csv(nt, file=paste0("storage",section,".diff.from.",then_date,".to.",now_date,".csv"), row.names=F, quote=F)
q()

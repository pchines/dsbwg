#!/usr/bin/env Rscript
isilons=c("centaur","ketu","spock","wyvern")
k=data.frame(user=character(0))
for (n in isilons) {
    i=read.table(paste0(n,".csv"), header=F, sep=",", col.names=c("user","x",n), stringsAsFactors=F, colClasses=c("character","NULL","numeric"))
    i$user=gsub("^NIH\\\\","",i$user)
    j=aggregate(.~user,i,sum)
    k=merge(k,j,all=T)
}
for (n in c(2,3,4,5)) {
    k[ is.na(k[,n]), n] = 0
}
k$total=k$centaur+k$ketu+k$spock+k$wyvern
k$status=ifelse(grepl("^(NIH|UID|SID):",k$user,perl=T),"Unknown","Known")
x=k[k$user!="TOTAL" & k$user!="Unknown",]
table(x$status)

k$user[k$user=="TOTAL"]="TOTAL of all users"
k$user[k$user=="Unknown"]="TOTAL of unknown users"
write.csv(k,file="all.totals.csv",quote=F,row.names=F)

library(ggplot2)
#library(reshape2)
#y=melt(x)
#ggplot(data=y)+geom_histogram(aes(x=value,fill=status))+facet_wrap(~variable,ncol=3)+scale_x_log10()+labs(x="Total storage used (log scale)",y="Number of Users",title="Distribution of storage by User")+theme_bw()

pdf("storage_by_user.pdf")
for (i in c("total",isilons)) {
    print(ggplot(data=x)+geom_histogram(aes_string(x=i,fill="status"))+scale_x_log10()+labs(x="Total storage used (log scale)",y="Number of Users",title=paste("Distribution of",i,"storage by User"))+theme_bw())
}
dev.off()
q()

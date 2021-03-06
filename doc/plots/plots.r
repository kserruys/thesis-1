require(plotrix)

enabled  <- read.csv(file="enabled.csv", header=T)
disabled <- read.csv(file="disabled.csv", header=T)

tree_names    <- enabled[1:5, 'Name']
tree_fused    <- enabled[1:5, 'Mean']
tree_unfused  <- disabled[1:5, 'Mean']
tree_speedups <- 100 * (tree_unfused - tree_fused) / tree_unfused

pdf("tree-speedups.pdf")
barplot(tree_speedups,
        xlab='Benchmark',
        ylab='Speedup (in %)',
        names.arg=tree_names,
        ylim=c(0,100))
dev.off()

pdf("tree.pdf")
plotCI(seq(1, 5), 1000*tree_unfused,
        enabled[1:5, 'StddevUB'] * 2000,
        enabled[1:5, 'StddevLB'] * 2000,
        pch=0,
        ylim=c(0, max(1000*tree_unfused)),
        xlab="Benchmark",
        ylab="Time (in ms)",
        col='red',
        axes=F)
plotCI(seq(1, 5), 1000*tree_fused,
        enabled[1:5, 'StddevUB'] * 2000,
        enabled[1:5, 'StddevLB'] * 2000,
        pch=1,
        col='blue',
        add=T)
axis(side=1, at=seq(1, 5), labels=tree_names, lwd=0)
axis(side=2)
legend("topleft", legend=c("Without fusion", "With fusion"), pch=c(0, 1),
       col=c('red', 'blue'))
dev.off()

# Copy pasta. s/tree/list/g. s/1:5/6:10

enabled  <- read.csv(file="enabled.csv", header=T)
disabled <- read.csv(file="disabled.csv", header=T)

list_names    <- enabled[6:10, 'Name']
list_fused    <- enabled[6:10, 'Mean']
list_unfused  <- disabled[6:10, 'Mean']
list_speedups <- 100 * (list_unfused - list_fused) / list_unfused

pdf("list-speedups.pdf")
barplot(list_speedups,
        xlab='Benchmark',
        ylab='Speedup (in %)',
        names.arg=list_names,
        ylim=c(0,100))
dev.off()

pdf("list.pdf")
plotCI(seq(1, 5), 1000 * list_unfused,
        enabled[6:10, 'StddevUB'] * 2000,
        enabled[6:10, 'StddevLB'] * 2000,
        pch=0,
        ylim=c(0, max(1000 * list_unfused)),
        xlab="Benchmark",
        ylab="Time (in ms)",
        col='red',
        axes=F)
plotCI(seq(1, 5), 1000 * list_fused,
        enabled[6:10, 'StddevUB'] * 2000,
        enabled[6:10, 'StddevLB'] * 2000,
        pch=1,
        col='blue',
        add=T)
axis(side=1, at=seq(1, 5), labels=list_names, lwd=0)
axis(side=2)
legend("topleft", legend=c("Without fusion", "With fusion"), pch=c(0, 1),
       col=c('red', 'blue'))
dev.off()

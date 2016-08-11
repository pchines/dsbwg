#!/usr/bin/perl -w
use strict;

my $dORv = shift;
my $delta = shift;
my $WithOverhead = 1;
$WithOverhead = $ARGV[0] if(defined($ARGV[0]));
my $reportPath = "projects";
$reportPath = $ARGV[1] if(defined($ARGV[1]));
my %id2user;
my %idUsage;
open F,"/etc/passwd2";
while (<F>) {
	chomp;
	my @f = split(/:/,$_);
	$id2user{$f[2]} = \@f;
}
close F;
open F,"/etc/passwd";
while (<F>) {
	chomp;
	my @f = split(/:/,$_);
	$id2user{$f[2]} = \@f;
}
my $dir = "/cluster/ifs/Isilon_quota_reports/";
opendir D,$dir; 
my @reports;
while(defined(my $r = readdir(D))){
	next unless $r =~ /scheduled_quota_report/;
	next unless $r =~ /xml$/;
	push @reports,$r;
}
my $t = time();
@reports = sort @reports;
my $i = scalar(@reports);
my @tps;
push @tps, $dir.$reports[$i-1];
print "first = $reports[$i-1]\n";
while(--$i >= 0) {
	my $sec = $reports[$i];
	$sec =~ s/scheduled_quota_report_//;
	$sec =~ s/.xml//;
	my $days = ($t-$sec)/24/3600;
	if($days > $delta) {
		unshift @tps, $dir.$reports[$i];
		print "second = $reports[$i]\n";
		last;
	}
	print "skip = $reports[$i]\n";
}
if($i == -1) {
	unshift @tps, $dir.$reports[0];
}
print "@tps\n";
foreach (@tps) {
    process_file($_);
}
my %du;
foreach my $id (sort {$a <=> $b} keys %idUsage) {
	next unless scalar (@{$idUsage{$id}}) == 2;
	my $delta = $idUsage{$id}->[1] - $idUsage{$id}->[0];
	my @f;
	push @f,$delta;
	push @f,$idUsage{$id}->[1];
	if(!exists($id2user{$id})) {
		#print "no user $id\n";
		$id2user{$id}->[4] = $id;
	}
	push @f,sprintf("%10.3e,%10.3e,%s\n",$delta,$idUsage{$id}->[1],$id2user{$id}->[4]);
	$du{$id} = \@f;
}
my $totalUsage = 0;
my $totalDelta = 0;
foreach my $id (sort {$du{$a}->[$dORv] <=> $du{$b}->[$dORv]} keys %du) {
	print $du{$id}->[2];
	$totalUsage += $du{$id}->[1];
	$totalDelta += $du{$id}->[0];
}
printf("%10.3e,%10.3e\n",$totalDelta,$totalUsage);

sub process_file {
    my ($fname) = @_;
	return unless -e $fname;
	if($fname =~ /xml$/) {
		open XML,$fname or return;
	} elsif ($fname =~ /xml.Z/ or $fname =~ /xml.gz/) {
		open XML,"gunzip -c $fname |" or return;
	} else {
		return;
	}
	my $id = 0;
	my $path;
	my $idUsage = -1;
	while(<XML>) {
		if(/<domain type=.user.*id=.(\d+).>/) {
			$id = $1;
			$idUsage = -1;
			next;
		}
		if(/<path>(.*)<.path>/) {
			$path = $1;
			if($path =~ /$reportPath$/) {
				next unless $idUsage > -1;
				push @{$idUsage{$id}},$idUsage;
			} else {
				$idUsage = -1;
			}
		}
		if($WithOverhead == 1) {
			if(/<usage resource=.physical.>(\d+)<.usage>/) {
				$idUsage = $1;
				next;
			}
		} elsif($WithOverhead == 2) {
			if(/<usage resource=.inodes.>(\d+)<.usage>/) {
				$idUsage = $1;
				next;
			}
		} else {
			if(/<usage resource=.logical.>(\d+)<.usage>/) {
				$idUsage = $1;
				next;
			}
		}
	}
	return;
}

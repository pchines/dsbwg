#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
our %Opt;
our $EMPTY = q{};

=head1 NAME

parseIsilonQuotaReports.pl - gather per-user disk usage info

=head1 SYNOPSIS

Gather per-user disk usage, report:

  parseIsilonQuotaReports.pl

For complete documentation, run C<parseIsilonQuotaReports.pl -man>

=head1 DESCRIPTION

Gather per-user disk usage, report total space used and change from as many
as 10 days previous (default 1, set with -delta option).

=cut

process_commandline();

if (!-d $Opt{isilon_dir}) {
    die "$Opt{isilon_dir} does not exist; specify with -isilon_dir option\n";
}
if (!-r _) {
    die "You do not have permissions to read Isilon report dir $Opt{isilon_dir}\n";
}

my $dORv = $Opt{'sort'} eq 'total' ? 1 : 0;
my $delta = $Opt{delta};
my $WithOverhead = $Opt{logical} ? 0 : $Opt{nodes} ? 2 : 1;
my $reportPath = $Opt{match};
my %id2user;
my %idUsage;
if (-f "/etc/passwd2" && -r _) {
    open F,"/etc/passwd2";
    while (<F>) {
        chomp;
        my @f = split(/:/,$_);
        $id2user{$f[2]} = \@f;
    }
}
open F,"/etc/passwd";
while (<F>) {
	chomp;
	my @f = split(/:/,$_);
	$id2user{$f[2]} = \@f;
}
my $dir = $Opt{isilon_dir};
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
push @tps, $dir ."/". $reports[$i-1];
print "first = $reports[$i-1]\n";
while(--$i >= 0) {
	my $sec = $reports[$i];
	$sec =~ s/scheduled_quota_report_//;
	$sec =~ s/.xml//;
	my $days = ($t-$sec)/24/3600;
	if($days > $delta) {
		unshift @tps, $dir."/".$reports[$i];
		print "second = $reports[$i]\n";
		last;
	}
	print "skip = $reports[$i]\n";
}
if($i == -1) {
	unshift @tps, $dir."/".$reports[0];
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

sub process_commandline {
    %Opt = (isilon_dir  => '/cluster/ifs/Isilon_quota_reports',
            match       => 'projects',
            );
    GetOptions(\%Opt, qw(delta:i isilon_dir=s logical match|m=s nodes sort=s
                manual help+ version)) || pod2usage(1);
    if ($Opt{manual})  { pod2usage(verbose => 2); }
    if ($Opt{help})    { pod2usage(verbose => $Opt{help}-1); }
    if ($Opt{version}) { die "parseIsilonQuotaReports.pl, ", q$Revision: 1991 $, "\n"; }
    $Opt{'sort'} ||= defined($Opt{delta}) ? 'delta' : 'total';
    if ($Opt{'sort'} =~ /^[cd]/i) {
        $Opt{'sort'} = 'delta';
    }
    elsif ($Opt{'sort'} =~ /^[un]/i) {
        $Opt{'sort'} = 'user';
    }
    else {
        $Opt{'sort'} = 'total';
    }
    $Opt{delta} ||= 1;
    if ($Opt{delta} < 1) {
        pod2usage("--delta DAYS cannot be negative");
    }
}

=head1 OPTIONS

=over 4

=item B<--delta> DAYS

Number of days (current max == 10) back to use to calculate change in disk
space usage.  The default is 1 day.  If this option is manually set, the sort
order will default to "delta", but can be overridden.  See C<--sort>.

=item B<--isilon_dir> DIR

Set location to read Isilon quota reports from.  Defaults to
/cluster/ifs/Isilon_quota_reports.

=item B<--logical>

Report logical disk space used (just the size of user files), rather than the
default physical space, which includes overhead.

=item B<--match> BASENAME

Gather per-user disk usage only from directories ending with the basename
specified.  Defaults (for now) to 'projects', to match current behavior.
Will likely change.

=item B<--nodes>

Report inode count per user, rather than disk space.  Can't be used with
C<--logical>.

=item B<--sort> delta | total

Specify sort order (can abbreviate to first initial).  Defaults to 'total',
unless a C<--delta> is specified.

=item B<--help|--manual>

Display documentation.  One C<--help> gives a brief synopsis, C<-h -h> shows
all options, C<--manual> provides complete documentation.

=back

=head1 AUTHOR

 Peter Chines - pchines@mail.nih.gov

=head1 LEGAL

This software/database is "United States Government Work" under the terms of
the United States Copyright Act.  It was written as part of the authors'
official duties for the United States Government and thus cannot be
copyrighted.  This software/database is freely available to the public for
use without a copyright notice.  Restrictions cannot be placed on its present
or future use.

Although all reasonable efforts have been taken to ensure the accuracy and
reliability of the software and data, the National Human Genome Research
Institute (NHGRI) and the U.S. Government does not and cannot warrant the
performance or results that may be obtained by using this software or data.
NHGRI and the U.S.  Government disclaims all warranties as to performance,
merchantability or fitness for any particular purpose.

In any work or product derived from this material, proper attribution of the
authors as the source of the software or data should be made, using "NHGRI
Genome Technology Branch" as the citation.

=cut

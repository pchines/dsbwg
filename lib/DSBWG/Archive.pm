# DSBWG/Archive.pm
package DSBWG::Archive;

use strict;
use warnings;
use Carp;
use File::Spec;
use Digest::MD5 qw(md5_hex);
use NHGRI::Db::Connector;
use GTB::File qw(Open);
use GTB::Run qw(as_number);

our $EMPTY = q{};
our @RequiredStats = qw(size n_files n_dirs);
our @Isilons = qw(bo centaur ketu spock wyvern);
our $MAX_FILE_SIZE = 256 * 1024 * 1024; # 256Mb

=head1 NAME

DSBWG::Archive - object-oriented library for archives

=head1 SYNOPSIS

  use DSBWG::Archive;
  my $ar = DSBWG::Archive->new();

=head1 DESCRIPTION

=cut

sub new {
    my $pkg = shift;
    my %defaults = (
            date => today(),
            db   => 'storage',
            user => $ENV{USER},
            );
    my %param;
    if (@_ == 1) {
        %param = (%defaults, %{$_[0]});
    }
    elsif (@_ % 2 == 0) {
        %param = (%defaults, @_);
    }
    else {
        croak "DSBWG::Archive:new: expect hash or hash ref";
    }
    my $self = bless \%param, (ref $pkg || __PACKAGE__);
    $self->{dbc} = NHGRI::Db::Connector->new(-realm => $self->{db}, -dbi_attrib => {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        });
    return $self;
}

sub dbh {
    my ($self) = @_;
    return $self->{dbc}->connect();
}

sub get_archive_request {
    my ($self, $id) = @_;
    if (!$self->{_ar} || $self->{_ar}{archive_id} != $id) {
        my $dbh = $self->dbh();
        my $ra = $dbh->selectall_arrayref(q/
                SELECT * FROM archives WHERE archive_id = ?
                /, {Slice => {}}, $id);
        if (@$ra != 1) {
            die "Error retrieving archive request #$id: "
                . ($dbh->errstr ? $dbh->errstr : "record not found")
                . "\n";
        }
        $self->{_ar} = $ra->[0];
    }
    return $self->{_ar};
}

sub update_status {
    my ($self, %p) = @_;
    my $ar = $self->{_ar}
        || croak "Must get_archive_request() before calling update_status()";
    if ($ar->{curr_status} ne $p{status_from}) {
        warn "Expected before status '$p{status_from}', got '$ar->{curr_status}'\n";
        $self->confirm("Continue");
    }
    my $cp = $p{check_path} || $p{real_path} || $p{user_path};
    if (!$self->similar_ending($ar->{user_path}, $cp)) {
        die "Archive request #$ar->{archive_id} refers to path"
            . " '$ar->{user_path}',\nwhile this INFO file is from"
            . " '$cp'.\nAborting.\n";
    }
    if ($p{archive_id} && $p{archive_id} != $ar->{archive_id}) {
        die "This INFO file is from archive #$p{archive_id}, not #$ar->{archive_id}\n";
    }

    my $sql = "UPDATE archives SET curr_status = ?";
    my @f = ("status_to");
    my $msg = "Preparing update for Archive Request #$ar->{archive_id}:\n";
    if ($p{status_from} ne $p{status_to}) {
        $msg .= "\tChange status from '$p{status_from}' to '$p{status_to}'\n";
    }
    for my $k (sort keys %p) {
        next if $k =~ /^(status_(to|from)|check_path)$/;
        if ($k eq "notes_add") {
            $msg .= "\tAdd '$p{$k}' to notes\n";
            $sql .= ", notes = CONCAT(IFNULL(notes,''),?)";
            push @f, "notes_add";
        }
        elsif ($k =~ /^(\w+)_file$/) {
            $msg .= "\tSet ${1}_info to contents of $p{$k}\n";
        }
        else {
            if (defined $p{$k}) {
                $msg .= "\tSet $k to '$p{$k}'\n";
            }
            else {
                $msg .= "\tSet $k to NULL\n";
            }
            $sql .= ", $k = ?";
            push @f, $k;
        }
    }
    $msg .= "Proceed";
    $sql .= " WHERE archive_id = ? AND curr_status = ?";
    my $rv = 0;
    if ($self->confirm($msg, "Y")) {
        my $dbh = $self->dbh();
        my $sth = $dbh->prepare($sql);
        $rv = $sth->execute(
            (map { $p{$_} } @f), $ar->{archive_id}, $ar->{curr_status} );
    }
    return $rv+0;
}

sub upload_file {
    my ($self, $file, $col) = @_;
    my $ar = $self->{_ar}
        || croak "Must get_archive_request() before calling upload_file()";
    my $id = $ar->{archive_id} || die "Missing archive ID";
    my $dbh = $self->dbh();
    my $rs_content = $self->slurp_file($file);
    my $sql;
    my @md5;
    my $md5_col = $col;
    if ($md5_col =~ s/_info/_md5/) {
        @md5 = md5_hex($$rs_content);
        $sql = qq/UPDATE archives SET $col = ?, $md5_col = ?
                   WHERE archive_id = ?
                 /;
    } else {
        $sql = qq/UPDATE archives SET $col = ? WHERE archive_id = ?/;
    }
    my $sth = $dbh->prepare($sql);
    my $rv = $sth->execute($$rs_content, @md5, $id);
    return $rv+0;
}

sub slurp_file {
    my ($self, $file) = @_;
    my $size = -s $file;
    if ($size > $MAX_FILE_SIZE) {
        warn "WARNING: $file is larger than maximum allowed size\n";
    }
    my $fh;
    open $fh, "<", $file or die "Error opening $file, $!\n";
    local $/;
    my $data = <$fh>;
    return \$data;
}


sub similar_ending {
    my ($self, $p1, $p2) = @_;
    my @a = File::Spec->splitdir($p1);
    my @b = File::Spec->splitdir($p2);
    return $a[-1] eq $b[-1];
}

sub read_stats {
    my ($self, $ifile, $upload) = @_;
    my %stats;
    my $pre = $ifile;
    if ($pre !~ s/\.info\.txt(?:\.gz)?$//) {
        die "Invalid input file name; should be output '<PREFIX>.info.txt'"
            . " file\nfrom archive_check program.\n";
    }
    $stats{files_file} = "$pre.files.txt.gz";
    $stats{dirs_file}  = "$pre.dirs.txt.gz";
    if ($upload && !(-f $stats{files_file} && -f $stats{dirs_file})) {
        die "Missing $stats{files_file} or $stats{dirs_file}\n"
            . "These files must be in same directory as $ifile\n"
            . "To proceed without uploading these files, use the"
            . " --noupload option\n";
    }
    my $ifh = Open($ifile);
    while (<$ifh>) {
        if (/^Pre-archive report for ([\w.-]+):(.+)/) {
            my ($h, $p) = ($1, $2);
            $stats{user_host} = munge_hostname($h);
            $stats{user_path} = $p;
            set_real_path(\%stats, $h, $p);
        }
        elsif (/Total size of files:\s+([\d.]+[KMGTP]?)$/) {
            $stats{size} = as_number($1);
        }
        elsif (/Total number of (files|dirs):\s+(\d+)/) {
            $stats{"n_$1"} = $2;
        }
    }
    my @miss = grep { !exists $stats{$_} } @RequiredStats;
    if (@miss) {
        warn "Missing expected information in $ifile: "
            . join(", ", @miss) . "\n";
        $self->confirm("Continue");
    }
    return \%stats;
}

sub munge_hostname {
    my ($h) = @_;
    if ($h =~ /k\w+\.gc\.nih\.gov/) {
        $h = "trek";
    }
    if ($h =~ /^(ghead\d+|gryphon-\w+|gry-compute\d+)\.core\.nhgri\.nih\.gov/) {
        $h = "gryphon";
    }
    if ($h =~ /^(\w+)-(?:ba|sc)\.nhgri\.nih\.gov$/) {
        $h = $1;
    }
    return $h;
}

sub set_real_path {
    my ($rh_s, $h, $p) = @_;
    my $isilons = join "|", @Isilons;
    if ($h =~ /^($isilons)$/i) {
        $rh_s->{real_host} = $h;
        $rh_s->{real_path} = $p;
    }
    elsif ($h eq munge_hostname($ENV{HOSTNAME})) {
        my ($real_h, $export, $mount) = get_mount($p);
        if (!$mount) {
            warn "Can't find local mount matching $p\n";
        }
        elsif ($p !~ s/^$mount/$export/) {
            warn "Error translating path based on $mount = $export\n";
        }
        else {
            $rh_s->{real_host} = $real_h;
            $rh_s->{real_path} = $p;
        }
    }
}

sub get_mount {
    my ($p) = @_;
    my ($mh, $ex, $mp);
    my @o = `df -h $p`;
    if ($o[1] =~ /^([\w\.]+):(\S+)/) {
        $mh = $1;
        $ex = $2;
        if ($o[1] =~ /(\S+)$/) {
            $mp = $1;
        }
    }
    return ($mh, $ex, $mp);
}

sub today {
    my @t = localtime();
    return sprintf("%d-%02d-%02d", $t[5]+1900, $t[4]+1, $t[3]);
}

sub ask {
    my ($self, $msg, $default) = @_;
    print STDERR "$msg ";
    my $resp = <STDIN>;
    chomp $resp;
    if ($resp eq $EMPTY) {
        $resp = $default;
    }
    return $resp;
}

sub confirm {
    my ($self, $msg, $default) = @_;
    $default ||= "N";
    my $choices = $default eq "N" ? "y/N" : "Y/n";
    my $resp = $self->ask("$msg? [$choices]", $default);
    my $ok = $resp =~ /^Y/i;
    if ($msg eq "Continue" && !$ok) {
        die "Aborting at user request.\n";
    }
    return $ok;
}

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
Information Technology Branch" as the citation. 

=cut

1;

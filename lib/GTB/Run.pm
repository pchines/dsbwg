# $Id: Run.pm 7738 2016-11-26 20:53:51Z pchines $
package GTB::Run;

use strict;
use GTB::File qw(Open);
use File::Temp qw(tempfile);
use Carp qw(carp croak confess);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(find_exe get_output run_command run_cmd
        read_map slurp_file
        as_number human_readable comment_usage make_prefix_regex
        now secs2hms today
        warn_once);

our $VERSION = '0.23';
our $VERBOSE = 0;
our $KILO = 1024;
my $EMPTY = q{};

sub find_exe {
    my ($prog) = @_;
    my $out = `which $prog`;
    chomp $out;
    return $out;
}

sub get_output {
    my ($cmd) = @_;
    my $temp = '/dev/null';
    if (wantarray) {
        (undef, $temp) = tempfile();
    }
    if ($VERBOSE) {
        warn "Capturing output: $cmd 2>$temp\n";
    }
    my $out = `$cmd 2>$temp`;
    my $rc = $?;
    my $err;
    if (wantarray) {
        $err = slurp_file($temp);
        unlink $temp;
    }
    return wantarray ? ($out, $err, $rc) : $out;
}

sub run_cmd {
    carp "run_cmd is deprecated; use run_command instead";
    goto &run_command;
}

sub run_command {
    my ($cmd, $expected) = @_;
    if ($VERBOSE) {
        warn "Running: $cmd\n";
    }
    my $rc = system $cmd;
    if (defined($expected) && $rc == $expected) {
        return;
    }
    if ($rc == -1) {
        die "Failed to start command: $!\n";
    }
    if ($rc & 127) {
        die sprintf "Program died from signal %d, %s coredump\n",
            ($rc & 127), ($rc & 128) ? 'with' : 'without';
    }
    if (defined $expected) {
        die "Command returned $rc, not $expected as expected\n";
    }
    if ($rc) {
        warn sprintf "Program returned error code %d\n", $rc >> 8;
    }
    return $rc;
}

sub slurp_file {
    my ($file) = @_;
    my $fh = Open($file);
    my @data = <$fh>;
    return wantarray ? @data : join($EMPTY, @data);
}

sub read_map {
    my ($file, $delim) = @_;
    $delim ||= "\t";
    my $fh = Open($file);
    my %map;
    while (my $x = <$fh>) {
        chomp $x;
        my ($key, $val) = split $delim, $x;
        if (exists $map{$key}) {
            warn "Warning: redefinition of '$key' in '$file':\n"
                . "was '$map{$key}', now '$val'\n";
        }
        $map{$key} = $val;
    }
    return \%map;
}

sub as_number {
    my ($val) = @_;
    if (!defined $val) {
        return 0;
    }
    my $n = $val;
    $n =~ s/[\s,]//g;
    $n =~ s/b$//i;
    my $units = "KMGTPZY";
    if ($n =~ s/(?<=\d)([$units])$//i) {
        my $suff = uc $1;
        while ($units && $suff =~ /^[$units]$/) {
            $n *= $KILO;
            $units = substr($units,1);
        }
    }
    # gives warning if unknown suffix is used
    return $n+0;
}

sub human_readable {
    my ($n, $fmt) = @_;
    my $val = $n;
    my $unit = $EMPTY;
    $fmt ||= "%.0f";
    my $e = int(log($val) / log($KILO));
    if ($e > 0) {
        $val /= $KILO ** $e;
        $unit = substr(".KMGTPZY", $e, 1);
    }
    return sprintf($fmt, $val) . $unit;
}

sub make_prefix_regex {
    my ($min, @vals) = @_;
    $min -= 1;
    my $regex = '(?:';
    for my $match (@vals) {
        $regex .= substr($match,0,$min) . '(?:';
        for (my $i = length($match)-$min; $i > 0; --$i) {
            $regex .= substr($match,$min,$i) . '|';
        }
        chop $regex;
        $regex .= ')|';
    }
    chop $regex;
    $regex .= ')';
    return $regex;
}

###################################################################### 
# comment_usage - print the comments at the beginning of the executable
#  as a usage message and die
# INPUTS:  Any strings passed in will be printed as error messages
#          following the usage message.
# OUTPUTS: Prints usage message and exit(1);
######################################################################
sub comment_usage {
    my @errors = @_;

    open IN, $0 or confess "Couldn't read source ($0): $!";
    $_ = <IN>;
    
    # skip frst 3 lines if the program starts with an eval statement 
    # added by make install
    my $line2pos = tell(IN);
    $_ = <IN>; $_ .= <IN>; $_ .= <IN>;
    if ($_ !~ /\neval 'exec .*\n\s+if 0;[^\n]+\n/) {
        seek(IN, $line2pos, 0);
    }

    while (<IN>) {
        if(s/^#[ \t]?//) {
           print STDERR $_;
        } else {
            close (IN);
            last;
        }
    }
    if (@errors) {
        foreach my $error (@errors) {
            chomp $error;
            $error .= "\n";
        }
        print STDERR "ERROR:\n";
        print STDERR @errors;
        print STDERR "Died", Carp::shortmess();
        exit 1;
    }
    else {
        exit 1;
    }
}

######################################################################
# secs2hms - convert elapsed seconds to string indicationg days, hours
#     minutes, etc.
# INPUTS:  # seconds
# OUTPUTS: returns string
######################################################################
sub secs2hms {
    my $secs = shift;
    my $str = '';
    if ($secs < 0) {
        $str = '- ';
        $secs = 0-$secs;
    }
    if ($secs > 60 * 60 * 24) {
        $str .= (int($secs / 86400)) . " days "
            . (int(($secs % (60*60*24)) / 3600)) . " hours "
            . (int(($secs % 3600) / 60)) . " mins "
            . (int($secs % 60)) . " secs";
    } else {
        $str .= (int($secs / 3600)) . " hours "
            . (int(($secs % 3600) / 60)) . " mins "
            . (int($secs % 60)) . " secs";
    }
    return $str;
}

sub today {
    my @t = localtime;
    return sprintf '%d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3];
}

sub now {
    my ($tz) = @_;
    my @t;
    if (!$tz) {
        @t = localtime;
    }
    elsif ($tz =~ /(utc|gmt)/i) {
        @t = gmtime;
    }
    return sprintf '%02d:%02d:%02d', $t[2], $t[1], $t[0];
}

{   # begin closure
    my %seen;
sub warn_once {
    my ($msg, $detail) = @_;
    if (!exists $seen{$msg}) {
        if (defined $detail) {
            warn "$msg $detail\n";
        }
        else {
            warn "$msg\n";
        }
        $seen{$msg} = undef;
        return 1;
    }
    return 0;
}
}   # end closure

1;
__END__

=head1 NAME

GTB::Run - Functions related to running programs

=head1 SYNOPSIS

    use GTB::Run qw(get_output run_command);
    my $output = get_output('command -to run');
    run_command('command -to run');

=head1 DESCRIPTION

This is a library of exportable functions.

=head1 EXPORTABLE FUNCTIONS

=head2 Running commands:

=head3 get_output(COMMAND)

Run the command and returns the output as a single long string.  Obviously,
this is not appropriate for programs with very large output.  Instead,
open a pipe to read the results of the command, or use C<run_command> to
write the results to a temporary file.

In scalar context, only STDOUT is returned.  In list context, STDOUT, STDERR,
and the return value are returned.  Running this function in list context
when including shell redirects in the command is not well-defined, and
will likely fail.

  Usage : my $output = get_output('command -to run');
          my ($out, $err, $rv) = get_output('command -to run');
  Args  : command to be run, as a single string
  Return: STDOUT in scalar context (STDERR to /dev/null)
          STDOUT, STDERR, and UNIX return value in list context

=head3 run_command(COMMAND)

Runs the specified command.  Returns the system() return value (encodes
signal, core dump, program return value), zero on success.

If the return value is expected to be some particular value (e.g. 0), and you
want to terminate the program if it does not match, provide this expected
return value as the second argument.

  Usage : my $rv = run_command('command -to run');
          run_command('command -to run', $expected_rv);
  Args  : command to be run, as a single string
          optional expected return value
  Return: system() return value
  Except: dies if program fails to start, or is killed by a signal,
          or fails to match the optional return value provided

=head3 find_exe(STRING)

Return the location of the first instance of the given program in the user's
PATH, or an empty string if the program is not found.

  Usage : find_exe("a_program") || die "Can't find a_program in PATH\n";
  Args  : program name
  Return: path to program, or empty string

=head2 Reading files:

=head3 read_map(FILE [,DELIM])

Reads the first two columns of a delimited file and builds a hash,
interpreting the first column value as the key, and the second as the
value.

  Usage : my $rh_map = read_map("/path/to/file.txt");
          my $rh_map = read_map("/path/to/file.csv", ",");
  Args  : filename (required)
          delimiter (optional, default is tab)
  Return: reference to hash
  Except: warns if a key is associated with more than one value.

=head3 slurp_file(FILE)

Reads an entire file into memory.  In list context, returns array of lines;
in scalar context returns entire contents in a single string.

  Usage : my $contents = slurp_file("/path/to/file.txt");
          my @lines    = slurp_file("/path/to/file.txt");
  Args  : filename
  Return: contents as string or array

=head2 Options and Usage:

=head3 as_number(STRING)

Converts a user-input value, e.g. "3.2Gb" into a numeric representation.
Useful for specifying memory limits and other large values.  Also ignores
commas, which may be useful in other contexts.

Suffixes understood include "K", "M", "G", "T", "P", "Z", "Y", and their
lowercase equivalents, with or without trailing "b".  Either way, these are
interpreted as binary multipliers, not metric ones.  To change this, you may
set $GTB::Run::KILO to 1000.  Setting this variable to other values is not
recommended.

  Usage : my $value = as_number( $Opt{memory} );
  Args  : string representing numeric value
  Return: numeric equivalent

=head3 human_readable(NUMBER [,FMT])

Converts a number (typically a large integer) into a string representation,
using "K", "M", "G", "T", "P", "Z", and "Y" suffixes.  By default, these
represent binary quantifiers, but you can set $GTB::Run::KILO = 1000 to change
to metric (SI) units.  Optionally, supply sprintf format, which defaults to
"%.0f".

  Usage : my $value = human_readable( -s $file );
  Args  : numeric value
  Return: string expression with suffix

=head3 make_prefix_regex(LEN, @WORDS)

Creates a regular expression to detect any of the given words, or prefixes
thereof, with the minimum prefix length specified.  This is often useful when
requesting that a user provide an option value that should be one of a set of
prescribed choices.  For example, to recognize "alpha" (or even just "a") as
an abbreviation for "alphabetical".

  Usage : my $regex = make_prefix_regex(1, "alphabetical", "lexical");
          if ($opt =~ /^$regex$/i) {
              $opt = "alphabetical";
          }
  Args  : minimum length that must be matched (typically 1)
          list of words to test for a match
  Return: a string suitable for inclusion in a regular expression

Since the regular expression comes back without anchors or capturing parens,
these need to be provided by the calling code, as appropriate.  These
regexes try to capture the longest possible match, and so can be used
to substitute as well as match:

        $cmd =~ s/-?-$regex\b/--canonical/;

=head3 comment_usage([@ERRS])

Prints all lines beginning with # after the first line in the calling
script followed by any error messages passed to it.  ("\n" is added to 
each paramenter if it doesn't already exist).

  Usage : comment_usage(@error_messages);
  Args  : any error messages you want to append (optional)
  Return: exit(1);

e.g., a program starting with:

    #!/usr/bin/perl
    # this is a usage message
    # Usage: message <message>
    use strict;
    comment_usage();

would print:

    this is a usage message
    Usage: message <message>

and exit with a return value of 1.

=head2 Time-related:

=head3 secs2hms(NUMBER)

Converts a number of seconds into [days] hours, minutes, and seconds.

  Usage : print secs2hms(time() - $start_time);
  Args  : # of seconds
  Return: String representing the time elapsed 
          e.g., 4 hours 3 mins 22 secs

=head3 today()

Returns today's date in YYYY-MM-DD format.

  Usage : print "Run date: ", today(), "\n";
  Args  : none
  Return: date in YYYY-MM-DD format
 
=head3 now()

Returns the time in HH::MM::SS format.  Uses local time zone unless "UTC" is
specified as the first argument.

  Usage : my $here  = now();
          my $there = now('UTC');
  Args  : time zone, but only 'UTC' is understood
  Return: time in 24-hr HH:MM:SS format

=head2 Other:

=head3 warn_once(MSG [,DETAIL])

Issues a warning only the first time a given message is seen.  Optional
details are reported for this first instance.  Useful for cases where
the same situation is likely to occur on many lines of a file, but we only
want to report it once.

  Usage : warn_once("Something's rotten");
          warn_once("Something's rotten", "in Denmark")
  Args  : message - required
          details - optional
  Return: 1 if first report, else 0

Note that using this function with too many different warning messages can
use a lot of memory.  Make sure that the message is generic, and details (if
any) are relegated to the second argument.

=head1 AUTHORS

 Peter Chines <pchines@mail.nih.gov>
 Arjun Prasad <aprasad@nhgri.nih.gov>

=head1 LEGAL

This software is "United States Government Work" under the terms of
the United States Copyright Act.  It was written as part of the authors'
official duties for the United States Government and thus cannot be
copyrighted.  This software is freely available to the public for
use without a copyright notice.  Restrictions cannot be placed on its present
or future use. 

Although all reasonable efforts have been taken to ensure the accuracy and
reliability of the software and data, the National Human Genome Research
Institute (NHGRI) and the U.S. Government does not and cannot warrant the
performance or results that may be obtained by using this software or data.
NHGRI and the U.S. Government disclaims all warranties as to performance,
merchantability or fitness for any particular purpose. 

In any work or product derived from this material, proper attribution of the
authors as the source of the software or data should be made, using "NHGRI
Genome Technology Branch" as the citation. 

=cut

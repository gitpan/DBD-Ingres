#
# $Id: Ingperl.pm,v 1.6 1996/12/02 11:56:06 ht Exp $
#
# Ingperl emulation interface for DBD::Ingres
#
# This implements the functions of the former perl4 ingperl
# Ingres interface, as defined in the Ingperl 2.1 module by
# Tim Bunce <Tim.Bunce@ig.co.uk>
#
# Writte by Henrik Tougaard <ht@datani.dk>
#

use DBD::Ingres;

package Ingperl;
use DBI 0.73;
use Exporter;
use Carp;

$VERSION = substr(q$Revision: 1.6 $, 10);

@ISA = qw(Exporter);

@EXPORT = qw(
    &sql &sql_exec &sql_fetch &sql_close
    &sql_types &sql_ingtypes &sql_lengths &sql_nullable &sql_names
    $sql_version $sql_error $sql_sqlcode $sql_rowcount $sql_readonly
    $sql_showerrors $sql_debug
    $sql_drh $sql_dbh $sql_sth
    &sql_eval_row1 &sql_eval_col1
);

$debug    = 0 unless defined $debug;
$debugdbi = 0;

if ($debugdbi){
    my $sw = DBI->internal;
    $sw->debug($debugdbi);
    print "Switch: $sw->{Attribution}, $sw->{Version}\n";
    $sw->{DebugDispatch} = $debugdbi;
}


use strict;
use vars (qw[$sql_drh $sql_dbh $sql_sth $debug]);

# Install Driver
$sql_drh = DBI->install_driver('Ingres');
if ($sql_drh) {
	print "DBD::Ingres driver installed as $sql_drh\n" if $debug;
	$sql_drh->debug($debug);
	$sql_drh->{Warn}       = 0;
}



#	-----------------------------------------------------------------
#
# &sql_exec
# &sql_fetch()
# &sql()
#

sub sql_exec {
    my($statement) = @_;
    # decide what this is...
    warn "sql_exec('$statement')\n" if $Ingperl::debug;
    if ($statement =~ /^\s*connect\b/i) {
        # connect to the database;
        croak "Already connected to database" if $sql_dbh;
        my($database, $user, $option);
        # this contain the database name and possibly
        # a username
        # find database
        ($database) = $statement =~ /connect\s+([\w:]+)/;
        my $rest = $';  #possibly contains username... and other options
        if ($rest =~ /identified\s+by\s+(\w+)/) {
            $user = $1;
            $option = "$`$'"; # every thing else..
        } elsif ($rest =~ /-u(\w+)/) {
            $user = $1;
            $option = "$`$'"; # every thing else..
        } else {
            $user = ""; # noone;
            $option = $rest
        }
        warn "Ingperl connecting to database '$database' as user '$user'\n"
            if $Ingperl::debug;
	$option =~ s/^\s+//;
        $sql_dbh = $Ingperl::sql_drh->connect($database, $user, $option);
    }
    elsif ($statement =~ /^\s*disconnect\b/i) {
        croak "Ingperl: Not connected to database" unless $sql_dbh;
        $sql_dbh->disconnect();
        undef $sql_dbh;
    }
    elsif ($statement =~ /^\s*commit\b/i) {
        croak "Ingperl: Not connected to database" unless $sql_dbh;
        $sql_dbh->commit();
    }
    elsif ($statement =~ /^\s*rollback\b/i) {
        croak "Ingperl: Not connected to database" unless $sql_dbh;
        $sql_dbh->rollback();
    }
    else {
        # This is something else. Just execute the statement
        croak "Ingperl: Not connected to database" unless $sql_dbh;
        $sql_dbh->do($statement);
    }
}

sub sql_close {
	if ($sql_sth) {
	    $sql_sth->finish;
	    undef $sql_sth;
	    1;
	} else {
	    carp "Ingperl: close with no open cursor" unless $sql_sth;
	}
}

sub sql_fetch {
    croak "Ingperl: No active cursor\n" unless $sql_sth;
    my(@row) = $sql_sth->fetchrow();
    &sql_close() unless @row;
    @row;
}

sub sql {
    my ($statement) = @_;
    if ($statement =~ /^\s*fetch\b/i) {
        return &sql_fetch();
    }
    elsif ($statement =~ /^\s*select\b/i) {
        if ($sql_sth) {
            warn "IngPerl: Select while another select active\n".
                 "         Closing previous select: $sql_sth\n" if $Ingperl::debug;
            $sql_sth->finish();
        }
        $sql_sth = $sql_dbh->prepare($statement) or return undef;
        $sql_sth->execute() or return undef;
    } else {
        return &sql_exec($statement);
    }
}

# *--------------------------*
#
# @types = &sql_types;
# @ingtypes = &sql_ingtypes;
# @lengths = &sql_lengths;
# @nullable = &sql_nullable;
# @names = &sql_names;
#

sub sql_types       { $sql_sth ? @{$sql_sth->{'TYPE'}}     : undef; }
sub sql_ingtypes    { $sql_sth ? @{$sql_sth->{'SqlType'}}  : undef; }
sub sql_lengths     { $sql_sth ? @{$sql_sth->{'SqlLen'}}   : undef; }
sub sql_nullable    { $sql_sth ? @{$sql_sth->{'NULLABLE'}} : undef; }
sub sql_names       { $sql_sth ? @{$sql_sth->{'NAME'}}     : undef; }

# *----------------------------------------
#

tie $Ingperl::sql_version,   'Ingperl::var', 'version';
*sql_error = \$DBD::Ingres::errstr;
*sql_sqlcode = \$DBD::Ingres::err;
*sql_rowcount = \$DBI::rows;
$Ingperl::sql_readonly = 1;
$Ingperl::sql_showerrors = 0;
$Ingperl::sql_debug = 0;

# *----------------------------------------
#
# Library function to execute a select and return first row
sub sql_eval_row1{
	&sql(@_);
	return undef if $::sql_error;
	my(@row) = &sql_fetch;	# fetch one row
	&sql_close;					# close the cursor
	@row;
}

# Library function to execute a select and return first col
sub sql_eval_col1{
	&sql(@_);
	return undef if $::sql_error;
	my(@row, @col);
	while (@row = &sql_fetch){
		push(@col, $row[0]);
	}
	@col;
}

package Ingperl::var;
use Carp (qw[carp croak confess]);
use strict;

sub TIESCALAR {
    my ($class, $var) = @_;
    return bless \$var, $class;
}

sub FETCH {
    my $self = shift;
    confess "wrong type" unless ref $self;
    croak "too many arguments" if @_;
    if ($$self eq "version") {
        my ($sw) = DBI->internal;
        "\nIngperl emulation interface version $Ingperl::VERSION\n" .
        "Ingres driver $Ingperl::sql_drh->{'Version'}, ".
        "$Ingperl::sql_drh->{'Attribution'}\n" .
        $sw->{'Attribution'}. ", ".
        "version " . $sw->{'Version'}. "\n\n";
    }
    else {
        carp "unknown special variable $$self";
    }
}

sub STORE {
    carp "Can't modify ${$_[0]} special variable"
}

1;

__END__

=head1 NAME

Ingperl - Perl access to Ingres databases for old ingperl scripts

=head1 SYNOPSIS

     &sql('...');
     &sql_exec('...');
     @values = &sql_fetch;
     &sql_close;
     
     @types = &sql_types;
     @ingtypes = &sql_ingtypes;
     @lengths = &sql_lengths;
     @nullable = &sql_nullable;
     @names = &sql_names;
     
     $sql_version
     $sql_error
     $sql_sqlcode
     $sql_rowcount
     $sql_readonly
     $sql_showerrors
     $sql_debug
     
     @row1 = &sql_eval_row1('select ...');
     @col1 = &sql_eval_col1('select ...');

=head1 DESCRIPTION

Ingperl is an extension to Perl which allows access to Ingres databases.

The functions that make up the interface are described in the following
sections.

All functions return false or undefined (in the Perl sense)
to indicate failure.

The text in this document is largely unchanged from the original Perl4
ingperl documentation written by Tim Bunce (timbo@ig.co.uk).  Any
comments specific to the DBD::Ingres Ingperl emulation are prefixed by
B<DBD:>.

=head2 IngPerl Functions

Ingperl function, that access data.

=over 4

=item * sql

    &sql('...');

This functions should be used to

=over 4

=item connect to a database:

    &sql("connect database_name [-sqloptions]");
    
where sqloptions are the options defined in the manual
for the sql command.

For example:

    &sql("connect database_name identified by username -xw -Rrole -Ggroup -l");

Returns true else undef on error.

=item disconnect from a database:

    &sql("disconnect");

Note that ingperl will complain if a transaction is active.

You should &sql_exec 'commit' or 'rollback' before disconnect.

Returns true else undef on error (unlikely!).

Note that an ingres bug means that $sql_error will contain an
error message (E_LQ002E query issued outside of a session) even
though the disconnect worked ok.
B<DBD:> I<Must check if this is still the case...>

=item prepare a statement:

    &sql("select ...");

Returns true else undef on error.

If a non-select statement is prepared it will be executed at once.

B<DBD:> A non-select statement return rowcount ("0E0", 1, 2, ..),
while a select statement returns 0. This is the same value as
sqlca.sqlerrd[2].

This function cannot be used to prepare the following statements:

    call,
    get dbevent,
    inquire_sql,
    execute immediate,
    execute procedure,
    execute,
    prepare to commit,
    prepare,
    set.

Some of these can be performmed by the &sql_exec() function.

B<DBD:> This is no longer true! There is no difference between the
SQL-statements that C<&sql> and C<&sql_exec> can execute. C<&sql>
hands off all non-select statements to C<&sql_exec>.

=back

item * sql_exec

    &sql_exec('...');

Execute an sql statement immediately. This function should be used
to issue Commit, Rollback, Insert, Delete and Update statements.

Returns true else undef on error.

B<DBD:> A non-select statement return rowcount ("0E0", 1, 2, ..),
while a select statement returns 0. This is the same value as
sqlca.sqlerrd[2].

It is also often used to execute 'set' commands. For example:

    &sql_exec('set autocommit on');
    &sql_exec('set session with on_error=rollback transaction');
    &sql_exec('set lockmode readlock=nolock');
    &sql_exec('set qep');

This function cannot be used to prepare the following statements:

    call,
    get dbevent,
    inquire_sql,
    prepare to commit.

=item * sql_fetch

    @values = &sql_fetch;

Fetch the next record of data returned from the last prepared
select statement. When all records have been returned &sql_fetch
will close the select statement cursor and return an empty array.

For example:

    &sql('select * from iitables') || die $sql_error;
    while(@values = &sql_fetch){
        ...
    }

Null values are returned as undef elements of the array.

B<DBD:> C<&sql_fetch> can also be expressed as either
C<&sql("fetch")> or C<&sql_exec("fetch")> - to cater for
Ingperl 1.0 scripts!

=item * sql_close

    &sql_close;

This function needs to be called *only* if you do not use
C<&sql_fetch> to fetch *all* the records *and* you wish to close
the cursor as soon as possible (to release locks etc).
Otherwise ignore it. Always returns true.

=back

IngPerl Functions to describe the currently prepared statement.
These functions all return an array with one element for each
field in the query result.

=over 4

=item * sql_types

    @types = &sql_types;

Returns a list of sprintf type letters to indicate the generic
type if each field: 'd' (int), 'f' (float), or 's' (string).

=item * sql_ingtypes

    @ingtypes = &sql_ingtypes;

Returns a list of specific ingres type numbers:
     3 - date
     5 - money
    30 - integer
    31 - float
    20 - char
    21 - varchar

=item * sql_lengths

    @lengths = &sql_lengths;

Returns a list if ingres data type lengths.
For strings the length is the maximum width of the field.
For numbers it is the number of bytes used to store the
binary representation of the value, 1, 2, 4 or 8.

=item * sql_nullable

    @nullable = &sql_nullable;

Returns a list of boolean values (0 or 1's). A 1 indicates
that the corresponding field may return a null value.

=item * sql_names

    @names = &sql_names;

Returns a list of field names.

=back

=head2 IngPerl Variables

=over 4

=item * $sql_version (read only)

A constant string compiled into ingperl containing the major
and minor version numbers of ingperl, the patchlevel and the
date that the ingperl binary was built.

For example:
    ingperl 2.0 pl0 (built Apr  8 1994 13:17:03)

B<DBD:> The variable gives a similar output now, including the
Ingperl version and the DBD::Ingres version.

=item * $sql_error (read only)

Contains the error message text of the current ingres error.

Is empty if last statement succedded.

For example:
    print "$sql_error\n" if $sql_error;

=item * $sql_sqlcode (read only)

The current value of sqlda.sqlcode. Only of interest in more
sophisticated applications.

Typically 0, <0 on error,
100=no more rows, 700=message, 710=dbevent.

=item * $sql_rowcount (read only)

After a successful Insert, Delete, Update, Select, Modify,
Create Index, Create Table As Select or Copy this variable
holds the number of rows affected.

=item * $sql_readonly (default 1)

If true then prepared sql statements are given read only cursors
this is generally a considerable performance gain.

B<DBD:> Not implemented. All cursors are readonly - there is no way to
modify the value of a cursor element, therefore no reason not to make
the cursors readonly. The value of this variable was ignored already
in Ingperl 2.0.

=item * $sql_showerrors (default 0)

If true then ingres error and warning messages are printed by
ingperl as they happen. Very useful for testing.

B<DBD:> Not yet implemented. (Does anybody need it?)

=item * $sql_debug (default 0)

If ingperl has been compiled with -DINGPERL_DEBUG then setting this
variable true will enable debugging messages from ingperl internals.

B<DBD:> Not implemented. Setting the variable C<$debugdbi> to 3
or greater results in debug information from DBI and DBD::Ingres

=item * $sql_drh

B<DBD:> This variable is the DBI-internal driver handle for the
DBD::Ingres driver. It is of little or no use at present especially as
there is no provision for multiple connects yet).

=item * $sql_dbh

B<DBD:> This variable is the DBI database handle. It can be used to
add DBI/DBD statements to an old Ingperl script.

=item * $sql_sth

B<DBD:> This is the DBI statement handle for the current SELECT-statement
(if any).

=back

IngPerl Library Functions

=over 4

=item * sql_eval_row1

    @row1 = &sql_eval_row1('select ...');

Execute a select statement and return the first row.

=item * sql_eval_col1

    @col1 = &sql_eval_col1('select ...');

Execute a select statement and return the first column.

=head1 NOTES

The DBD::Ingres module has been modelled closely on Tim Bunce's
DBD::Oracle module and warnings that apply to DBD::Oracle and
the Oraperl emulation interface may also apply to the Ingperl
emulation interface.

Your mileage may vary.

=head1 WARNINGS


IngPerl comes with no warranty - it works for me - it may not
work for you. If it trashes your database I am not responsible!

This file should be included in all applications using ingperl
in order to help ensure that scripts will remain compatible with
new releases of ingperl.

B<DBD:> The following warning is taken (almost) verbatim from the
oraperl emulation module, but is also valid for Ingres.

The Ingperl emulation software shares no code with the original ingperl.
It is built on top the the new Perl5 DBI and DBD::Ingres
modules. These modules are still evolving. (One of the goals of
the Ingperl emulation software is to allow useful work to be done
with the DBI and DBD::Ingres modules whilst insulation users from
the ongoing changes in their interfaces.)

It is quite possible, indeed probable, that some differences in
behaviour will exist. This should be confined to error handling.

B<All> differences in behaviour which are not documented here should
be reported to ht@datani.dk and CC'd to dbi-users@fugue.com.


=head1 SEE ALSO

=over 2

=item Ingres Documentation

SQL Reference Guide

=item Books
Programming Perl by Larry Wall, Randal Schwartz and Tom Christiansen.
Learning Perl by Randal Schwartz.

=item Manual Pages

perl(1)

=back

=head1 AUTHORS

Formerly sqlperl by Ted Lemon.

Perl4 version developed and maintained by Tim Bunce,
<Tim.Bunce@ig.co.uk> Copyright 1994 Tim Bunce and Ted Lemon 

Ingperl emulation using DBD::Ingres by Henrik Tougaard <ht@datani.dk>

Perl by Larry Wall <lwall@netlabs.com>.

=cut


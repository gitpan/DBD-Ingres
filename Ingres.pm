# $Id: //depot/tilpasninger/dbd-ingres/Ingres.pm#14 $ $DateTime: 2003/07/03 17:04:55 $ $Revision: #14 $
#
#   Copyright (c) 1996-2000 Henrik Tougaard
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

require 5.004;

=head1 NAME

DBD::Ingres - DBI driver for Ingres database systems

=head1 SYNOPSIS

    $dbh = DBI->connect("DBI:Ingres:$dbname", $user, $options, {AutoCommit=>0})
    $sth = $dbh->prepare($statement)
    $sth = $dbh->prepare($statement, {ing_readonly=>1})
    $sth->execute
    @row = $sth->fetchrow
    $sth->finish
    $dbh->commit
    $dbh->rollback
    $dbh->disconnect
    and many more

=cut

# The POD text continues at the end of the file.
{
    package DBD::Ingres;

    use DBI 1.00;
    use DynaLoader ();
    @ISA = qw(DynaLoader);

    $VERSION = '0.38';
    my $Revision = substr(q$Change: 14429 $, 8)/100;

    bootstrap DBD::Ingres $VERSION;

    $err = 0;		# holds error code   for DBI::err
    $errstr = "";	# holds error string for DBI::errstr
    $drh = undef;	# holds driver handle once initialised

    sub driver{
        return $drh if $drh;
        my($class, $attr) = @_;

        $class .= "::dr";

        # not a 'my' since we use it above to prevent multiple drivers
        $drh = DBI::_new_drh($class, {
            'Name' => 'Ingres',
            'Version' => $VERSION,
            'Err'    => \$DBD::Ingres::err,
            'Errstr' => \$DBD::Ingres::errstr,
            'Attribution' => 'Ingres DBD by Henrik Tougaard',
            });

        $drh;
    }
    1;
}


{   package DBD::Ingres::dr; # ====== DRIVER ======
    use strict;

    sub connect {
        my($drh, $dbname, $user, $auth)= @_;

        # create a 'blank' dbh
        my $this = DBI::_new_dbh($drh, {
            'Name' => $dbname,
            'USER' => $user,
            'CURRENT_USER' => $user,
            });

        unless ($ENV{'II_SYSTEM'}) {
            warn("II_SYSTEM not set. Ingres may fail\n")
            	if $drh->{Warn};
        }
        unless (-d "$ENV{'II_SYSTEM'}/ingres") {
            warn("No ingres directory in \$II_SYSTEM. Ingres may fail\n")
            	if $drh->{Warn};
        }

        $user = "" unless defined $user;
        $auth = "" unless defined $auth;
        
        # Connect to the database..
        DBD::Ingres::db::_login($this, $dbname, $user, $auth)
            or return undef;

        $this;
    }

    sub data_sources {
        my ($drh) = @_;
        warn("\$drh->data_sources() not defined for Ingres\n")
            if $drh->{"warn"};
        "";
    }

}


{   package DBD::Ingres::db; # ====== DATABASE ======
    use strict;

    sub do {
        my($dbh, $statement, $attribs, @params) = @_;
        Carp::carp "DBD::Ingres::\$dbh->do() attribs unused\n" if $attribs;
        Carp::carp "DBD::Ingres::\$dbh->do() params unused\n" if @params;
	delete $dbh->{Statement};
        my $numrows = DBD::Ingres::db::_do($dbh, $statement);
	return $numrows;
    }

    sub prepare {
        my($dbh, $statement, $attribs)= @_;
	my $ing_readonly = defined($attribs->{ing_readonly}) ?
		$attribs->{ing_readonly} :
		scalar $statement !~ /select.*for\s+(?:deferred\s+|direct\s+)?update/is;

        # create a 'blank' sth
        my $sth = DBI::_new_sth($dbh, {
            Statement => $statement,
            ing_statement => $statement,
	    ing_readonly  => $ing_readonly, 
            });

        DBD::Ingres::st::_prepare($sth, $statement, $attribs)
            or return undef;

        $sth;
    }

    sub table_info {
        my ($dbh) = @_;
        my $sth = $dbh->prepare("
	  SELECT VARCHAR(null) AS TABLE_CAT, table_owner AS TABLE_SCHEM,	                 table_name, 'TABLE' AS TABLE_TYPE
	  FROM IITABLES                      
	  WHERE table_type='T'
          UNION
          SELECT null, table_owner, table_name, 'VIEW'
          FROM IITABLES
          WHERE table_type ='V'");
        return unless $sth;
        $sth->execute;
        $sth;
    }

    sub ping {
        my($dbh) = @_;
        # we know that DBD::Ingres prepare does a describe so this will
        # actually talk to the server and is this a valid and cheap test.
        return 1 if $dbh->prepare("select * from iitables");
        return 0;
    }

    sub type_info_all {
    	my ($dbh) = @_;
    	my $ti = [
    	    {   TYPE_NAME       => 0,
                DATA_TYPE       => 1,
                PRECISION       => 2,
                LITERAL_PREFIX  => 3,
                LITERAL_SUFFIX  => 4,
                CREATE_PARAMS   => 5,
                NULLABLE        => 6,
                CASE_SENSITIVE  => 7,
                SEARCHABLE      => 8,
                UNSIGNED_ATTRIBUTE=> 9,
                MONEY           => 10,
                AUTO_INCREMENT  => 11,
                LOCAL_TYPE_NAME => 12,
                MINIMUM_SCALE   => 13,
                MAXIMUM_SCALE   => 14,
    	    },
    	    [ 'SHORT',   DBI::SQL_SMALLINT, undef, "","",  undef,
    	        1, 0, 2, 0, 0,0,undef,0,0 ],
    	    [ 'INTEGER', DBI::SQL_INTEGER, undef, "","",   "size=1,2,4",
    	        1, 0, 2, 0, 0,0,undef,0,0 ],
    	    [ 'MONEY',   DBI::SQL_DECIMAL, undef, "","",   undef,
    	        1, 0, 2, 0, 1,0,undef,0,0 ],
    	    [ 'FLOAT',   DBI::SQL_INTEGER, undef, "","",   "size=4,8",
    	        1, 0, 2, 0, 0,0,undef,0,0 ],
    	    [ 'DATE',    DBI::SQL_DATE,    undef, "'","'", undef,
    	        1, 0, 3, 0, 0,0,undef,0,0 ],
    	    [ 'DECIMAL', DBI::SQL_DECIMAL, undef, "","",   "precision,scale",
    	        1, 0, 2, 0, 0,0,undef,0,0 ],
    	    [ 'VARCHAR', DBI::SQL_VARCHAR, undef, "'","'", "max length",
    	        1, 1, 3, 0, 0,0,undef,0,0 ],
    	    [ 'CHAR',    DBI::SQL_CHAR,    undef, "'","'", "length",
    	        1, 1, 3, 0, 0,0,undef,0,0 ],
    	];
    	return $ti;
    }
}


{   package DBD::Ingres::st; # ====== STATEMENT ======
    use strict;

}

1;

=head1 DESCRIPTION

DBD::Ingres is an extension to Perl which allows access to Ingres
databases. It is built on top of the standard DBI extension an
implements the methods that DBI require.

This document describes the differences between the "generic" DBD and
DBD::Ingres.

=head2 Extensions/Changes

=over 4

=item returned types

The DBI docs state that:

=over 2

Most data is returned to the perl script as strings (null values are
returned as undef).  This allows arbitrary precision numeric data to be
handled without loss of accuracy.  Be aware that perl may not preserve
the same accuracy when the string is used as a number.

=back

This is B<not> the case for Ingres.

Data is returned as it would be to an embedded C program:

=over 2

Integers are returned as integer values (IVs in perl-speak).

Floats and doubles are returned as numeric values (NVs in perl-speak).

Dates, moneys, chars, varchars and others are returned as strings
(PVs in perl-speak).

=back

=item get_dbevent

This non-DBI method calls C<GET DBEVENT> and C<INQUIRE_INGRES> to
fetch a pending database event. If called without argument a blocking
C<GET DBEVENT WITH WAIT> is called. A numeric argument results in a
call to C<GET DBEVENT WITH WAIT= :seconds>.

In a second step
C<INQUIRE_INGRES> is called to fetch the related information, wich is
returned as a reference to a hash with keys C<name>, C<database>,
C<text>, C<owner> and C<time>. The values are the C<dbevent>* values
received from Ingres. If no event was fetched, C<undef> is returned.
See F<t/event.t> for an example of usage.

  $event_ref = $dbh->func(10, 'get_dbevent')     # wait 10 secs at most
  $event_ref = $dbh->func('get_dbevent')         # blocks

  for (keys %$event_ref) {
    printf "%-20s = '%s'\n", $_, $event_ref->{$_};
  }

=item connect

    connect(dbi:Ingres:dbname[;options] [, user [, password]])

Options to the connection are passed in the datasource
argument. This argument should contain the database name possibly
followed by a semicolon and the database options.

Options must be given exactly as they would be given an ESQL-connect
statement, ie. separated by blanks.

The connect call will result in a connect statement like:

    CONNECT dbname IDENTIFIED BY user PASSWORD password OPTIONS=options

Eg.

=over 4

=item local database

       connect("mydb", "me", "mypassword")

=item with options and no password

       connect("mydb;-Rmyrole/myrolepassword", "me")

=item Ingres/Net database

       connect("thatnode::thisdb;-xw -l", "him", "hispassword")

=back

and so on.

B<Important>: The DBI spec defines that AutoCommit is B<ON> after connect.
This is the opposite of the normal Ingres default.

It is recommended that the C<connect> call ends with the attributes
C<{ AutoCommit => 0 }>.

If you dont want to check for errors after B<every> call use 
C<{ AutoCommit => 0, RaiseError => 1 }> instead. This will C<die> with
an error message if any DBI call fails.

=item do

    $dbh->do

This is implemented as a call to 'EXECUTE IMMEDIATE' with all the
limitations that this implies.

Placeholders and binding is not supported with C<$dbh-E<gt>do>.

=item ChopBlanks and binary data

Fetching of binary data is not possible if ChopBlanks is set. ChopBlanks
uses a \0 character internally to mark the end of the field, so returned
will be truncated at the first \0 character.

=item ing_readonly

Normally cursors are declared C<READONLY> 
to increase speed. READONLY cursors don't create
exclusive locks for all the rows selected; this is
the default.

If you need to update a row then you will need to ensure that either

=over 4

=item *

the C<select> statement contains an C<for update of> clause, or

= item *

the C<$dbh-E<gt>prepare> calls includes the attribute C<{ing_readonly =E<gt> 0}>.

=back

Eg.

   $sth = $dbh->prepare("select ....", {ing_readonly => 0});

will be opened for update, as will

   $sth = $dbh->prepare("select .... for direct update of ..")

while

   $sth = $dbh->prepare("select .... for direct update of ..",
                { ing_readonly => 1} );

will be opened C<FOR READONLY>.

When you wish to actually do the update, where you would normally put the
cursor name, you put:

    $sth->{CursorName}

instead,  for example:

    $sth = $dbh->prepare("select a,b,c from t for update of b");
    $sth->execute;
    $row = $sth->fetchrow_arrayref;
    $dbh->do("update t set b='1' where current of $sth->{CursorName}");

Later you can reexecute the statement without the update-possibility by doing:

    $sth->{ing_readonly} = 1;
    $sth->execute;

and so on. B<Note> that an C<update> will now cause an SQL error.

In fact the "FOR UPDATE" seems to be optional, ie you can update cursors even 
if their SELECT statements do not contain a C<for update> part.

If you wish to update such a cursor you B<must> include the C<ing_readonly>
attribute.

B<NOTE> DBD::Ingres version later than 0.19_1 have opened all cursors for
update. This change breaks that behaviour. Sorry if this breaks your code.

=item ing_statement

    $sth->{ing_statement}             ($)

Contains the text of the SQL-statement. Used mainly for debugging.

This is B<exactly> the same as the new and DBI-supported
C<$sth-E<gt>{Statement}>
and B<the use of C<$sth-E<gt>{ing_statement}> is depreceated>.

=item ing_types

    $sth->{ing_types}              (\@)

Returns an array of the "perl"-type of the return fields of a select
statement.

The types are represented as:

=over 4

=item 'i': integer

All integer types, ie. int1, int2 and int4.

These values are returned as integers. This should not cause loss of
precision as the internal Perl integer is at least 32 bit long.

=item 'f': float

The types float, float8 and money.

These values are returned as floating-point numbers. This may cause loss
of precision, but that would occur anyway whenever an application
referred to the data (all Ingres tools fetch these values as
floating-point numbers)

=item 's': string

All other supported types, ie. char, varchar, text, date etc.

=back

=item TYPE

    $sth->TYPE                       (\@)

See the DBI-docs for a description.

The ingres translations are:

=over 4

=item short -> DBI::SQL_SMALLINT

=item int -> DBI::SQL_INTEGER

=item float -> DBI::SQL_DOUBLE

=item double -> DBI::SQL_DOUBLE

=item char -> DBI::SQL_CHAR

=item text -> DBI::SQL_CHAR

=item varchar -> DBI::SQL_VARCHAR

=item date -> DBI::SQL_DATE

=item money -> DBI::SQL_DECIMAL

=item decimal -> DBI::SQL_DECIMAL

=back

Have I forgotten any?

=item ing_lengths

    $sth->{ing_lengths}              (\@)

Returns an array containing the lengths of the fields in Ingres, eg. an
int2 will return 2, a varchar(7) 7 and so on.

Note that money and date fields will have length returned as 0.

C<$sth-E<gt>{SqlLen}> is the same as C<$sth-E<gt>{ing_lengths}>,
but the use of it is depreceated.

See also the C$sth-E<gt>{PRECISION}> field in the DBI docs. This returns
a 'reasonable' value for all types including money and date-fields.

=item ing_sqltypes

    $sth->{ing_sqltypes}              (\@)

Returns an array containing the Ingres types of the fields. The types
are given as documented in the Ingres SQL Reference Manual.

All values are positive as the nullability of the field is returned in
C<$sth-E<gt>{NULLABLE}>.

See also the C$sth-E<gt>{TYPE}> field in the DBI docs.

=back

=head2 Not implemented

=over 4

=item state

    $h->state                (undef)

SQLSTATE is not implemented yet. It is planned for the (not so) near
future.

=item disconnect_all

Not implemented

=item commit and rollback invalidates open cursors

DBD::Ingres should warn when a commit or rollback is isssued on a $dbh
with open cursors.

Possibly a commit/rollback should also undef the $sth's. (This should
probably be done in the DBI-layer as other drivers will have the same
problems).

After a commit or rollback the cursors are all ->finish'ed, ie. they
are closed and the DBI/DBD will warn if an attempt is made to fetch
from them.

A future version of DBD::Ingres wil possibly re-prepare the statement.

This is needed for

=item Cached statements

A new feature in DBI that is not implemented in DBD::Ingres.

=item Procedure calls

It is not possible to call database procedures from DBD::Ingres.

A solution is underway for support for procedure calls from the DBI.
Until that is defined procedure calls can be implemented as a
DB::Ingres-specific function (like L<get_event>) if the need arises and
someone is willing to do it.

=item OpenIngres new features

The new features of OpenIngres are not (yet) supported in DBD::Ingres.

This includes BLOBS and spatial datatypes.

Support will be added when the need arises - if you need it you add it ;-)

=back

=head1 NOTES

I wonder if I have forgotten something?

=head1 SEE ALSO

The DBI documentation in L<DBI>.

=head1 AUTHORS

DBI/DBD was developed by Tim Bunce, <Tim.Bunce@ig.co.uk>, who also
developed the DBD::Oracle that is the closest we have to a generic DBD
implementation.

Henrik Tougaard, <htoug@cpan.org> developed the DBD::Ingres extension.

=cut

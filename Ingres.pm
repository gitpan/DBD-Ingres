#   $Id: Ingres.pm,v 2.114 1998/02/05 13:59:36 ht000 Exp $
#
#   Copyright (c) 1994,1995 Tim Bunce
#             (c) 1996 Henrik Tougaard
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

require 5.004;

=head1 NAME

DBD::Ingres - Ingres access interface for Perl5

=head1 SYNOPSIS

    $dbh = DBI->connect($dbname, $user, $options, 'Ingres')
    $sth = $dbh->prepare($statement)
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

    use DBI 0.91;
    use DynaLoader ();
    @ISA = qw(DynaLoader);

    $VERSION = '0.16';
    my $Revision = substr(q$Revision: 2.114 $, 10);

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
        Carp::carp "\$dbh->do() attribs unused\n" if $attribs;
	Carp::carp "\$dbh->do() params unused\n" if @params;
        DBD::Ingres::db::_do($dbh, $statement);
    }

    sub prepare {
        my($dbh, $statement, $attribs)= @_;

        # create a 'blank' sth
        my $sth = DBI::_new_sth($dbh, {
            'ing_statement' => $statement,
            });

        if ($statement !~ m/\b[Ss][Ee][Ll][Ee][Cc][Tt]\b/) {
	    $attribs->{"ing_outerjoin"} =
	      $statement =~ m/\b[Ll][Ee][Ff][Tt]\s*[Jj][Oo][Ii][Nn]\b/s ||
	      $statement =~ m/\b[Rr][Ii][Gg][Hh][Tt]\s*[Jj][Oo][Ii][Nn]\b/s ||
	      $statement =~ m/\b[Oo][Uu][Tt][Ee][Rr]\s*[Jj][Oo][Ii][Nn]\b/s
                 unless defined $attribs->{"ing_outerjoin"};
	}

        DBD::Ingres::st::_prepare($sth, $statement, $attribs)
            or return undef;

        $sth;
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

=item do

    $dbh->do

This is implemented as a call to 'EXECUTE IMMEDIATE' with all the
limitations that this implies.

Placeholders and binding is not supported with C<$dbh-E<gt>do>.

=item prepare and outerjoins

Due to a bug in OpenIngres 1.2 there is no way of determining which
fields in an 'outerjoin'select are nullable.

Therefore all fields in outerjoin selects are deemed NULLABLE.

DBD::Ingres tries to determine is a select statement is an outerjoin by
(primitively) parsing the select statement. You can override this
parsing by adding an attribute to the select-call:

    $dbh-E<gt>prepare($statement, %attribs)

C<$attribs{"ing_outerjoin"}> should contain true for outerjoins and false
otherwise.

Eg:

    $sth = $dbh->prepare("select...left join...", { ing_outerjoin => 1 });
    $sth = $dbh->prepare("select...", { ing_outerjoin => 0 });

=item ing_statement

    $sth->{ing_statement}             ($)

Contains the text of the SQL-statement. Used mainly for debugging.

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

=item ing_lengths

    $sth->{ing_lengths}              (\@)

Returns an array containing the lengths of the fields in Ingres, eg. an
int2 will return 2, a varchar(7) 7 and so on.

Note that money and date fields will have length returned as 0.

C<$sth-E<gt>{SqlLen}> is the same as C<$sth-E<gt>{ing_lengths}>,
but the use of it is depreceated.

=item ing_sqltypes

    $sth->{ing_sqltypes}              (\@)

Returns an array containing the Ingres types of the fields. The types
are given as documented in the Ingres SQL Reference Manual.

All values are positive as the nullability of the field is returned in
C<$sth-E<gt>{NULLABLE}>.

=back

=head2 Not implemented

=over 4

=item state

    $h->state                (undef)

SQLSTATE is not implemented yet. It is planned for the (not so) near
future.

=item ping

    $dbh->ping;

Not yet implemented - on the ToDo list.

=item updateable cursors

It should be possible to do something like this:

    $sth = $dbh->prepare("select a,b,c from t", ing_update => "b, c");
    $sth->execute;
    $row = $sth->fetchrow_arrayref;
    $dbh->do("update t set b='1' where current of $sth->{CursorName}");

The exact syntax is open for discussion (you implement => you decide!).

=item disconnect_all

Not implemented

=item commit and rollback invalidates open cursors

DBD::Ingres should warn when a commit or rollback is isssued on a $dbh
with open cursors.

Possibly a commit/rollback should also undef the $sth's. (This should
probably be done in the DBI-layer as other drivers will have the same
problems).

=item Procedure calls

It is not possible to call database procedures from DBD::Ingres.

A solution is underway for support for procedure calls from the DBI.
Until that is defined procedure calls can be implemented as a
DB::Ingres-specific function (like L<get_event>) if the need arises and
someone is willing to do it.

=item OpenIngres new features

The new features of OpenIngres are not (yet) supported in DBD::Ingres.

This includes BLOBS, decimal datatype and spatial datatypes.

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

Henrik Tougaard, <ht@datani.dk> developed the DBD::Ingres extension.

=cut

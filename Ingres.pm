#   $Id: Ingres.pm,v 2.104 1997/09/15 07:45:21 ht000 Exp $
#
#   Copyright (c) 1994,1995 Tim Bunce
#             (c) 1996 Henrik Tougaard
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

require 5.00390;

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

    use DBI ();
    use DynaLoader ();
    @ISA = qw(DynaLoader);

    $VERSION = '0.05_93';
    my $Revision = substr(q$Revision: 2.104 $, 10);

    require_version DBI 0.82;

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

        # Connect to the database..
        DBD::Ingres::db::_login($this, $dbname, $user, $auth)
            or return undef;

        $this;
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
        my($dbh, $statement, @attribs)= @_;

        # create a 'blank' sth
        my $sth = DBI::_new_sth($dbh, {
            'ing_statement' => $statement,
            });

        DBD::Ingres::st::_prepare($sth, $statement, @attribs)
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

=head2 Not implemented

=over 4

=item state

    $h->state                (undef)

SQLSTATE is not implemented yet. It is planned for the (not so) near
future.

=item ping

    $dbh->ping;

Not yet implemented - on the ToDo list.

=item OpenIngres new features

The new features of OpenIngres are not (yet) supported in DBD::Ingres.

This includes BLOBS, decimal datatype and spatial datatypes.

Support will be added when the need arises - if you need it you add it ;-)

=back

=head2 Extensions/Changes

=over 4

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

    $dbh-E<gt>do

This is implemented as a call to 'EXECUTE IMMEDIATE' with all the
limitations that this implies.

Placeholders and binding is not supported with C<$dbh-E<gt>do>.

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

Note that money and date will have length returned as 0.

=item ing_types

    $sth->{ing_sqltypes}              (\@)

Returns an array containing the Ingres types of the fields. The types
are given as documented in the Ingres SQL Reference Manual.

=back

=head1 NOTES

I wonder if I have forgotten something?

=head1 SEE ALSO

The DBI documentation (at the end of DBI.pm).

=head1 AUTHORS

DBI/DBD was developed by Tim Bunce, <Tim.Bunce@ig.co.uk>, who also
developed the DBD::Oracle that is the closest we have to a generic DBD
implementation.

Henrik Tougaard, <ht@datani.dk> developed the DBD::Ingres extension.
=cut

# create table testtab
# ( col1 integer not null primary key,
#   col2 char(2)
# );
use DBI qw(:sql_types);
our $num_test;

$verbose = 1 unless defined $verbose;
my $testtable = "testhththt";

my $t = 0;
sub ok ($$$;$) {
    my ($n, $ok, $expl, $warn) = @_;
    ++$t;
    die "sequence error, expected $n but actually $t"
	if $n and $n!=$t;
    print "Testing $expl\n" if $verbose;
    ($ok) ? print "ok $t\n" : print "not ok $t\n";
    if (!$ok && $warn) {
	$warn = $DBI::errstr if $warn eq '1';
	$warn = "" unless $warn;
	warn "$expl $warn\n";
    }
}

sub openingres {
    # Returns whether this is an OpenIngres installation or not -
    # should possibly be set from Makefile.PL ??
    # better tests are needed. This fails on OpenVMS!
    $ENV{"OPENINGRES"} || (-f "$ENV{II_SYSTEM}/ingres/lib/libcompat.1.so");
}

sub get_dbname {
    # find the name of a database on which test are to be performed
    # Should ask the user if it can't find a name.
    $dbname = $ENV{DBI_DBNAME} || $ENV{DBI_DSN};
    unless ($dbname) {
        warn "No databasename specified";
        print "1..0\n";
        exit 0;
    }
    $dbname = "dbi:Ingres:$dbname" unless $dbname =~ /^dbi:Ingres/;
    $dbname;
}

sub connect_db($$) {
    # Connects to the database.
    # If this fails everything else is in vain!
    my ($num_test, $dbname) = @_;

    print "Testing: DBI->connect('$dbname'):\n"
 	if $verbose;
    my $dbh = DBI->connect($dbname, "", "",
	{ AutoCommit => 0,
	  PrintError => !$ENV{HARNESS_ACTIVE},
        });
    $dbh->{ChopBlanks} = 1;
    if ($dbh) {
        print("1..$num_test\nok 1\n");
    } else {
        print("1..0\n");
        warn("Cannot connect to database $dbname: $DBI::errstr\n");
        exit 0;
    }
    $dbh;
}

my $dbname = get_dbname;
my $openingres = openingres;
if (!$openingres) {
    print "1..0 # Only on OpenIngres or newer\n";
    exit(0);
}
my $dbh = connect_db($num_test, $dbname);
$t = 1;

ok(2, $dbh->do("CREATE TABLE $testtable( col1 integer not null primary key, col2 char(2))"),
     "Create table", 1);

ok(0, $sth = $dbh->prepare("insert into $testtable values (?,?)"), "prepare", 1);

ok(0, $sth->bind_param(1,1,SQL_INTEGER), "bind 1-1", 1);
ok(0, $sth->bind_param(2,'abc',SQL_CHAR), "bind 1-2", 1);
ok(0, $sth->execute(), "execute 1", 1);

                        # use same key now, so an error should raise....
ok(0, $sth->bind_param(1,1,SQL_INTEGER), "bind 2-1", 1);
ok(0, $sth->bind_param(2,'def',SQL_CHAR), "bind 2-2", 1);
ok(0, !$sth->execute(), "execute 2", 1);

ok(0, $sth->bind_param(1,2,SQL_INTEGER), "bind 3-1");
ok(0, $sth->bind_param(2,'abc',SQL_CHAR), "bind 3-2");
ok(0, $sth->execute(), "execute 3");

ok(0, $dbh->do( "DROP TABLE $testtable" ), "Dropping table", 1);
ok(0, $dbh->rollback(), "rollback()", 1);
ok(0, $dbh->disconnect(), 1);

BEGIN { $num_test = 15; }

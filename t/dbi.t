use DBI qw(:sql_types);
use vars qw($num_test);

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
    my $dbh = DBI->connect($dbname, "", "", "Ingres", {AutoCommit => 0});
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
my $dbh = connect_db($num_test, $dbname);
$t = 1;

ok(2, $dbh->do("CREATE TABLE $testtable(id INTEGER4 not null, name CHAR(64))"),
     "Create table", 1);
ok(0, $dbh->do("INSERT INTO $testtable VALUES(1, 'Alligator Descartes')"),
     "Insert(value)", 1);
ok(0, $dbh->do("DELETE FROM $testtable WHERE id = 1"),
     "Delete", 1);

ok(0, $cursor = $dbh->prepare("SELECT * FROM $testtable WHERE id = 1"),
     "prepare(Select)", 1);
ok(0, $cursor->execute, "Execute(select)", 1);
$row = $cursor->fetchrow_arrayref;
ok(0, !defined($row), "Fetch from empty table",
     "Row is returned as: ".($row ? DBI->neat_list($row) : "''"));
ok(0, $cursor->finish, "Finish(select)", 1);

ok(0, $cursor->{NAME}[0] eq "id", "Column 1 name",
     "should be 'id' is '$cursor->{NAME}[0]'");
my $null = join  ':', map int($_), @{$cursor->{NULLABLE}};
ok(0, $null eq '0:1',
     "Column nullablility",
     "Should be '0:1' is '$null'");
ok(0, $cursor->{TYPE}[0] == SQL_INTEGER,
     "Column TYPE",
     "should be '".SQL_INTEGER."' is '$cursor->{TYPE}[0]'");
# Possibly needs test on ing_type, ing_ingtype, ing_lengths..


ok(0, $sth = $dbh->prepare("INSERT INTO $testtable(id, name) VALUES(?, ?)"),
     "Prepare(insert with ?)", 1);
ok(0, $sth->bind_param(1, 1, {TYPE => SQL_INTEGER}),
     "Bind param 1 as 1", 1);
ok(0, $sth->bind_param(2, "Henrik Tougaard", {TYPE => SQL_CHAR}),
     "Bind param 2 as string" ,1);
ok(0, $sth->execute, "Execute(insert) with params", 1);
ok(0, $sth->execute( 2, 'Aligator Descartes'),
     "Re-executing(insert)with params", 1);

ok(0, $cursor->execute, "Re-execute(select)", 1);
ok(0, $row = $cursor->fetchrow_arrayref, "Fetching row", 1); 
ok(0, $row->[0] == 1, "Column 1 value",
     "Should be '1' is '$row->[0]'");
ok(0, $row->[1] eq 'Henrik Tougaard', "Column 2 value",
     "Should be 'Henrik Tougaard' is '$row->[1]'");
ok(0, !defined($row = $cursor->fetchrow_arrayref),
     "Fetching past end of data", 
     "Row is returned as: ".($row ? DBI->neat_list($row) : "''"));
ok(0, $cursor->finish, "finish(cursor)", 1);

ok(0, $dbh->do(
        "UPDATE $testtable SET id = 3 WHERE name = 'Alligator Descartes'"),
     "do(Update) one row", 1);
ok(0, my $numrows = $dbh->do( "UPDATE $testtable SET id = id+1" ),
     "do(Update) all rows", 1);
ok(0, $numrows == 2, "Number of rows", "should be '2' is '$numrows'");

ok(0, $dbh->do( "DROP TABLE $testtable" ), "Dropping table", 1);
ok(0, $dbh->rollback, "Rolling back", 1);
#   What else??
ok(0, !$dbh->{AutoCommit}, "AutoCommit switched off upon connect time", 1);
$dbh->{AutoCommit}=1;
ok(0, $dbh->{AutoCommit}, "AutoCommit switched on", 1);

ok(0, $dbh->disconnect, "Disconnecting", 1);

$dbh = DBI->connect("$dbname") or die "not ok 999 - died due to $DBI::errstr";
#print "Autocommit = $dbh->{AutoCommit}\n";
#ok(0, $dbh->{AutoCommit}, "AutoCommit switched on by default", 1);
$dbh and $dbh->{AutoCommit}=0;
ok(0, !$dbh->{AutoCommit}, "AutoCommit switched off explicitly", 1);
$dbh and $dbh->disconnect;

# Missing:
#   test of ChopBlanks etc.
#           outerjoin and nullability
#   what else?

BEGIN { $num_test = 31; }


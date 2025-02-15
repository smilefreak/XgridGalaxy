use strict;
use warnings;

use DBI;
use Getopt::Long;

use Bio::EnsEMBL::Variation::Utils::Config qw(
    @ATTRIB_TYPES
    @ATTRIB_SETS
    %ATTRIBS
);

my $host;
my $port;
my $user;
my $pass;
my $db;
my $help;

GetOptions(
    "host=s"    => \$host,
    "port=i"    => \$port,
    "user=s"    => \$user,
    "pass=s"    => \$pass,
    "db=s"      => \$db,
    "help|h"    => \$help,
);

unless ($host && $user && $db) {
    print "Missing required parameter...\n" unless $help;
    $help = 1;
}

if ($help) {
    print "Usage: $0 --host <host> --port <port> --user <user> --pass <pass> --db <database> --help > attrib_entries.sql\n";
    exit(0);
}

my %attrib_ids;
my $attrib_type_ids;

my $last_attrib_type_id = 0;
my $last_attrib_id      = 0;
my $last_attrib_set_id  = 0;

my $attrib_type_fmt = 
    q{INSERT IGNORE INTO attrib_type (attrib_type_id, code, name, description) VALUES (%d, %s, %s, %s);};
my $attrib_fmt = 
    q{INSERT IGNORE INTO attrib (attrib_id, attrib_type_id, value) VALUES (%d, %d, '%s');};
my $set_fmt = 
    q{INSERT IGNORE INTO attrib_set (attrib_set_id, attrib_id) VALUES (%d, %d);};


# prefetch existing 

my $dbh = DBI->connect(
    "DBI:mysql:database=$db;host=$host;port=$port",
    $user,
    $pass,
);

my $existing_attrib_type;
my $existing_attrib;
my $existing_set;

my $get_types_sth = $dbh->prepare(qq{
    SELECT code, attrib_type_id FROM attrib_type
});

$get_types_sth->execute;

while (my ($code, $id) = $get_types_sth->fetchrow_array) {
    $existing_attrib_type->{$code} = $id;
    $last_attrib_type_id = $id if $id > $last_attrib_type_id;
}

my $get_attribs_sth = $dbh->prepare(qq{
    SELECT attrib_type_id, value, attrib_id FROM attrib
});

$get_attribs_sth->execute;

while (my ($type_id, $value, $id) = $get_attribs_sth->fetchrow_array) {
    $existing_attrib->{$type_id}->{$value} = $id;
    $last_attrib_id = $id if $id > $last_attrib_id;
}

my $get_sets_sth = $dbh->prepare(qq{
    SELECT attrib_set_id, attrib_id FROM attrib_set
});

$get_sets_sth->execute;

while (my ($set_id, $attrib_id) = $get_sets_sth->fetchrow_array) {
    $existing_set->{$set_id}->{$attrib_id} = 1;

    $last_attrib_set_id = $set_id if $set_id > $last_attrib_set_id;
}

sub get_attrib_type_id {
    my ($code) = @_;

    my $id = $existing_attrib_type->{$code};

    unless (defined $id) {
        $id = ++$last_attrib_type_id;
        $existing_attrib_type->{$code} = $id
    }

    return $id;
}

sub get_attrib_id {
    my ($type_id, $value) = @_;

    my $id = $existing_attrib->{$type_id}->{$value};

    unless (defined $id) {
        $id = ++$last_attrib_id;
        $existing_attrib->{$type_id}->{$value} = $id
    }

    return $id;
}

sub get_attrib_set_id {

    my $new_set = { map {$_ => 1} @_ };

    my $is_subset = sub {
        my ($s1, $s2) = @_;
        for my $e (keys %$s2) {
            return 0 unless $s1->{$e};
        }
        return 1;
    };

    SET : for my $set_id (keys %$existing_set) {
        my $set = $existing_set->{$set_id};
        if ($is_subset->($set, $new_set) || $is_subset->($new_set, $set)) {
            return $set_id;
        }
    }
  
    $last_attrib_set_id++;

    map { $existing_set->{$last_attrib_set_id}->{$_} = 1 } keys %$new_set;

    return $last_attrib_set_id;
}

my $SQL;

# first define the attrib type entries

for my $attrib_type (@ATTRIB_TYPES) {
    
    my $code        = delete $attrib_type->{code} or die "code required for attrib_type";
    my $name        = delete $attrib_type->{name};
    my $description = delete $attrib_type->{description};
    
    my $attrib_type_id = get_attrib_type_id($code);

    die "Unexpected entries in attrib_type definition: ".(join ',', keys %$attrib_type)
        if keys %$attrib_type;

    $SQL .= sprintf($attrib_type_fmt, 
        $attrib_type_id, 
        "'$code'",
        ($name ? "'$name'" : "''"),
        ($description ? "'$description'" : 'NULL'),
    )."\n";

    $attrib_type_ids->{$code} = $attrib_type_id;
}

# second, take the entries from the ATTRIBS and add them as single-element hashes to the @ATTRIB_SETS array
while (my ($type,$values) = each(%ATTRIBS)) {
    
    map {push(@ATTRIB_SETS,{$type => $_})} @{$values};
} 

# third, loop over the ATTRIB_SETS array and add attribs and assign them to attrib_sets as necessary
for my $set (@ATTRIB_SETS) {
    
    #�Keep the attrib_ids
    my @attr_ids;
    
    # Iterate over the type => value entries in the set
    while (my ($type,$value) = each(%{$set})) {
        
        # Lookup the attrib_type
        my $attrib_type_id = $attrib_type_ids->{$type} or next;
        
        # insert a new attrib if we haven't seen it before
        my $attrib_id = $attrib_ids{$type . "_" . $value};
        
        unless (defined($attrib_id)) {
            $attrib_id = get_attrib_id($attrib_type_id, $value);
            $SQL .= sprintf($attrib_fmt, $attrib_id, $attrib_type_id, $value)."\n"; 
            $attrib_ids{$type . "_" . $value} = $attrib_id;
        }
        
        push(@attr_ids,$attrib_id);   
    }
    
    # If the set had more than one attribute, group them into a set
    if (scalar(@attr_ids) > 1) {
        
        my $attrib_set_id = get_attrib_set_id(@attr_ids);
        map {$SQL .= sprintf($set_fmt, $attrib_set_id, $_)."\n"} @attr_ids;
        
    }
}

print $SQL . "\n";



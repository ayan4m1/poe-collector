#!/usr/bin/perl

# This program uses the data mined information from the ggpk file posted
# at poedb.tw to create the %gearBaseType hash of all known
# base item names
#
# It may break at any time if there are changes to the poedb.tw format
#
# The output of this can be copy/pasted into subs/sub.itemBaseTypes.pl to
# update that hash

use strict;
use warnings;

use Cwd;
use Encode;
use JSON::XS;
use HTML::Tree;
use LWP::UserAgent;

# Grab the list of item types from poedb.tw
my $baseurl = "http://poedb.tw/us/item.php";

# Results stored here
my %types = ();

# Hash of types to convert - the key is the poedb title, the value is the baseItemType we will use
$types{"Claws"} = "Claw";
$types{"Daggers"} = "Dagger";
$types{"Wands"} = "Wand";
$types{"One Hand Swords"} = "Sword";
$types{"Thrusting One Hand Swords"} = "Sword";
$types{"One Hand Axes"} = "Axe";
$types{"One Hand Maces"} = "Mace";
$types{"Sceptres"} = "Sceptre";
$types{"Bows"} = "Bow";
$types{"Staves"} = "Staff";
$types{"Two Hand Swords"} = "Sword";
$types{"Two Hand Axes"} = "Axe";
$types{"Two Hand Maces"} = "Mace";
$types{"Fishing Rods"} = "Fishing Rod";

$types{"Gloves"} = "Gloves";
$types{"Boots"} = "Boots";
$types{"Body Armours"} = "Body";
$types{"Helmets"} = "Helmet";
$types{"Shields"} = "Shield";

$types{"Amulets"} = "Amulet";
$types{"Rings"} = "Ring";
$types{"Quivers"} = "Quiver";
$types{"Belts"} = "Belt";
$types{"Jewel"} = "Jewel";

$types{"Life Flasks"} = "Flask";
$types{"Mana Flasks"} = "Flask";
$types{"Hybrid Flasks"} = "Flask";
$types{"Utility Flasks"} = "Flask";
$types{"Maps"} = "Map";
$types{"Map Fragments"} = "Map Fragment";

$types{"Divination Card"} = "Card";

my @content = split(/\n/, GetURL("$baseurl"));
foreach my $line (@content) {
  if ($line =~ /<li><a  href=\'item.php\?cn=(\S+)\'>(.*?)<\/a>/) {
    my $endurl = $1;
    my $dbtype = $2;
    next unless ($types{"$dbtype"});
    &ProcessURL("$baseurl\?cn=$endurl", $types{"$dbtype"});
  }
}

my $cwd = cwd();
my $jsonpath = "${cwd}/../data/BaseTypes.json";
my $jsonout = JSON::XS->new->utf8->pretty->canonical->encode(\%types);
open(my $jsonh, '>', $jsonpath) or die("can't write to BaseTypes.json: $!");
print $jsonh $jsonout;
close $jsonh;

exit;

# == Subroutines =====================

sub GetURL {
  my $url = $_[0];

  my $ua = LWP::UserAgent->new;
  my $can_accept = HTTP::Message::decodable;
  my $response = $ua->get("$url",'Accept-Encoding' => $can_accept);
  my $content = $response->decoded_content;

  return($content);
}

sub ProcessURL {
  my $content = &GetURL("$_[0]");
  my $type = $_[1];
  my @content = split(/<tr>/, $content);
  foreach my $line (@content) {
    if ($line =~ /<td><a href=\'item.php\?n=(.*?)\'>(.*?)<\/a>/) {
      $types{"$2"} = "$type";
    }
  }
}

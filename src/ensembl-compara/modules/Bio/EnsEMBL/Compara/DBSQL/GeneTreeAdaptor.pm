=head1 LICENSE

  Copyright (c) 1999-2011 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

   http://www.ensembl.org/info/about/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=head1 NAME

Bio::EnsEMBL::Compara::DBSQL::GeneTreeAdaptor

=head1 SYNOPSIS

=head1 DESCRIPTION

GeneTreeAdaptor - Generic adaptor for a tree, later derived as ProteinTreeAdaptor or NCTreeAdaptor

=head1 INHERITANCE TREE

  Bio::EnsEMBL::Compara::DBSQL::GeneTreeAdaptor
  +- Bio::EnsEMBL::Compara::DBSQL::NestedSetAdaptor

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Compara::DBSQL::GeneTreeAdaptor;

use strict;
use Bio::EnsEMBL::Compara::GeneTreeNode;
use Bio::EnsEMBL::Compara::GeneTreeMember;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use Bio::EnsEMBL::Compara::DBSQL::MemberAdaptor;
use base ('Bio::EnsEMBL::Compara::DBSQL::NestedSetAdaptor');

###########################
# FETCH methods
###########################

=head2 fetch_all

  Arg[1]     : [optional] int clusterset_id (def. 1)
  Example    : $all_trees = $proteintree_adaptor->fetch_all(1);

  Description: Fetches from the database all the protein trees
  Returntype : arrayref of Bio::EnsEMBL::Compara::GeneTreeNode
  Exceptions :
  Caller     :

=cut

sub fetch_all {
  my ($self, $clusterset_id) = @_;
  $clusterset_id = 1 if ! defined $clusterset_id;
  my $table = $self->tables->[0]->[1];
  my $constraint = "WHERE ${table}.node_id = ${table}.root_id and ${table}.clusterset_id = ${clusterset_id}";
  my $nodes = $self->_generic_fetch($constraint);
  return $nodes;
}

=head2 fetch_by_Member_root_id

  Arg[1]     : Bio::EnsEMBL::Compara::Member
  Arg[2]     : [optional] int clusterset_id (def. 1)
  Example    : $protein_tree = $proteintree_adaptor->fetch_by_Member_root_id($member);

  Description: Fetches from the database the protein_tree that contains the
               member. If you give it a clusterset id of 0 this will cause
               the search span across all known clustersets.
  Returntype : Bio::EnsEMBL::Compara::GeneTreeNode
  Exceptions :
  Caller     :

=cut


sub fetch_by_Member_root_id {
  my ($self, $member, $clusterset_id) = @_;
  $clusterset_id = 1 if ! defined $clusterset_id;

  my $root_id = $self->gene_member_id_is_in_tree($member->gene_member_id || $member->member_id);

  return undef unless (defined $root_id);
  my $aligned_member = $self->fetch_AlignedMember_by_member_id_root_id
    (
    $self->_get_canonical_Member($member)->member_id,
     $clusterset_id);
  return undef unless (defined $aligned_member);
  my $node = $aligned_member->subroot;
  return undef unless (defined $node);
  my $gene_tree = $self->fetch_node_by_node_id($node->node_id);

  return $gene_tree;
}


=head2 fetch_by_gene_Member_root_id

=cut

sub fetch_by_gene_Member_root_id {
  my ($self, $member, $clusterset_id) = @_;
  $clusterset_id = 1 if ! defined $clusterset_id;

  my $root_id = $self->gene_member_id_is_in_tree($member->member_id);
  return undef unless (defined $root_id);
  my $gene_tree = $self->fetch_node_by_node_id($root_id);

  return $gene_tree;
}


=head2 fetch_AlignedMember_by_member_id_root_id

  Arg[1]     : int member_id of a peptide member (longest translation)
  Arg[2]     : [optional] int clusterset_id (def. 0)
  Example    :

      my $aligned_member = $proteintree_adaptor->
                            fetch_AlignedMember_by_member_id_root_id
                            (
                             $member->get_canonical_peptide_Member->member_id
                            );

  Description: Fetches from the database the protein_tree that contains the member_id
  Returntype : Bio::EnsEMBL::Compara::GeneTreeMember
  Exceptions :
  Caller     :

=cut

sub fetch_AlignedMember_by_member_id_root_id {
  my ($self, $member_id, $clusterset_id) = @_;

  my $constraint = "WHERE tm.member_id = $member_id and m.member_id = $member_id";
  $constraint .= " AND t.clusterset_id = $clusterset_id" if($clusterset_id and $clusterset_id>0);
  my $final_clause = "order by tm.node_id desc";
  $self->final_clause($final_clause);
  my ($node) = @{$self->_generic_fetch($constraint)};
  return $node;
}

# This is experimental -- use at your own risk
sub fetch_first_shared_ancestor_indexed {
  my $self = shift;
  my $node1 = shift;
  my $node2 = shift;

  my $root_id1 = $node1->_root_id; # This depends on the new root_id field in the schema
  my $root_id2 = $node2->_root_id;

  return undef unless ($root_id1 eq $root_id2);

  my $left_node_id1 = $node1->left_index;
  my $left_node_id2 = $node2->left_index;

  my $right_node_id1 = $node1->right_index;
  my $right_node_id2 = $node2->right_index;

  my $min_left;
  $min_left = $left_node_id1 if ($left_node_id1 < $left_node_id2);
  $min_left = $left_node_id2 if ($left_node_id2 < $left_node_id1);

  my $max_right;
  $max_right = $right_node_id1 if ($right_node_id1 > $right_node_id2);
  $max_right = $right_node_id2 if ($right_node_id2 > $right_node_id1);

  my $constraint = "WHERE t.root_id=$root_id1 AND left_index < $min_left";
  $constraint .= " AND right_index > $max_right";
  $constraint .= " ORDER BY (right_index-left_index) LIMIT 1";

  my $ancestor = $self->_generic_fetch($constraint)->[0];

  return $ancestor;
}


=head2 fetch_AlignedMember_by_member_id_mlssID

  Arg[1]     : int member_id of a peptide member (longest translation)
  Arg[2]     : [optional] int clusterset_id (def. 0)
  Example    :

      my $aligned_member = $proteintree_adaptor->
                            fetch_AlignedMember_by_member_id_mlssID
                            (
                             $member->get_canonical_peptide_Member->member_id, $mlssID
                            );

  Description: Fetches from the database the protein_tree that contains the member_id
  Returntype : Bio::EnsEMBL::Compara::GeneTreeMember
  Exceptions :
  Caller     :

=cut


sub fetch_AlignedMember_by_member_id_mlssID {
  my ($self, $member_id, $mlss_id) = @_;

  my $constraint = "WHERE tm.member_id = $member_id and m.member_id = $member_id";
  $constraint .= " AND tm.method_link_species_set_id = $mlss_id" if($mlss_id and $mlss_id>0);
  my ($node) = @{$self->_generic_fetch($constraint)};
  return $node;
}


sub gene_member_id_is_in_tree {
  my ($self, $member_id) = @_;

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->prepare("SELECT ptm1.root_id FROM member m1, ".$prefix."_tree_member ptm1 WHERE ptm1.member_id=m1.member_id AND m1.gene_member_id=? LIMIT 1");
  $sth->execute($member_id);
  my($root_id) = $sth->fetchrow_array;

  if (defined($root_id)) {
    return $root_id;
  } else {
    return undef;
  }
}

sub fetch_all_AlignedMembers_by_root_id {
  my ($self, $root_id) = @_;

  my $constraint = "WHERE tm.root_id = $root_id";
  my $nodes = $self->_generic_fetch($constraint);
  return $nodes;

}

###########################
# STORE methods
###########################


sub store {
  my ($self, $node) = @_;

  unless($node->isa('Bio::EnsEMBL::Compara::GeneTreeNode')) {
    throw("set arg must be a [Bio::EnsEMBL::Compara::GeneTreeNode] not a $node");
  }

  $self->store_node($node);

  # recursively do all the children
  my $children = $node->children;
  foreach my $child_node (@$children) {
    $child_node->clusterset_id($node->clusterset_id) unless (defined($child_node->clusterset_id));
    $self->store($child_node);
  }

  return $node->node_id;
}

sub store_node {
  my ($self, $node) = @_;

  unless($node->isa('Bio::EnsEMBL::Compara::GeneTreeNode')) {
    throw("set arg must be a [Bio::EnsEMBL::Compara::GeneTreeNode] not a $node");
  }

  if($node->adaptor and
     $node->adaptor->isa('Bio::EnsEMBL::Compara::DBSQL::GeneTreeAdaptor') and
     $node->adaptor eq $self)
  {
    #already stored so just update
    return $self->update_node($node);
  }

  my $parent_id = 0; my $root_id = 0; my $clusterset_id = undef;
  if($node->parent) {
    $parent_id = $node->parent->node_id;
    if (ref($node->node_id)) {
      # We got here because we haven't stored this node and so it
      # doesn't have a node_id, returning a hashref (node object) for node_id
      # instead of an integer
      $root_id = $node->root->node_id;
    } else {
      $root_id = $node->subroot->node_id;
    }
  }
  $clusterset_id = $node->clusterset_id || 1;
  #printf("inserting parent_id = %d, root_id = %d\n", $parent_id, $root_id);

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->prepare("INSERT INTO ".$prefix."_tree_node
                             (parent_id,
                              root_id,
                              clusterset_id,
                              left_index,
                              right_index,
                              distance_to_parent)  VALUES (?,?,?,?,?,?)");
  $sth->execute($parent_id, $root_id, $clusterset_id, $node->left_index, $node->right_index, $node->distance_to_parent);

  $node->node_id( $sth->{'mysql_insertid'} );
  #printf("  new node_id %d\n", $node->node_id);
  $node->adaptor($self);
  $sth->finish;

  if($node->isa('Bio::EnsEMBL::Compara::GeneTreeMember')) {
    $sth = $self->prepare("INSERT ignore INTO ".$prefix."_tree_member
                               (node_id,
                                root_id,
                                member_id,
                                method_link_species_set_id,
                                cigar_line)  VALUES (?,?,?,?,?)");
    $sth->execute($node->node_id, $root_id, $node->member_id, $node->method_link_species_set_id, $node->cigar_line);
    $sth->finish;
  }
  return $node->node_id;
}

sub update_node {
  my ($self, $node) = @_;

  unless($node->isa('Bio::EnsEMBL::Compara::GeneTreeNode')) {
    throw("set arg must be a [Bio::EnsEMBL::Compara::GeneTreeNode] not a $node");
  }

  my $parent_id = 0; my $root_id = 0; my $clusterset_id = undef;
  if($node->parent) {
    $parent_id = $node->parent->node_id;
    if (ref($node->node_id)) {
      # We got here because we haven't stored this node and so it
      # doesn't have a node_id, returning a hashref (node object) for node_id
      # instead of an integer
      $root_id = $node->root->node_id;
    } else {
      $root_id = $node->subroot->node_id;
    }
    $clusterset_id = $node->clusterset_id || 1;
  }

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->prepare("UPDATE ".$prefix."_tree_node SET
                            parent_id=?,
                            root_id=?,
                            left_index=?,
                            right_index=?,
                            distance_to_parent=?
                            WHERE node_id=?");
  $sth->execute($parent_id, $root_id, $node->left_index, $node->right_index,
                $node->distance_to_parent, $node->node_id);

  $node->adaptor($self);
  $sth->finish;

  if($node->isa('Bio::EnsEMBL::Compara::GeneTreeMember')) {
    my $sql = "UPDATE ".$prefix."_tree_member SET ".
              "cigar_line='". $node->cigar_line . "'";
    $sql .= ", cigar_start=" . $node->cigar_start if($node->cigar_start);
    $sql .= ", cigar_end=" . $node->cigar_end if($node->cigar_end);
    $sql .= ", root_id=" . $root_id;
    $sql .= ", method_link_species_set_id=" . $node->method_link_species_set_id if($node->method_link_species_set_id);
    $sql .= " WHERE node_id=". $node->node_id;
    $self->dbc->do($sql);
  }

}

sub merge_nodes {
  my ($self, $node1, $node2) = @_;

  unless($node1->isa('Bio::EnsEMBL::Compara::GeneTreeNode')) {
    throw("set arg must be a [Bio::EnsEMBL::Compara::GeneTreeNode] not a $node1");
  }

  # printf("MERGE children from parent %d => %d\n", $node2->node_id, $node1->node_id);

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->prepare("UPDATE ".$prefix."_tree_node SET
                              parent_id=?
			      WHERE parent_id=?");
  $sth->execute($node1->node_id, $node2->node_id);
  $sth->finish;

  $sth = $self->prepare("DELETE from ".$prefix."_tree_node WHERE node_id=?");
  $sth->execute($node2->node_id);
  $sth->finish;
}

sub delete_flattened_leaf {
  my $self = shift;
  my $node = shift;

  my $node_id = $node->node_id;
  my $prefix = $self->_get_table_prefix();
  $self->dbc->do("DELETE from ".$prefix."_tree_node WHERE node_id = $node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_tag WHERE node_id = $node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_member WHERE node_id = $node_id");
}

sub delete_node {
  my $self = shift;
  my $node = shift;

  my $node_id = $node->node_id;
  #print("delete node $node_id\n");
  my $prefix = $self->_get_table_prefix();
  $self->dbc->do("UPDATE ".$prefix."_tree_node dn, ".$prefix."_tree_node n SET ".
            "n.parent_id = dn.parent_id WHERE n.parent_id=dn.node_id AND dn.node_id=$node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_node WHERE node_id = $node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_tag WHERE node_id = $node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_member WHERE node_id = $node_id");
}

sub delete_nodes_not_in_tree
{
  my $self = shift;
  my $tree = shift;

  unless($tree->isa('Bio::EnsEMBL::Compara::GeneTreeNode')) {
    throw("set arg must be a [Bio::EnsEMBL::Compara::GeneTreeNode] not a $tree");
  }
  #print("delete_nodes_not_present under ", $tree->node_id, "\n");
  my $dbtree = $self->fetch_node_by_node_id($tree->node_id);
  my @all_db_nodes = $dbtree->get_all_subnodes;
  foreach my $dbnode (@all_db_nodes) {
    next if($tree->find_node_by_node_id($dbnode->node_id));
    $self->delete_node($dbnode);
  }
  $dbtree->release_tree;
}

sub delete_node_and_under {
  my $self = shift;
  my $node = shift;

  my $prefix = $self->_get_table_prefix();
  my @all_subnodes = $node->get_all_subnodes;
  foreach my $subnode (@all_subnodes) {
    my $subnode_id = $subnode->node_id;
    $self->dbc->do("DELETE from ".$prefix."_tree_node WHERE node_id = $subnode_id");
    $self->dbc->do("DELETE from ".$prefix."_tree_tag WHERE node_id = $subnode_id");
    $self->dbc->do("DELETE from ".$prefix."_tree_member WHERE node_id = $subnode_id");
  }
  my $node_id = $node->node_id;
  $self->dbc->do("DELETE from ".$prefix."_tree_node WHERE node_id = $node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_tag WHERE node_id = $node_id");
  $self->dbc->do("DELETE from ".$prefix."_tree_member WHERE node_id = $node_id");
}

sub store_supertree_node_and_under {
  my $self = shift;
  my $node = shift;

  my $prefix = $self->_get_table_prefix();
  $self->dbc->do("CREATE TABLE IF NOT EXISTS super_".$prefix."_tree_node like ".$prefix."_tree_node");
  $self->dbc->do("CREATE TABLE IF NOT EXISTS super_".$prefix."_tree_member like ".$prefix."_tree_member");
  $self->dbc->do("CREATE TABLE IF NOT EXISTS super_".$prefix."_tree_tag like ".$prefix."_tree_tag");

  my @all_subnodes = $node->get_all_subnodes;
  foreach my $subnode (@all_subnodes) {
    my $subnode_id = $subnode->node_id;
    $self->dbc->do("INSERT IGNORE into super_".$prefix."_tree_node SELECT * from ".$prefix."_tree_node WHERE node_id = $subnode_id");
    $self->dbc->do("INSERT IGNORE into super_".$prefix."_tree_member SELECT * from ".$prefix."_tree_member WHERE node_id = $subnode_id");
    $self->dbc->do("INSERT IGNORE into super_".$prefix."_tree_tag SELECT * from ".$prefix."_tree_tag WHERE node_id = $subnode_id");
  }
  my $node_id = $node->node_id;
  $self->dbc->do("INSERT IGNORE into super_".$prefix."_tree_node SELECT * from ".$prefix."_tree_node WHERE node_id = $node_id");
  $self->dbc->do("INSERT IGNORE into super_".$prefix."_tree_member SELECT * from ".$prefix."_tree_member WHERE node_id = $node_id");
  $self->dbc->do("INSERT IGNORE into super_".$prefix."_tree_tag SELECT * from ".$prefix."_tree_tag WHERE node_id = $node_id");
}


###################################
#
# tagging
#
###################################

sub _load_tagvalues {
  my $self = shift;
  my $node = shift;

  unless($node->isa('Bio::EnsEMBL::Compara::GeneTreeNode')) {
    throw("set arg must be a [Bio::EnsEMBL::Compara::GeneTreeNode] not a $node");
  }

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->prepare("SELECT tag,value from ".$prefix."_tree_tag where node_id=?");
  $sth->execute($node->node_id);
  while (my ($tag, $value) = $sth->fetchrow_array()) {
    $node->add_tag($tag,$value);
  }
  $sth->finish;
}

sub _store_tagvalue {
  my $self = shift;
  my $node_id = shift;
  my $tag = shift;
  my $value = shift;

  $value="" unless(defined($value));

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->prepare("INSERT ignore into ".$prefix."_tree_tag (node_id,tag) values (?, ?)");
  $sth->execute($node_id, $tag);

  $sth = $self->prepare("UPDATE ".$prefix."_tree_tag set value=? where node_id=? and tag=?");
  $sth->execute($value, $node_id, $tag);
}

sub delete_tag {
  my $self = shift;
  my $node_id = shift;
  my $tag = shift;

  my $prefix = $self->_get_table_prefix();
  my $sth = $self->dbc->prepare("DELETE from ".$prefix."_tree_tag where node_id=? and tag=?");
  $sth->execute($node_id, $tag);
}


##################################
#
# subclass override methods
#
##################################

sub columns {
  my $self = shift;
  return ['t.node_id',
          't.parent_id',
          't.root_id',
          't.clusterset_id',
          't.left_index',
          't.right_index',
          't.distance_to_parent',

          'tm.cigar_line',
          'tm.cigar_start',
          'tm.cigar_end',
          'tm.method_link_species_set_id',

          @{Bio::EnsEMBL::Compara::DBSQL::MemberAdaptor->columns()}
          ];
}

sub tables {
  my $self = shift;
  my $prefix = $self->_get_table_prefix();
  return [[$prefix.'_tree_node', 't']];
}

sub left_join_clause {
  my $self = shift;
  my $prefix = $self->_get_table_prefix();
  return "left join ".$prefix."_tree_member tm on t.node_id = tm.node_id left join member m on tm.member_id = m.member_id";
}

sub default_where_clause {
  return "";
}


sub _objs_from_sth {
  my ($self, $sth) = @_;
  my $node_list = [];

  while(my $rowhash = $sth->fetchrow_hashref) {
    my $node = $self->create_instance_from_rowhash($rowhash);
    push @$node_list, $node;
  }

  return $node_list;
}


sub create_instance_from_rowhash {
  my $self = shift;
  my $rowhash = shift;

  my $node;
  if($rowhash->{'member_id'}) {
    $node = new Bio::EnsEMBL::Compara::GeneTreeMember;
  } else {
    $node = new Bio::EnsEMBL::Compara::GeneTreeNode;
  }

  $self->init_instance_from_rowhash($node, $rowhash);
  return $node;
}


sub init_instance_from_rowhash {
  my $self = shift;
  my $node = shift;
  my $rowhash = shift;

  #SUPER is NestedSetAdaptor
  $self->SUPER::init_instance_from_rowhash($node, $rowhash);
   if($rowhash->{'member_id'}) {
    Bio::EnsEMBL::Compara::DBSQL::MemberAdaptor->init_instance_from_rowhash($node, $rowhash);

    $node->cigar_line($rowhash->{'cigar_line'});
    $node->method_link_species_set_id($rowhash->{method_link_species_set_id});
# cigar_start and cigar_end does not need to be set.
#    $node->cigar_start($rowhash->{'cigar_start'});
#    $node->cigar_end($rowhash->{'cigar_end'});
  }
  # print("  create node : ", $node, " : "); $node->print_node;

  $node->adaptor($self);

  return $node;
}


##########################################################
#
# explicit method forwarding to MemberAdaptor
#
##########################################################

sub _fetch_sequence_by_id {
  my $self = shift;
  return $self->db->get_MemberAdaptor->_fetch_sequence_by_id(@_);
}

1;

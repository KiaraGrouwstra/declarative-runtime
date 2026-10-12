# tasansga/lldap provider specifics: executor, resource surface, provider block.
#
# The resource surface is *derived* from the vendored provider schema
# (./provider-schema.json, parsed by ./schema.nix) via
# ../../modules/lib/tf-schema.nix. What stays hand-written is only what a schema
# cannot state: the NixOS-facing collection descriptions and the reference graph
# between collections. A provider bump that adds, removes or retypes anything is
# then an eval-time error rather than an apply-time surprise.
#
# Shared helpers (option helpers, renderer, reconciler) live in modules/lib.
{ pkgs, nix-tf-schema }:
let
  genlib = import ../../modules/lib { inherit pkgs; };
  tfSchema = import ../../modules/lib/tf-schema.nix { inherit pkgs nix-tf-schema; };

  provider = import ./pkg.nix { inherit pkgs; };
  providerVersion = provider.version;
  # provider source address; also keys the vendored provider schema.
  providerSource = "tasansga/lldap";
  runtimePrefix = "services.lldap.runtime";
  # The password of the admin user the provider logs in as.
  tokenVar = "lldap_admin_password";
  executor = pkgs.opentofu.withPlugins (_: [ provider ]);

  # A reference to a user, a group, or an attribute of either. A user's id is
  # its user name; a group's id is a number that lldap assigns.
  userRef = {
    targets = [
      {
        collection = "users";
        field = "username";
      }
    ];
    managedOnly = false;
  };
  groupRef = {
    targets = [
      {
        collection = "groups";
        field = "id";
      }
    ];
    managedOnly = false;
  };
  attributeRef = collection: {
    targets = [
      {
        inherit collection;
        # An attribute's id is its name.
        field = "id";
      }
    ];
    managedOnly = false;
  };

  # The tasansga/lldap resource surface. Per collection, only the facts the
  # schema does not carry (see modules/lib/tf-schema.nix for the full overlay
  # vocabulary). `scope` is null throughout: lldap has no token scopes.
  generated = tfSchema.mkResourceTypes {
    schema = import ./schema.nix;
    inherit provider runtimePrefix;
    source = providerSource;
    resources = {
      users = {
        type = "lldap_user";
        prefix = "user";
        nameAttr = "username";
        scope = null;
        refs = { };
        description = "lldap users, keyed by user name.";
      };
      groups = {
        type = "lldap_group";
        prefix = "group";
        nameAttr = "display_name";
        scope = null;
        refs = { };
        description = "lldap groups, keyed by display name. The built-in groups (`lldap_admin` and others) are not in this collection: lldap makes them.";
      };
      user_attributes = {
        type = "lldap_user_attribute";
        prefix = "user_attribute";
        nameAttr = "name";
        scope = null;
        refs = { };
        description = "Custom attributes in the user schema, keyed by attribute name.";
      };
      group_attributes = {
        type = "lldap_group_attribute";
        prefix = "group_attribute";
        nameAttr = "name";
        scope = null;
        refs = { };
        description = "Custom attributes in the group schema, keyed by attribute name.";
      };
      members = {
        type = "lldap_member";
        prefix = "member";
        nameAttr = null;
        scope = null;
        refs = {
          user = userRef // {
            attr = "user_id";
            required = true;
            description = "User to add: the key of a managed user, or a literal user name.";
          };
          group = groupRef // {
            attr = "group_id";
            required = true;
            description = "Group to add the user to: the key of a managed group, or a literal group id.";
          };
        };
        description = "Single memberships of a user in a group, keyed by an arbitrary label. Other memberships of the user and the group are kept.";
      };
      group_memberships = {
        type = "lldap_group_memberships";
        prefix = "group_memberships";
        nameAttr = null;
        scope = null;
        refs = {
          group = groupRef // {
            attr = "group_id";
            required = true;
            description = "Group whose members to set: the key of a managed group, or a literal group id.";
          };
          users = userRef // {
            attr = "user_ids";
            list = true;
            required = true;
            description = "All members of the group: keys of managed users, or literal user names.";
          };
        };
        description = "The full member list of a group, keyed by an arbitrary label. Members that are not in the list are removed, so do not also use `members` or `user_memberships` for the same group.";
      };
      user_memberships = {
        type = "lldap_user_memberships";
        prefix = "user_memberships";
        nameAttr = null;
        scope = null;
        refs = {
          user = userRef // {
            attr = "user_id";
            required = true;
            description = "User whose groups to set: the key of a managed user, or a literal user name.";
          };
          groups = groupRef // {
            attr = "group_ids";
            list = true;
            required = true;
            description = "All groups of the user: keys of managed groups, or literal group ids.";
          };
        };
        description = "The full group list of a user, keyed by an arbitrary label. Groups that are not in the list are removed, so do not also use `members` or `group_memberships` for the same user.";
      };
      user_attribute_assignments = {
        type = "lldap_user_attribute_assignment";
        prefix = "user_attribute_assignment";
        nameAttr = null;
        scope = null;
        refs = {
          user = userRef // {
            attr = "user_id";
            required = true;
            description = "User to set the attribute on: the key of a managed user, or a literal user name.";
          };
          attribute = attributeRef "user_attributes" // {
            attr = "attribute_id";
            required = true;
            description = "Attribute to set: the key of a managed user attribute, or a literal attribute name.";
          };
        };
        description = "Values of custom user attributes, keyed by an arbitrary label.";
      };
      group_attribute_assignments = {
        type = "lldap_group_attribute_assignment";
        prefix = "group_attribute_assignment";
        nameAttr = null;
        scope = null;
        refs = {
          group = groupRef // {
            attr = "group_id";
            required = true;
            description = "Group to set the attribute on: the key of a managed group, or a literal group id.";
          };
          attribute = attributeRef "group_attributes" // {
            attr = "attribute_id";
            required = true;
            description = "Attribute to set: the key of a managed group attribute, or a literal attribute name.";
          };
        };
        description = "Values of custom group attributes, keyed by an arbitrary label.";
      };
    };
  };
  inherit (generated) resourceTypes;

  lldapTfConfig = genlib.mkTfConfig {
    inherit
      resourceTypes
      providerVersion
      providerSource
      runtimePrefix
      tokenVar
      ;
    providerName = "lldap";
    providerBlock = cfg: {
      http_url = cfg.baseUrl;
      # The provider dials LDAP only to set a user's password.
      ldap_url = cfg.ldapUrl;
      username = cfg.adminUser;
      password = "\${var.${tokenVar}}";
      base_dn = cfg.baseDN;
    };
  };
in
{
  inherit
    provider
    providerSource
    resourceTypes
    lldapTfConfig
    ;
  # the generator's drift assertions and coverage data, for the pairing's checks
  # to force independently of any particular configuration.
  inherit (generated) checks coverage;
  resourceOptions = genlib.resourceOptions resourceTypes;
  mkReconcileService = args: genlib.mkReconcileService (args // { inherit executor tokenVar; });
}

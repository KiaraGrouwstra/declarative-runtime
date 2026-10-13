# cyrilgdn/postgresql provider specifics: executor, resource surface, provider
# block.
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

  provider = pkgs.terraform-providers.cyrilgdn_postgresql;
  providerVersion = provider.version;
  # provider source address; also keys the vendored provider schema.
  providerSource = "cyrilgdn/postgresql";
  runtimePrefix = "services.postgresql.runtime";
  # the password of the role that the provider logs in as.
  tokenVar = "postgresql_password";
  # the role that the provider logs in as. The module makes it.
  adminUser = "declarative_postgresql";
  executor = pkgs.opentofu.withPlugins (_: [ provider ]);

  # A reference to a role, a database, a schema or a foreign server takes the
  # key of a managed entry or a literal name, so objects that PostgreSQL makes
  # itself (the `postgres` database, the `public` schema, the `public`
  # pseudo-role) stay reachable.
  ref =
    collection: field: attrs:
    {
      targets = [ { inherit collection field; } ];
      managedOnly = false;
      required = false;
    }
    // attrs;
  roleRef = ref "roles" "name";
  databaseRef = ref "databases" "name";
  schemaRef = ref "schemas" "name";
  serverRef = ref "servers" "server_name";

  optionalDatabase = databaseRef {
    attr = "database";
    description = "Database: the key of a managed database, or a literal database name. Null is the database that the provider connects to (`postgres`).";
  };
  requiredDatabase = databaseRef {
    attr = "database";
    required = true;
    description = "Database: the key of a managed database, or a literal database name.";
  };
  optionalSchema = schemaRef {
    attr = "schema";
    description = "Schema: the key of a managed schema, or a literal schema name.";
  };
  optionalOwner = roleRef {
    attr = "owner";
    description = "Owner: the key of a managed role, or a literal role name. Null is the role that the provider connects as.";
  };
  # `public` is a pseudo-role for all roles.
  grantee = roleRef {
    attr = "role";
    required = true;
    description = "Role that gets the privileges: the key of a managed role, or a literal role name (`public` for all roles).";
  };

  # The cyrilgdn/postgresql resource surface. Per collection, only the facts the
  # schema does not carry (see modules/lib/tf-schema.nix for the full overlay
  # vocabulary). `scope` is null throughout: PostgreSQL has no token scopes.
  generated = tfSchema.mkResourceTypes {
    schema = import ./schema.nix;
    inherit provider runtimePrefix;
    source = providerSource;
    # the sdk/v2 synthetic `id` is computed.
    omitEverywhere = [ "id" ];
    resources = {
      roles = {
        type = "postgresql_role";
        prefix = "role";
        nameAttr = "name";
        scope = null;
        refs = {
          roles = roleRef {
            attr = "roles";
            list = true;
            description = "Roles that this role is a member of: keys of managed roles, or literal role names. The list is complete: memberships not in it are revoked.";
          };
          assume_role = roleRef {
            attr = "assume_role";
            description = "Role to switch to at login: the key of a managed role, or a literal role name.";
          };
        };
        description = "PostgreSQL roles (users and groups), keyed by role name.";
      };
      databases = {
        type = "postgresql_database";
        prefix = "database";
        nameAttr = "name";
        scope = null;
        refs.owner = optionalOwner;
        description = "PostgreSQL databases, keyed by database name.";
      };
      schemas = {
        type = "postgresql_schema";
        prefix = "schema";
        nameAttr = "name";
        scope = null;
        refs = {
          database = optionalDatabase;
          owner = optionalOwner;
        };
        description = "PostgreSQL schemas, keyed by schema name.";
      };
      extensions = {
        type = "postgresql_extension";
        prefix = "extension";
        nameAttr = "name";
        scope = null;
        refs = {
          database = optionalDatabase;
          schema = optionalSchema;
        };
        description = "PostgreSQL extensions, keyed by extension name. The PostgreSQL package must contain the extension (`services.postgresql.extensions`).";
      };
      functions = {
        type = "postgresql_function";
        prefix = "function";
        nameAttr = "name";
        scope = null;
        refs = {
          database = optionalDatabase;
          schema = optionalSchema;
        };
        description = "PostgreSQL functions, keyed by function name.";
      };
      grants = {
        type = "postgresql_grant";
        prefix = "grant";
        nameAttr = null;
        scope = null;
        refs = {
          database = requiredDatabase;
          role = grantee;
          schema = optionalSchema;
        };
        description = "Privileges of a role on a database, a schema or objects, keyed by an arbitrary handle. The list of privileges is complete: privileges of that role on that object type that are not in it are revoked.";
      };
      grant_roles = {
        type = "postgresql_grant_role";
        prefix = "grant_role";
        nameAttr = null;
        scope = null;
        refs = {
          role = roleRef {
            attr = "role";
            required = true;
            description = "Role that gets the membership: the key of a managed role, or a literal role name.";
          };
          grant_role = roleRef {
            attr = "grant_role";
            required = true;
            description = "Role to grant membership of: the key of a managed role, or a literal role name.";
          };
        };
        description = "Role memberships, keyed by an arbitrary handle. Each adds one membership and keeps all others. For a member role in `roles`, use `roles.<name>.roles` instead: that list is complete, so each apply revokes a membership from here and the next apply grants it again.";
      };
      default_privileges = {
        type = "postgresql_default_privileges";
        prefix = "default_privileges";
        nameAttr = null;
        scope = null;
        refs = {
          database = requiredDatabase;
          owner = roleRef {
            attr = "owner";
            required = true;
            description = "Role whose new objects get the privileges: the key of a managed role, or a literal role name.";
          };
          role = grantee;
          schema = optionalSchema;
        };
        description = "Default privileges on objects that a role makes in the future, keyed by an arbitrary handle.";
      };
      publications = {
        type = "postgresql_publication";
        prefix = "publication";
        nameAttr = "name";
        scope = null;
        refs = {
          database = optionalDatabase;
          owner = optionalOwner;
        };
        description = "Logical replication publications, keyed by publication name. Requires `services.postgresql.settings.wal_level = \"logical\"`.";
      };
      subscriptions = {
        type = "postgresql_subscription";
        prefix = "subscription";
        nameAttr = "name";
        scope = null;
        refs = {
          database = optionalDatabase;
          publications = ref "publications" "name" {
            attr = "publications";
            list = true;
            required = true;
            description = "Publications to subscribe to. A key of a managed publication when this server publishes them, else a literal publication name on the server in `conninfo`.";
          };
          slot_name = ref "replication_slots" "name" {
            attr = "slot_name";
            description = "Replication slot on the publisher. A key of a managed replication slot when this server publishes, else a literal slot name. Null lets the subscription make a slot named after it.";
          };
        };
        description = "Logical replication subscriptions, keyed by subscription name. When the publisher is this server, set `create_slot = false` and name a managed replication slot, as `CREATE SUBSCRIPTION` cannot make a slot on its own server.";
      };
      replication_slots = {
        type = "postgresql_replication_slot";
        prefix = "replication_slot";
        nameAttr = "name";
        scope = null;
        refs.database = optionalDatabase;
        description = "Logical replication slots, keyed by slot name. Requires `services.postgresql.settings.wal_level = \"logical\"`.";
      };
      physical_replication_slots = {
        type = "postgresql_physical_replication_slot";
        prefix = "physical_replication_slot";
        nameAttr = "name";
        scope = null;
        refs = { };
        description = "Physical replication slots, keyed by slot name.";
      };
      servers = {
        type = "postgresql_server";
        prefix = "server";
        nameAttr = "server_name";
        scope = null;
        refs = {
          fdw_name = ref "extensions" "name" {
            attr = "fdw_name";
            required = true;
            description = "Foreign-data wrapper: the key of a managed extension that makes a wrapper of the same name (such as `postgres_fdw`), or a literal wrapper name.";
          };
          server_owner = roleRef {
            attr = "server_owner";
            description = "Owner of the server: the key of a managed role, or a literal role name. Null is the role that the provider connects as.";
          };
        };
        description = "Foreign servers, keyed by server name. A server is in the database that the provider connects to (`postgres`), so the extension that makes its wrapper must be there too.";
      };
      user_mappings = {
        type = "postgresql_user_mapping";
        prefix = "user_mapping";
        nameAttr = null;
        scope = null;
        refs = {
          server_name = serverRef {
            attr = "server_name";
            required = true;
            description = "Foreign server: the key of a managed server, or a literal server name.";
          };
          user_name = roleRef {
            attr = "user_name";
            required = true;
            description = "Role to map: the key of a managed role, or a literal role name (`public` for all roles).";
          };
        };
        description = "User mappings for foreign servers, keyed by an arbitrary handle. An option value can come from a file: `options.passwordFile` in place of `options.password`.";
      };
      security_labels = {
        type = "postgresql_security_label";
        prefix = "security_label";
        nameAttr = null;
        scope = null;
        refs = { };
        description = "Security labels, keyed by an arbitrary handle. The label provider must be loaded, for example through `services.postgresql.settings.shared_preload_libraries`.";
      };
    };
  };
  inherit (generated) resourceTypes;

  postgresqlTfConfig = genlib.mkTfConfig {
    inherit
      resourceTypes
      providerVersion
      providerSource
      runtimePrefix
      tokenVar
      ;
    providerName = "postgresql";
    providerBlock = cfg: {
      # TCP and not the socket: the provider puts the host into a connection
      # URL, which cannot hold a socket path.
      host = "127.0.0.1";
      inherit (cfg) port;
      database = "postgres";
      username = adminUser;
      password = "\${var.${tokenVar}}";
      sslmode = "disable";
      # The role is a superuser, but with `superuser = true` the provider reads
      # each role password back from `pg_authid`. A SCRAM hash then differs
      # from the declared password, and every apply changes the role.
      superuser = false;
    };
  };
in
{
  inherit
    provider
    providerSource
    adminUser
    resourceTypes
    postgresqlTfConfig
    ;
  # the generator's drift assertions and coverage data, for the pairing's checks
  # to force independently of any particular configuration.
  inherit (generated) checks coverage;
  resourceOptions = genlib.resourceOptions resourceTypes;
  mkReconcileService = args: genlib.mkReconcileService (args // { inherit executor tokenVar; });
}

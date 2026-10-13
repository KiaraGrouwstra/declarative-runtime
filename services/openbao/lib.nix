# hashicorp/vault provider specifics, against OpenBao: executor, resource
# surface, provider block.
#
# The resource surface is *derived* from the vendored provider schema
# (./provider-schema.json, parsed by ./schema.nix) via
# ../../modules/lib/tf-schema.nix. What stays hand-written is only what a schema
# cannot state: the NixOS-facing collection descriptions, the reference graph
# between collections, and the resources that OpenBao does not serve.
#
# Shared helpers (option helpers, renderer, reconciler) live in modules/lib.
{ pkgs, nix-tf-schema }:
let
  inherit (pkgs) lib;
  genlib = import ../../modules/lib { inherit pkgs; };
  tfSchema = import ../../modules/lib/tf-schema.nix { inherit pkgs nix-tf-schema; };
  schema = import ./schema.nix;

  provider = pkgs.terraform-providers.hashicorp_vault;
  providerVersion = provider.version;
  # provider source address; also keys the vendored provider schema.
  providerSource = "hashicorp/vault";
  runtimePrefix = "services.openbao.runtime";
  # the token that the provider authenticates with.
  tokenVar = "openbao_token";
  executor = pkgs.opentofu.withPlugins (_: [ provider ]);

  # A reference takes the key of a managed entry or a literal value, so objects
  # that OpenBao makes itself (the `token/` auth method, the `default` and
  # `root` policies) and objects managed elsewhere stay reachable.
  ref =
    targets: attrs:
    {
      inherit targets;
      managedOnly = false;
      required = false;
    }
    // attrs;
  on =
    field:
    map (collection: {
      inherit collection field;
    });

  # collections that mount a secrets engine or an auth method.
  secretsMounts = [
    "mounts"
    "database_secrets_mounts"
    "kubernetes_secret_backends"
    "ldap_secret_backends"
    "rabbitmq_secret_backends"
  ];
  authMounts = [
    "auth_backends"
    "jwt_auth_backends"
    "ldap_auth_backends"
  ];

  mountRef =
    attr: required:
    ref (on "path" secretsMounts) {
      inherit attr required;
      description = "Secrets engine mount path: the key of a managed mount, or a literal path.";
    };
  authRef =
    attr: required:
    ref (on "path" authMounts) {
      inherit attr required;
      description = "Auth method mount path: the key of a managed auth method, or a literal path. Null is the default path of the auth method type.";
    };
  accessorRef =
    attr: attrs:
    ref (on "accessor" authMounts) (
      {
        inherit attr;
        description = "Auth method accessor: the key of a managed auth method, or a literal accessor.";
      }
      // attrs
    );
  policiesRef =
    attr: attrs:
    ref (on "name" [ "policies" ]) (
      {
        inherit attr;
        list = true;
        description = "Policies: keys of managed policies, or literal policy names (such as `default`).";
      }
      // attrs
    );
  passwordPolicyRef =
    attr:
    ref (on "name" [ "password_policies" ]) {
      inherit attr;
      description = "Password policy: the key of a managed password policy, or a literal policy name.";
    };
  entityRef =
    attr: attrs:
    ref (on "id" [ "identity_entities" ]) (
      {
        inherit attr;
        description = "Identity entity: the key of a managed entity, or a literal entity ID.";
      }
      // attrs
    );
  groupRef =
    attr: attrs:
    ref (on "id" [ "identity_groups" ]) (
      {
        inherit attr;
        description = "Identity group: the key of a managed group, or a literal group ID.";
      }
      // attrs
    );
  oidcKeyRef =
    attr: required:
    ref (on "name" [ "identity_oidc_keys" ]) {
      inherit attr required;
      description = "OIDC signing key: the key of a managed OIDC key, or a literal key name.";
    };
  oidcClientRef =
    attr: attrs:
    ref (on "client_id" [ "identity_oidc_clients" ]) (
      {
        inherit attr;
        description = "OIDC client: the key of a managed OIDC client, or a literal client ID.";
      }
      // attrs
    );
  # an issuer comes from a root certificate, or from an issuer that is
  # imported with an intermediate certificate.
  issuerRef =
    attr: required:
    ref
      [
        {
          collection = "pki_root_certs";
          field = "issuer_id";
        }
        {
          collection = "pki_issuers";
          field = "issuer_id";
        }
      ]
      {
        inherit attr required;
        description = "PKI issuer: the key of a managed root certificate or issuer, or a literal issuer ID or name.";
      };
  pkiKeyRef =
    attr:
    ref (on "key_id" [ "pki_keys" ]) {
      inherit attr;
      description = "PKI key: the key of a managed PKI key, or a literal key ID or name.";
    };
  # every PKI resource takes the path of its PKI mount.
  pki = refs: { backend = mountRef "backend" true; } // refs;

  # OpenBao has namespaces, so each resource that takes a `namespace` can be
  # put in a managed one.
  namespaceRef = ref (on "path_fq" [ "namespaces" ]) {
    attr = "namespace";
    description = "Namespace: the key of a managed namespace, or a literal namespace path. Null is the namespace of the provider (the root namespace).";
  };
  withNamespace =
    o:
    {
      scope = null;
      refs = { };
    }
    // o
    // {
      refs =
        lib.optionalAttrs (schema.resource_schemas.${o.type}.block.attributes ? namespace) {
          namespace = namespaceRef;
        }
        // o.refs or { };
    };

  # Database plugins that the provider has a block for, but that OpenBao does
  # not have built in.
  absentDatabasePlugins = [
    "couchbase"
    "elasticsearch"
    "hana"
    "mongodb"
    "mongodbatlas"
    "mssql"
    "oracle"
    "redis_elasticache"
    "redshift"
    "snowflake"
  ];

  because = reason: types: lib.genAttrs (map (t: "vault_${t}") types) (_: reason);
  unsupported =
    because "OpenBao does not have this secrets engine or auth method built in." [
      "ad_secret_backend"
      "ad_secret_library"
      "ad_secret_role"
      "alicloud_auth_backend_role"
      "alicloud_secret_backend"
      "alicloud_secret_backend_role"
      "aws_auth_backend_cert"
      "aws_auth_backend_client"
      "aws_auth_backend_config_identity"
      "aws_auth_backend_identity_whitelist"
      "aws_auth_backend_login"
      "aws_auth_backend_role"
      "aws_auth_backend_role_tag"
      "aws_auth_backend_roletag_blacklist"
      "aws_auth_backend_sts_role"
      "aws_secret_backend"
      "aws_secret_backend_role"
      "aws_secret_backend_static_role"
      "azure_auth_backend_config"
      "azure_auth_backend_role"
      "azure_secret_backend"
      "azure_secret_backend_role"
      "azure_secret_backend_static_role"
      "cf_auth_backend_config"
      "cf_auth_backend_role"
      "consul_secret_backend"
      "consul_secret_backend_role"
      "gcp_auth_backend"
      "gcp_auth_backend_role"
      "gcp_secret_backend"
      "gcp_secret_impersonated_account"
      "gcp_secret_roleset"
      "gcp_secret_static_account"
      "gcpkms_secret_backend"
      "gcpkms_secret_backend_key"
      "github_auth_backend"
      "github_team"
      "github_user"
      "mongodbatlas_secret_backend"
      "mongodbatlas_secret_role"
      "nomad_secret_backend"
      "nomad_secret_role"
      "oci_auth_backend"
      "oci_auth_backend_role"
      "okta_auth_backend"
      "okta_auth_backend_group"
      "okta_auth_backend_user"
      "terraform_cloud_secret_backend"
      "terraform_cloud_secret_creds"
      "terraform_cloud_secret_role"
    ]
    // because "Vault Enterprise or Vault only: OpenBao does not have this engine." [
      "keymgmt_aws_kms"
      "keymgmt_azure_kms"
      "keymgmt_distribute_key"
      "keymgmt_gcp_kms"
      "keymgmt_key"
      "keymgmt_key_rotate"
      "keymgmt_replicate_key"
      "kmip_secret_backend"
      "kmip_secret_ca_generated"
      "kmip_secret_ca_imported"
      "kmip_secret_listener"
      "kmip_secret_role"
      "kmip_secret_scope"
      "transform_alphabet"
      "transform_key_configuration"
      "transform_role"
      "transform_template"
      "transform_transformation"
      "saml_auth_backend"
      "saml_auth_backend_role"
      "scep_auth_backend_role"
      "spiffe_auth_backend_config"
      "spiffe_auth_backend_role"
      "spiffe_secret_backend_config"
      "spiffe_secret_backend_role"
      "os_secret_backend"
      "os_secret_backend_account"
      "os_secret_backend_host"
      "pki_external_ca_secret_backend_acme_account"
      "pki_external_ca_secret_backend_order"
      "pki_external_ca_secret_backend_order_certificate"
      "pki_external_ca_secret_backend_order_challenge_fulfilled"
      "pki_external_ca_secret_backend_role"
    ]
    // because "Vault Enterprise PKI enrollment protocol: OpenBao PKI does not serve it." [
      "pki_secret_backend_config_cmpv2"
      "pki_secret_backend_config_est"
      "pki_secret_backend_config_scep"
    ]
    // because "Vault Enterprise `sys/` endpoint: OpenBao does not serve it." [
      "managed_keys"
      "secrets_sync_association"
      "secrets_sync_aws_destination"
      "secrets_sync_azure_destination"
      "secrets_sync_config"
      "secrets_sync_gcp_destination"
      "secrets_sync_gh_destination"
      "secrets_sync_github_apps"
      "secrets_sync_vercel_destination"
      "egp_policy"
      "rgp_policy"
      "config_control_group"
      "config_group_policy_application"
      "activation_flags"
      "quota_lease_count"
      "raft_snapshot_agent_config"
      "plugin_pinned_version"
      "plugin_runtime"
      "config_ui_custom_message"
      "config_ui_default_auth"
      "rotation_policy"
      "oauth_resource_server_config_profile"
      "agent_registration"
    ]
    //
      because
        "Vault Enterprise step-up MFA (`sys/mfa/method`): OpenBao serves only the identity MFA methods (`identity_mfa_*`)."
        [
          "mfa_duo"
          "mfa_okta"
          "mfa_pingid"
          "mfa_totp"
        ]
    //
      because "Mints a credential that goes only into the Terraform state, where no consumer can read it."
        [
          "approle_auth_backend_login"
          "token"
          "pki_secret_backend_cert"
          "pki_secret_backend_sign"
        ]
    //
      because
        "OpenBao refuses to make an audit device through the API unless `unsafe_allow_api_audit_creation` is set. Declare audit devices in `services.openbao.settings` instead."
        [
          "audit"
        ];

  # The hashicorp/vault resource surface that OpenBao serves. Per collection,
  # only the facts the schema does not carry (see modules/lib/tf-schema.nix for
  # the full overlay vocabulary). `scope` is null throughout: the provider
  # token is a single token, and its policies decide what it can do.
  generated = tfSchema.mkResourceTypes {
    inherit
      schema
      provider
      runtimePrefix
      unsupported
      ;
    source = providerSource;
    # the sdk/v2 synthetic `id` is computed.
    omitEverywhere = [ "id" ];
    resources = lib.mapAttrs (_: withNamespace) {
      # Mounts and system configuration.
      namespaces = {
        type = "vault_namespace";
        prefix = "namespace";
        nameAttr = "path";
        description = "Namespaces, keyed by path relative to the parent namespace.";
      };
      mounts = {
        type = "vault_mount";
        prefix = "mount";
        nameAttr = "path";
        description = "Secrets engine mounts, keyed by path.";
      };
      auth_backends = {
        type = "vault_auth_backend";
        prefix = "auth";
        nameAttr = "path";
        # a list of objects, which the option conversion does not support; the
        # same settings are top-level attributes.
        omit = [ "tune" ];
        description = "Auth method mounts other than `jwt`, `oidc` and `ldap`, keyed by path.";
      };
      policies = {
        type = "vault_policy";
        prefix = "policy";
        nameAttr = "name";
        description = "ACL policies, keyed by name.";
      };
      password_policies = {
        type = "vault_password_policy";
        prefix = "password_policy";
        nameAttr = "name";
        description = "Password policies, keyed by name.";
      };
      audit_request_headers = {
        type = "vault_audit_request_header";
        prefix = "audit_request_header";
        nameAttr = "name";
        description = "Request headers that audit devices log, keyed by header name.";
      };
      ui_headers = {
        type = "vault_config_ui_header";
        prefix = "ui_header";
        nameAttr = "name";
        description = "Custom response headers of the web UI, keyed by header name.";
      };
      config_cors = {
        type = "vault_sys_config_cors";
        prefix = "config_cors";
        nameAttr = null;
        description = "CORS configuration, keyed by an arbitrary handle. Declare at most one.";
      };
      plugins = {
        type = "vault_plugin";
        prefix = "plugin";
        nameAttr = "name";
        description = "Plugin catalog entries, keyed by plugin name. The plugin binary must be in the plugin directory of the server.";
      };
      quota_config = {
        type = "vault_quota_config";
        prefix = "quota_config";
        nameAttr = null;
        description = "Quota configuration, keyed by an arbitrary handle. Declare at most one per namespace.";
      };
      quota_rate_limits = {
        type = "vault_quota_rate_limit";
        prefix = "quota_rate_limit";
        nameAttr = "name";
        description = "Rate limit quotas, keyed by name.";
      };
      raft_autopilot = {
        type = "vault_raft_autopilot";
        prefix = "raft_autopilot";
        nameAttr = null;
        description = "Raft autopilot configuration, keyed by an arbitrary handle. Declare at most one. Requires the `raft` storage backend.";
      };

      # Auth methods.
      approle_roles = {
        type = "vault_approle_auth_backend_role";
        prefix = "approle_role";
        nameAttr = "role_name";
        refs = {
          backend = authRef "backend" false;
          token_policies = policiesRef "token_policies" { };
        };
        description = "AppRole roles, keyed by role name.";
      };
      approle_secret_ids = {
        type = "vault_approle_auth_backend_role_secret_id";
        prefix = "approle_secret_id";
        nameAttr = null;
        refs = {
          backend = authRef "backend" false;
          role_name = ref (on "role_name" [ "approle_roles" ]) {
            attr = "role_name";
            required = true;
            description = "AppRole role: the key of a managed AppRole role, or a literal role name.";
          };
        };
        description = "AppRole secret IDs, keyed by an arbitrary handle. Without `secret_id`, OpenBao generates the secret ID, and it goes only into the Terraform state.";
      };
      cert_auth_roles = {
        type = "vault_cert_auth_backend_role";
        prefix = "cert_role";
        nameAttr = "name";
        refs = {
          backend = authRef "backend" false;
          token_policies = policiesRef "token_policies" { };
        };
        description = "TLS certificate auth roles, keyed by name.";
      };
      jwt_auth_backends = {
        type = "vault_jwt_auth_backend";
        prefix = "jwt_auth";
        nameAttr = "path";
        omit = [ "tune" ];
        description = "`jwt` and `oidc` auth method mounts with their configuration, keyed by path.";
      };
      jwt_auth_roles = {
        type = "vault_jwt_auth_backend_role";
        prefix = "jwt_role";
        nameAttr = "role_name";
        refs = {
          backend = authRef "backend" false;
          token_policies = policiesRef "token_policies" { };
        };
        description = "JWT and OIDC auth roles, keyed by role name.";
      };
      kerberos_auth_configs = {
        type = "vault_kerberos_auth_backend_config";
        prefix = "kerberos_config";
        nameAttr = null;
        refs.mount = authRef "mount" true;
        description = "Kerberos auth method configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      kerberos_auth_groups = {
        type = "vault_kerberos_auth_backend_group";
        prefix = "kerberos_group";
        nameAttr = "name";
        refs = {
          mount = authRef "mount" true;
          policies = policiesRef "policies" { };
        };
        description = "Kerberos auth LDAP group mappings, keyed by group name.";
      };
      kerberos_auth_ldap_configs = {
        type = "vault_kerberos_auth_backend_ldap_config";
        prefix = "kerberos_ldap_config";
        nameAttr = null;
        refs = {
          mount = authRef "mount" true;
          token_policies = policiesRef "token_policies" { };
        };
        description = "Kerberos auth LDAP configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      kubernetes_auth_configs = {
        type = "vault_kubernetes_auth_backend_config";
        prefix = "kubernetes_auth_config";
        nameAttr = null;
        refs.backend = authRef "backend" false;
        description = "Kubernetes auth method configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      kubernetes_auth_roles = {
        type = "vault_kubernetes_auth_backend_role";
        prefix = "kubernetes_auth_role";
        nameAttr = "role_name";
        refs = {
          backend = authRef "backend" false;
          token_policies = policiesRef "token_policies" { };
        };
        description = "Kubernetes auth roles, keyed by role name.";
      };
      ldap_auth_backends = {
        type = "vault_ldap_auth_backend";
        prefix = "ldap_auth";
        nameAttr = "path";
        omit = [ "tune" ];
        refs.token_policies = policiesRef "token_policies" { };
        description = "`ldap` auth method mounts with their configuration, keyed by path.";
      };
      ldap_auth_groups = {
        type = "vault_ldap_auth_backend_group";
        prefix = "ldap_auth_group";
        nameAttr = "groupname";
        refs = {
          backend = authRef "backend" false;
          policies = policiesRef "policies" { };
        };
        description = "LDAP auth group mappings, keyed by group name.";
      };
      ldap_auth_users = {
        type = "vault_ldap_auth_backend_user";
        prefix = "ldap_auth_user";
        nameAttr = "username";
        refs = {
          backend = authRef "backend" false;
          policies = policiesRef "policies" { };
        };
        description = "LDAP auth user mappings, keyed by user name.";
      };
      radius_auth_configs = {
        type = "vault_radius_auth_backend";
        prefix = "radius_config";
        nameAttr = null;
        refs = {
          mount = authRef "mount" true;
          token_policies = policiesRef "token_policies" { };
          unregistered_user_policies = policiesRef "unregistered_user_policies" { };
        };
        description = "RADIUS auth method configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      radius_auth_users = {
        type = "vault_radius_auth_backend_user";
        prefix = "radius_user";
        nameAttr = "username";
        refs = {
          mount = authRef "mount" true;
          policies = policiesRef "policies" { };
        };
        description = "RADIUS auth user mappings, keyed by user name.";
      };
      token_roles = {
        type = "vault_token_auth_backend_role";
        prefix = "token_role";
        nameAttr = "role_name";
        refs = {
          allowed_policies = policiesRef "allowed_policies" { };
          disallowed_policies = policiesRef "disallowed_policies" { };
          token_policies = policiesRef "token_policies" { };
        };
        description = "Token auth roles, keyed by role name.";
      };
      userpass_users = {
        type = "vault_userpass_auth_backend_user";
        prefix = "userpass_user";
        nameAttr = "username";
        refs = {
          mount = authRef "mount" true;
          token_policies = policiesRef "token_policies" { };
        };
        description = "Userpass auth users, keyed by user name.";
      };

      # Key/value and generic secrets.
      generic_endpoints = {
        type = "vault_generic_endpoint";
        prefix = "generic_endpoint";
        nameAttr = "path";
        description = "Writes to arbitrary API paths, keyed by path. The path is literal, so the write is not ordered after a managed mount.";
      };
      generic_secrets = {
        type = "vault_generic_secret";
        prefix = "generic_secret";
        nameAttr = "path";
        description = "Secrets at arbitrary paths, keyed by path. The path is literal, so the write is not ordered after a managed mount.";
      };
      kv_secrets = {
        type = "vault_kv_secret";
        prefix = "kv_secret";
        nameAttr = "path";
        description = "Key/value version 1 secrets, keyed by full path. The path is literal, so the write is not ordered after a managed mount.";
      };
      kv_backend_v2_configs = {
        type = "vault_kv_secret_backend_v2";
        prefix = "kv_v2_config";
        nameAttr = null;
        refs.mount = mountRef "mount" true;
        description = "Key/value version 2 mount configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      kv_secrets_v2 = {
        type = "vault_kv_secret_v2";
        prefix = "kv_secret_v2";
        nameAttr = "name";
        refs.mount = mountRef "mount" true;
        description = "Key/value version 2 secrets, keyed by name in the mount.";
      };

      # Secrets engines.
      database_secrets_mounts = {
        type = "vault_database_secrets_mount";
        prefix = "database_mount";
        nameAttr = "path";
        omit = absentDatabasePlugins;
        description = "Database secrets engine mounts with their connections, keyed by path.";
      };
      database_connections = {
        type = "vault_database_secret_backend_connection";
        prefix = "db_conn";
        nameAttr = "name";
        omit = absentDatabasePlugins;
        refs = {
          backend = mountRef "backend" true;
          password_policy = passwordPolicyRef "password_policy";
        };
        description = "Database secrets engine connections, keyed by name.";
      };
      database_roles = {
        type = "vault_database_secret_backend_role";
        prefix = "db_role";
        nameAttr = "name";
        refs = {
          backend = mountRef "backend" true;
          db_name = ref (on "name" [ "database_connections" ]) {
            attr = "db_name";
            required = true;
            description = "Database connection: the key of a managed connection, or a literal connection name.";
          };
        };
        description = "Database secrets engine dynamic roles, keyed by name.";
      };
      database_static_roles = {
        type = "vault_database_secret_backend_static_role";
        prefix = "db_static_role";
        nameAttr = "name";
        refs = {
          backend = mountRef "backend" true;
          db_name = ref (on "name" [ "database_connections" ]) {
            attr = "db_name";
            required = true;
            description = "Database connection: the key of a managed connection, or a literal connection name.";
          };
        };
        description = "Database secrets engine static roles, keyed by name.";
      };
      kubernetes_secret_backends = {
        type = "vault_kubernetes_secret_backend";
        prefix = "kubernetes_secrets";
        nameAttr = "path";
        description = "Kubernetes secrets engine mounts with their configuration, keyed by path.";
      };
      kubernetes_secret_roles = {
        type = "vault_kubernetes_secret_backend_role";
        prefix = "kubernetes_secret_role";
        nameAttr = "name";
        refs.backend = mountRef "backend" true;
        description = "Kubernetes secrets engine roles, keyed by name.";
      };
      ldap_secret_backends = {
        type = "vault_ldap_secret_backend";
        prefix = "ldap_secrets";
        nameAttr = "path";
        refs.password_policy = passwordPolicyRef "password_policy";
        description = "LDAP secrets engine mounts with their configuration, keyed by path.";
      };
      ldap_secret_dynamic_roles = {
        type = "vault_ldap_secret_backend_dynamic_role";
        prefix = "ldap_dynamic_role";
        nameAttr = "role_name";
        refs.mount = mountRef "mount" false;
        description = "LDAP secrets engine dynamic roles, keyed by role name.";
      };
      ldap_secret_library_sets = {
        type = "vault_ldap_secret_backend_library_set";
        prefix = "ldap_library_set";
        nameAttr = "name";
        refs.mount = mountRef "mount" false;
        description = "LDAP secrets engine service account libraries, keyed by name.";
      };
      ldap_secret_static_roles = {
        type = "vault_ldap_secret_backend_static_role";
        prefix = "ldap_static_role";
        nameAttr = "role_name";
        refs.mount = mountRef "mount" false;
        description = "LDAP secrets engine static roles, keyed by role name.";
      };
      rabbitmq_secret_backends = {
        type = "vault_rabbitmq_secret_backend";
        prefix = "rabbitmq_secrets";
        nameAttr = "path";
        refs.password_policy = passwordPolicyRef "password_policy";
        description = "RabbitMQ secrets engine mounts with their configuration, keyed by path.";
      };
      rabbitmq_secret_roles = {
        type = "vault_rabbitmq_secret_backend_role";
        prefix = "rabbitmq_role";
        nameAttr = "name";
        refs.backend = mountRef "backend" true;
        description = "RabbitMQ secrets engine roles, keyed by name.";
      };
      ssh_cas = {
        type = "vault_ssh_secret_backend_ca";
        prefix = "ssh_ca";
        nameAttr = null;
        refs.backend = mountRef "backend" false;
        description = "SSH secrets engine CA keys, keyed by an arbitrary handle. Declare at most one per mount. Without `private_key`, OpenBao generates the key pair, and the private key does not leave OpenBao.";
      };
      ssh_roles = {
        type = "vault_ssh_secret_backend_role";
        prefix = "ssh_role";
        nameAttr = "name";
        refs.backend = mountRef "backend" true;
        description = "SSH secrets engine roles, keyed by name.";
      };
      transit_keys = {
        type = "vault_transit_secret_backend_key";
        prefix = "transit_key";
        nameAttr = "name";
        refs.backend = mountRef "backend" true;
        description = "Transit secrets engine keys, keyed by name.";
      };
      transit_cache_configs = {
        type = "vault_transit_secret_cache_config";
        prefix = "transit_cache_config";
        nameAttr = null;
        refs.backend = mountRef "backend" true;
        description = "Transit secrets engine cache configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };

      # PKI secrets engine.
      pki_keys = {
        type = "vault_pki_secret_backend_key";
        prefix = "pki_key";
        nameAttr = "key_name";
        refs = pki { };
        description = "PKI keys, keyed by key name. A generated key does not leave OpenBao.";
      };
      pki_root_certs = {
        type = "vault_pki_secret_backend_root_cert";
        prefix = "pki_root";
        nameAttr = "issuer_name";
        refs = pki { key_ref = pkiKeyRef "key_ref"; };
        description = "PKI root CA certificates, keyed by issuer name.";
      };
      pki_intermediate_cert_requests = {
        type = "vault_pki_secret_backend_intermediate_cert_request";
        prefix = "pki_intermediate_csr";
        nameAttr = null;
        refs = pki { key_ref = pkiKeyRef "key_ref"; };
        description = "PKI intermediate CA certificate signing requests, keyed by an arbitrary handle. With `type = \"exported\"`, the private key goes only into the Terraform state.";
      };
      pki_root_sign_intermediates = {
        type = "vault_pki_secret_backend_root_sign_intermediate";
        prefix = "pki_sign_intermediate";
        nameAttr = null;
        refs = pki {
          csr = ref (on "csr" [ "pki_intermediate_cert_requests" ]) {
            attr = "csr";
            required = true;
            description = "Certificate signing request: the key of a managed intermediate certificate request, or a literal PEM CSR.";
          };
          issuer_ref = issuerRef "issuer_ref" false;
        };
        description = "Intermediate CA certificates that a PKI root signs, keyed by an arbitrary handle.";
      };
      pki_intermediate_set_signed = {
        type = "vault_pki_secret_backend_intermediate_set_signed";
        prefix = "pki_set_signed";
        nameAttr = null;
        refs = pki {
          certificate = ref (on "certificate" [ "pki_root_sign_intermediates" ]) {
            attr = "certificate";
            required = true;
            description = "Signed intermediate CA certificate: the key of a managed signed intermediate, or a literal PEM certificate.";
          };
        };
        description = "Signed intermediate CA certificates to import into a PKI mount, keyed by an arbitrary handle.";
      };
      pki_issuers = {
        type = "vault_pki_secret_backend_issuer";
        prefix = "pki_issuer";
        nameAttr = null;
        refs = pki { issuer_ref = issuerRef "issuer_ref" true; };
        description = "PKI issuer settings, keyed by an arbitrary handle.";
      };
      pki_roles = {
        type = "vault_pki_secret_backend_role";
        prefix = "pki_role";
        nameAttr = "name";
        refs = pki { issuer_ref = issuerRef "issuer_ref" false; };
        description = "PKI roles, keyed by name.";
      };
      pki_acme_eabs = {
        type = "vault_pki_secret_backend_acme_eab";
        prefix = "pki_acme_eab";
        nameAttr = null;
        refs = pki {
          role = ref (on "name" [ "pki_roles" ]) {
            attr = "role";
            description = "PKI role: the key of a managed PKI role, or a literal role name.";
          };
          issuer = issuerRef "issuer" false;
        };
        description = "ACME external account bindings, keyed by an arbitrary handle. The key goes only into the Terraform state.";
      };
      pki_config_acme = {
        type = "vault_pki_secret_backend_config_acme";
        prefix = "pki_config_acme";
        nameAttr = null;
        refs = pki { };
        description = "PKI ACME configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      pki_config_auto_tidy = {
        type = "vault_pki_secret_backend_config_auto_tidy";
        prefix = "pki_config_auto_tidy";
        nameAttr = null;
        refs = pki { };
        description = "PKI automatic tidy configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      pki_config_ca = {
        type = "vault_pki_secret_backend_config_ca";
        prefix = "pki_config_ca";
        nameAttr = null;
        refs = pki { };
        description = "PKI CA bundles to import, keyed by an arbitrary handle.";
      };
      pki_config_cluster = {
        type = "vault_pki_secret_backend_config_cluster";
        prefix = "pki_config_cluster";
        nameAttr = null;
        refs = pki { };
        description = "PKI cluster URLs, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      pki_config_issuers = {
        type = "vault_pki_secret_backend_config_issuers";
        prefix = "pki_config_issuers";
        nameAttr = null;
        refs = pki { default = issuerRef "default" false; };
        description = "PKI default issuer, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      pki_config_urls = {
        type = "vault_pki_secret_backend_config_urls";
        prefix = "pki_urls";
        nameAttr = null;
        refs = pki { };
        description = "PKI issuing certificate, CRL and OCSP URLs, keyed by an arbitrary handle. Declare at most one per mount.";
      };
      pki_config_crl = {
        type = "vault_pki_secret_backend_crl_config";
        prefix = "pki_config_crl";
        nameAttr = null;
        refs = pki { };
        description = "PKI CRL configuration, keyed by an arbitrary handle. Declare at most one per mount.";
      };

      # Identity.
      identity_entities = {
        type = "vault_identity_entity";
        prefix = "entity";
        nameAttr = "name";
        refs.policies = policiesRef "policies" { };
        description = "Identity entities, keyed by name.";
      };
      identity_entity_aliases = {
        type = "vault_identity_entity_alias";
        prefix = "entity_alias";
        nameAttr = "name";
        refs = {
          canonical_id = entityRef "canonical_id" { required = true; };
          mount_accessor = accessorRef "mount_accessor" { required = true; };
        };
        description = "Identity entity aliases, keyed by the name of the alias in its auth method.";
      };
      identity_entity_policies = {
        type = "vault_identity_entity_policies";
        prefix = "entity_policies";
        nameAttr = null;
        refs = {
          entity_id = entityRef "entity_id" { required = true; };
          policies = policiesRef "policies" { required = true; };
        };
        description = "Policies of an identity entity, keyed by an arbitrary handle. Leave `policies` unset in `identity_entities` for an entity that this manages.";
      };
      identity_groups = {
        type = "vault_identity_group";
        prefix = "group";
        nameAttr = "name";
        refs = {
          policies = policiesRef "policies" { };
          member_entity_ids = entityRef "member_entity_ids" {
            list = true;
            description = "Member entities: keys of managed entities, or literal entity IDs.";
          };
          member_group_ids = groupRef "member_group_ids" {
            list = true;
            description = "Member groups: keys of managed groups, or literal group IDs.";
          };
        };
        description = "Identity groups, keyed by name.";
      };
      identity_group_aliases = {
        type = "vault_identity_group_alias";
        prefix = "group_alias";
        nameAttr = "name";
        refs = {
          canonical_id = groupRef "canonical_id" { required = true; };
          mount_accessor = accessorRef "mount_accessor" { required = true; };
        };
        description = "Identity group aliases, keyed by the name of the group in its auth method.";
      };
      identity_group_member_entity_ids = {
        type = "vault_identity_group_member_entity_ids";
        prefix = "group_member_entities";
        nameAttr = null;
        refs = {
          group_id = groupRef "group_id" { required = true; };
          member_entity_ids = entityRef "member_entity_ids" {
            list = true;
            description = "Member entities: keys of managed entities, or literal entity IDs.";
          };
        };
        description = "Member entities of an identity group, keyed by an arbitrary handle. Set `external_member_entity_ids = true` in `identity_groups` for a group that this manages.";
      };
      identity_group_member_group_ids = {
        type = "vault_identity_group_member_group_ids";
        prefix = "group_member_groups";
        nameAttr = null;
        refs = {
          group_id = groupRef "group_id" { required = true; };
          member_group_ids = groupRef "member_group_ids" {
            list = true;
            description = "Member groups: keys of managed groups, or literal group IDs.";
          };
        };
        description = "Member groups of an identity group, keyed by an arbitrary handle. Set `external_member_group_ids = true` in `identity_groups` for a group that this manages.";
      };
      identity_group_policies = {
        type = "vault_identity_group_policies";
        prefix = "group_policies";
        nameAttr = null;
        refs = {
          group_id = groupRef "group_id" { required = true; };
          policies = policiesRef "policies" { required = true; };
        };
        description = "Policies of an identity group, keyed by an arbitrary handle. Set `external_policies = true` in `identity_groups` for a group that this manages.";
      };
      identity_mfa_duo = {
        type = "vault_identity_mfa_duo";
        prefix = "mfa_duo";
        nameAttr = null;
        description = "Duo MFA methods, keyed by an arbitrary handle.";
      };
      identity_mfa_okta = {
        type = "vault_identity_mfa_okta";
        prefix = "mfa_okta";
        nameAttr = null;
        description = "Okta MFA methods, keyed by an arbitrary handle.";
      };
      identity_mfa_pingid = {
        type = "vault_identity_mfa_pingid";
        prefix = "mfa_pingid";
        nameAttr = null;
        description = "PingID MFA methods, keyed by an arbitrary handle.";
      };
      identity_mfa_totp = {
        type = "vault_identity_mfa_totp";
        prefix = "mfa_totp";
        nameAttr = null;
        description = "TOTP MFA methods, keyed by an arbitrary handle.";
      };
      identity_mfa_login_enforcements = {
        type = "vault_identity_mfa_login_enforcement";
        prefix = "mfa_login_enforcement";
        nameAttr = "name";
        refs = {
          mfa_method_ids =
            ref
              (on "method_id" [
                "identity_mfa_duo"
                "identity_mfa_okta"
                "identity_mfa_pingid"
                "identity_mfa_totp"
              ])
              {
                attr = "mfa_method_ids";
                list = true;
                required = true;
                description = "MFA methods: keys of managed MFA methods, or literal method IDs.";
              };
          auth_method_accessors = accessorRef "auth_method_accessors" {
            list = true;
            description = "Auth methods to enforce MFA on: keys of managed auth methods, or literal accessors.";
          };
          identity_entity_ids = entityRef "identity_entity_ids" {
            list = true;
            description = "Entities to enforce MFA on: keys of managed entities, or literal entity IDs.";
          };
          identity_group_ids = groupRef "identity_group_ids" {
            list = true;
            description = "Groups to enforce MFA on: keys of managed groups, or literal group IDs.";
          };
        };
        description = "MFA login enforcements, keyed by name.";
      };

      # Identity tokens and the OIDC provider.
      identity_oidc = {
        type = "vault_identity_oidc";
        prefix = "oidc";
        nameAttr = null;
        description = "Identity token issuer configuration, keyed by an arbitrary handle. Declare at most one per namespace.";
      };
      identity_oidc_keys = {
        type = "vault_identity_oidc_key";
        prefix = "oidc_key";
        nameAttr = "name";
        description = "Identity token and OIDC signing keys, keyed by name. To allow a managed OIDC client, use `identity_oidc_key_allowed_client_ids`: a reference from here would make a cycle with the client's `key`.";
      };
      identity_oidc_key_allowed_client_ids = {
        type = "vault_identity_oidc_key_allowed_client_id";
        prefix = "oidc_key_client";
        nameAttr = null;
        refs = {
          key_name = oidcKeyRef "key_name" true;
          allowed_client_id = oidcClientRef "allowed_client_id" { required = true; };
        };
        description = "Clients that a signing key allows, one each, keyed by an arbitrary handle.";
      };
      identity_oidc_roles = {
        type = "vault_identity_oidc_role";
        prefix = "oidc_role";
        nameAttr = "name";
        refs = {
          key = oidcKeyRef "key" true;
          client_id = oidcClientRef "client_id" { };
        };
        description = "Identity token roles, keyed by name.";
      };
      identity_oidc_assignments = {
        type = "vault_identity_oidc_assignment";
        prefix = "oidc_assignment";
        nameAttr = "name";
        refs = {
          entity_ids = entityRef "entity_ids" {
            list = true;
            description = "Entities: keys of managed entities, or literal entity IDs.";
          };
          group_ids = groupRef "group_ids" {
            list = true;
            description = "Groups: keys of managed groups, or literal group IDs.";
          };
        };
        description = "OIDC provider assignments, keyed by name.";
      };
      identity_oidc_clients = {
        type = "vault_identity_oidc_client";
        prefix = "oidc_client";
        nameAttr = "name";
        refs = {
          key = oidcKeyRef "key" false;
          assignments = ref (on "name" [ "identity_oidc_assignments" ]) {
            attr = "assignments";
            list = true;
            description = "Assignments: keys of managed assignments, or literal assignment names (such as `allow_all`).";
          };
        };
        description = "OIDC provider clients, keyed by name. The client secret goes only into the Terraform state.";
      };
      identity_oidc_scopes = {
        type = "vault_identity_oidc_scope";
        prefix = "oidc_scope";
        nameAttr = "name";
        description = "OIDC provider scopes, keyed by name.";
      };
      identity_oidc_providers = {
        type = "vault_identity_oidc_provider";
        prefix = "oidc_provider";
        nameAttr = "name";
        refs = {
          allowed_client_ids = oidcClientRef "allowed_client_ids" {
            list = true;
            description = "Clients: keys of managed OIDC clients, or literal client IDs (`*` for all).";
          };
          scopes_supported = ref (on "name" [ "identity_oidc_scopes" ]) {
            attr = "scopes_supported";
            list = true;
            description = "Scopes: keys of managed scopes, or literal scope names.";
          };
        };
        description = "OIDC providers, keyed by name.";
      };
    };
  };
  inherit (generated) resourceTypes;

  openbaoTfConfig = genlib.mkTfConfig {
    inherit
      resourceTypes
      providerVersion
      providerSource
      runtimePrefix
      tokenVar
      ;
    providerName = "vault";
    providerBlock =
      cfg:
      {
        inherit (cfg) address;
        token = "\${var.${tokenVar}}";
        # The reconciler is the only client of its token, so a child token
        # buys nothing, and it would need `auth/token/create`.
        skip_child_token = true;
      }
      // lib.optionalAttrs (cfg.caCertFile != null) { ca_cert_file = cfg.caCertFile; };
  };
in
{
  inherit
    provider
    providerSource
    resourceTypes
    openbaoTfConfig
    ;
  # the generator's drift assertions and coverage data, for the pairing's checks
  # to force independently of any particular configuration.
  inherit (generated) checks coverage;
  resourceOptions = genlib.resourceOptions resourceTypes;
  mkReconcileService = args: genlib.mkReconcileService (args // { inherit executor tokenVar; });
}

# jkossis/garage provider specifics: executor, resource surface, provider block.
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
  providerSource = "jkossis/garage";
  runtimePrefix = "services.garage.runtime";
  tokenVar = "garage_admin_token";
  executor = pkgs.opentofu.withPlugins (_: [ provider ]);

  # The jkossis/garage resource surface. Per collection, only the facts the
  # schema does not carry (see modules/lib/tf-schema.nix for the full overlay
  # vocabulary). `scope` is null throughout: a Garage admin token is not scoped
  # per resource kind.
  generated = tfSchema.mkResourceTypes {
    schema = import ./schema.nix;
    inherit provider runtimePrefix;
    source = providerSource;
    resources = {
      buckets = {
        type = "garage_bucket";
        prefix = "bucket";
        # A bucket gets one global alias from the provider, which is the key.
        nameAttr = "global_alias";
        scope = null;
        refs = { };
        description = "Garage buckets, keyed by global alias.";
      };
      keys = {
        type = "garage_key";
        prefix = "key";
        nameAttr = "name";
        scope = null;
        refs = { };
        description = "Garage access keys, keyed by key name.";
      };
      bucket_permissions = {
        type = "garage_bucket_permission";
        prefix = "bucket_permission";
        nameAttr = null;
        scope = null;
        refs = {
          bucket = {
            attr = "bucket_id";
            targets = [
              {
                collection = "buckets";
                field = "id";
              }
            ];
            managedOnly = false;
            required = true;
            description = "Bucket the grant is on: the key of a managed bucket, or a literal bucket id.";
          };
          key = {
            attr = "access_key_id";
            targets = [
              {
                collection = "keys";
                field = "id";
              }
            ];
            managedOnly = false;
            required = true;
            description = "Access key the grant is for: the key of a managed access key, or a literal access key id.";
          };
        };
        description = "Garage bucket permissions of an access key, keyed by an arbitrary label.";
      };
    };
  };
  inherit (generated) resourceTypes;

  garageTfConfig = genlib.mkTfConfig {
    inherit
      resourceTypes
      providerVersion
      providerSource
      runtimePrefix
      tokenVar
      ;
    providerName = "garage";
    providerBlock = cfg: {
      endpoint = cfg.baseUrl;
      token = "\${var.${tokenVar}}";
    };
  };
in
{
  inherit
    provider
    providerSource
    resourceTypes
    garageTfConfig
    ;
  # the generator's drift assertions and coverage data, for the pairing's checks
  # to force independently of any particular configuration.
  inherit (generated) checks coverage;
  resourceOptions = genlib.resourceOptions resourceTypes;
  mkReconcileService = args: genlib.mkReconcileService (args // { inherit executor tokenVar; });
}

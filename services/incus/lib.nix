# lxc/incus provider specifics: executor, resource surface, provider block.
#
# The resource surface is *derived* from the vendored provider schema
# (./provider-schema.json, parsed by ./schema.nix) via
# ../../modules/lib/tf-schema.nix. What stays hand-written is only what a schema
# cannot state: the NixOS-facing collection descriptions, the reference graph
# between collections, and the import IDs of the objects that incus or its
# preseed make before the reconciler runs.
#
# Shared helpers (option helpers, renderer, reconciler) live in modules/lib.
{ pkgs, nix-tf-schema }:
let
  inherit (pkgs) lib;
  genlib = import ../../modules/lib { inherit pkgs; };
  tfSchema = import ../../modules/lib/tf-schema.nix { inherit pkgs nix-tf-schema; };

  provider = pkgs.terraform-providers.lxc_incus;
  providerVersion = provider.version;
  # provider source address; also keys the vendored provider schema.
  providerSource = "lxc/incus";
  # incus has no `services.incus`: its NixOS module is `virtualisation.incus`.
  runtimePrefix = "virtualisation.incus.runtime";
  executor = pkgs.opentofu.withPlugins (_: [ provider ]);

  # A reference to an object by its name. The literal fallback is for objects
  # that incus makes itself (the `default` project, say) or that a different
  # tool manages.
  nameRef = collection: {
    targets = [
      {
        inherit collection;
        field = "name";
      }
    ];
    managedOnly = false;
  };
  projectRef = nameRef "projects" // {
    attr = "project";
    description = "Project of the object: the key of a managed project, or a literal project name. Unset means the `default` project.";
  };
  networkRef =
    required:
    nameRef "networks"
    // {
      attr = "network";
      inherit required;
      description = "Network of the object: the key of a managed network, or a literal network name.";
    };
  poolRef = nameRef "storage_pools" // {
    attr = "pool";
    required = true;
    description = "Storage pool of the object: the key of a managed storage pool, or a literal pool name.";
  };

  # The import ID of an object that the provider identifies by its project and
  # name: `[<project>/]<name>`. The provider also accepts a remote prefix, but
  # the reconciler talks to the local daemon only.
  projectScopedId = v: lib.optionalString (v ? project) "${v.project}/" + v.name;

  # The lxc/incus resource surface. Per collection, only the facts the schema
  # does not carry (see modules/lib/tf-schema.nix for the full overlay
  # vocabulary). `scope` is null throughout: the reconciler talks to the local
  # unix socket as root, which has full access.
  #
  # Profile devices refer to networks and pools by literal name: refs are top
  # level only, and a device's properties are a map. OpenTofu thus does not
  # know that a profile depends on the network or pool its devices name. When
  # the same apply creates both, the profile can come first and fail. The
  # usual case, a profile that uses a network and pool that exist already, is
  # not affected.
  generated = tfSchema.mkResourceTypes {
    schema = import ./schema.nix;
    inherit provider runtimePrefix;
    source = providerSource;
    # The provider block configures no remote: the reconciler manages the
    # local daemon only.
    omitEverywhere = [ "remote" ];
    unsupported = {
      incus_instance = "An instance is a workload with a lifecycle of its own, not configuration of the host.";
      incus_instance_snapshot = "A snapshot is a point-in-time copy of an instance, which is not modelled.";
      incus_image = "An image belongs with the instances that use it, which are not modelled.";
    };
    resources = {
      certificates = {
        type = "incus_certificate";
        prefix = "certificate";
        nameAttr = "name";
        scope = null;
        refs = {
          projects = nameRef "projects" // {
            attr = "projects";
            list = true;
            description = "Projects that a restricted certificate can access: keys of managed projects, or literal project names.";
          };
        };
        # The certificate is public, but a host often mints it at runtime (a
        # client key pair made at first boot, say). A `<attr>File` sibling is
        # the only way to read a file at apply time.
        extraSecrets = [ "certificate" ];
        description = "Certificates in the trust store, keyed by name. Give the PEM inline, or the path of a file on the host with `certificateFile`.";
      };
      cluster_groups = {
        type = "incus_cluster_group";
        prefix = "cluster_group";
        nameAttr = "name";
        scope = null;
        refs = { };
        description = "Cluster groups, keyed by name.";
      };
      networks = {
        type = "incus_network";
        prefix = "network";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        importId = projectScopedId;
        description = "Networks, keyed by name. Keys of `config` that the network computes (`ipv4.address` when not set, say) are kept, and other keys that are not in `config` are removed.";
      };
      network_acls = {
        type = "incus_network_acl";
        prefix = "network_acl";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        description = "Network ACLs, keyed by name.";
      };
      network_address_sets = {
        type = "incus_network_address_set";
        prefix = "network_address_set";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        description = "Network address sets, keyed by name.";
      };
      network_forwards = {
        type = "incus_network_forward";
        prefix = "network_forward";
        nameAttr = null;
        scope = null;
        refs = {
          project = projectRef;
          network = networkRef true;
        };
        description = "Network forwards, keyed by an arbitrary label. A forward is identified by its network and listen address.";
      };
      network_integrations = {
        type = "incus_network_integration";
        prefix = "network_integration";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        description = "Network integrations, keyed by name.";
      };
      network_lbs = {
        type = "incus_network_lb";
        prefix = "network_lb";
        nameAttr = null;
        scope = null;
        refs = {
          project = projectRef;
          network = networkRef true;
        };
        description = "Network load balancers, keyed by an arbitrary label. A load balancer is identified by its network and listen address.";
      };
      network_peers = {
        type = "incus_network_peer";
        prefix = "network_peer";
        nameAttr = "name";
        scope = null;
        refs = {
          project = projectRef;
          network = networkRef false;
          target_network = nameRef "networks" // {
            attr = "target_network";
            description = "Network to peer with: the key of a managed network, or a literal network name.";
          };
          target_project = nameRef "projects" // {
            attr = "target_project";
            description = "Project of the network to peer with: the key of a managed project, or a literal project name.";
          };
        };
        description = "Network peerings, keyed by name.";
      };
      network_zones = {
        type = "incus_network_zone";
        prefix = "network_zone";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        description = "Network DNS zones, keyed by name.";
      };
      network_zone_records = {
        type = "incus_network_zone_record";
        prefix = "network_zone_record";
        nameAttr = "name";
        scope = null;
        refs = {
          project = projectRef;
          zone = nameRef "network_zones" // {
            attr = "zone";
            required = true;
            description = "Zone of the record: the key of a managed network zone, or a literal zone name.";
          };
        };
        description = "Records in network DNS zones, keyed by name.";
      };
      profiles = {
        type = "incus_profile";
        prefix = "profile";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        # Not needed for the `default` profile: the provider changes that
        # profile in place when it creates it, and resets it when it destroys
        # it.
        importId = projectScopedId;
        description = "Profiles, keyed by name. Devices name their networks and pools literally, so OpenTofu does not order a profile after them.";
      };
      projects = {
        type = "incus_project";
        prefix = "project";
        nameAttr = "name";
        scope = null;
        refs = { };
        importId = v: v.name;
        description = "Projects, keyed by name.";
      };
      server = {
        type = "incus_server";
        prefix = "server";
        nameAttr = null;
        scope = null;
        refs = { };
        description = "Server configuration, keyed by an arbitrary label. Set one entry at most. Only the keys in `config` are managed; other server keys are kept.";
      };
      storage_pools = {
        type = "incus_storage_pool";
        prefix = "storage_pool";
        nameAttr = "name";
        scope = null;
        refs.project = projectRef;
        importId = projectScopedId;
        description = "Storage pools, keyed by name. Keys of `config` that the pool computes (`source`, say) are kept.";
      };
      storage_buckets = {
        type = "incus_storage_bucket";
        prefix = "storage_bucket";
        nameAttr = "name";
        scope = null;
        refs = {
          project = projectRef;
          pool = poolRef;
        };
        description = "Storage buckets, keyed by name.";
      };
      storage_bucket_keys = {
        type = "incus_storage_bucket_key";
        prefix = "storage_bucket_key";
        nameAttr = "name";
        scope = null;
        refs = {
          project = projectRef;
          pool = poolRef;
          storage_bucket = nameRef "storage_buckets" // {
            attr = "storage_bucket";
            required = true;
            description = "Bucket of the key: the key of a managed storage bucket, or a literal bucket name.";
          };
        };
        description = "Access keys of storage buckets, keyed by name. incus makes the access and secret keys; they are in the state only.";
      };
      storage_volumes = {
        type = "incus_storage_volume";
        prefix = "storage_volume";
        nameAttr = "name";
        scope = null;
        refs = {
          project = projectRef;
          pool = poolRef;
        };
        description = "Custom storage volumes, keyed by name.";
      };
    };
  };
  inherit (generated) resourceTypes;

  incusTfConfig = genlib.mkTfConfig {
    inherit
      resourceTypes
      providerVersion
      providerSource
      runtimePrefix
      ;
    providerName = "incus";
    providerBlock = cfg: {
      # A directory with no `config.yml`, so that the provider uses its
      # default configuration: the `local` remote on the local unix socket.
      # The default, `$HOME/.config/incus`, can hold the remotes of an admin.
      config_dir = cfg.configDir;
    };
  };
in
{
  inherit
    provider
    providerSource
    runtimePrefix
    resourceTypes
    incusTfConfig
    ;
  # the generator's drift assertions and coverage data, for the pairing's checks
  # to force independently of any particular configuration.
  inherit (generated) checks coverage;
  resourceOptions = genlib.resourceOptions resourceTypes;
  mkReconcileService = args: genlib.mkReconcileService (args // { inherit executor; });
}

# tasansga/lldap Terraform/OpenTofu provider, built from source.
#
# Not packaged in the pinned nixpkgs, so we vendor it here using the nixpkgs
# `terraform-providers.mkProvider` builder, same as ../forgejo/pkg.nix. lldap's
# own project publishes no provider; this is the one the registry lists.
#
# To update: bump `rev`, then refresh `hash` (source) and `vendorHash` (Go
# module set) together.
{ pkgs }:
(pkgs.terraform-providers.mkProvider {
  owner = "tasansga";
  repo = "terraform-provider-lldap";
  rev = "v0.4.4";
  spdx = "MPL-2.0";
  hash = "sha256-P87NPce4yd9uQG76oNJcs07y74WvC9ZZR0IbaTOZU58=";
  vendorHash = "sha256-5kRtjoxe0p3kt4/nNqR///jMm4x6PdoRUOdciqhp58s=";
  homepage = "https://registry.terraform.io/providers/tasansga/lldap";
}).overrideAttrs
  (_: {
    # The `main` package is not at the root of the repository, where
    # `mkProvider` builds it. The repository also has a CLI, which this does
    # not build.
    subPackages = [ "cmd/terraform-provider-lldap" ];
  })
